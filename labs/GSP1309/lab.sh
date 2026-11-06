#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP1309 — Dynamic volume provisioning on GKE with Google Cloud NetApp Volumes
# static validated only; runtime/grader unverified

_gsp1309_main() (
  set -Eeuo pipefail
  export LC_ALL=C

  if [[ -n "${NO_COLOR+x}" ]]; then
    BLUE='' GREEN='' YELLOW='' RED='' RESET=''
  elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
    BLUE=$'\033[1;34m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; RESET=$'\033[0m'
  else
    BLUE='' GREEN='' YELLOW='' RED='' RESET=''
  fi
  info() { printf '%s%s%s\n' "$BLUE" "$*" "$RESET"; }
  ok() { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
  warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
  fail() { printf '%s%s%s\n' "$RED" "$*" "$RESET" >&2; return 1; }
  retry() {
    local count=0
    until "$@"; do
      count=$((count + 1))
      if (( count >= 4 )); then return 1; fi
      sleep "$((count * 4))"
    done
  }
  require() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }
  info 'ePlus.DEV – Starting Execution | GSP1309'
  printf 'Copyright (c) 2026 ePlus.DEV | Unlicense\n'
  for cmd in gcloud kubectl curl tar python3; do require "$cmd"; done

  local project cluster_location project_number pool_json zone sa_email work key_json key_id client_id
  project="${GOOGLE_CLOUD_PROJECT:-${DEVSHELL_PROJECT_ID:-}}"
  if [[ -z "$project" ]]; then project="$(gcloud config get-value project 2>/dev/null || true)"; fi
  [[ -n "$project" && "$project" != '(unset)' ]] || fail 'No lab project detected.'
  project_number="$(gcloud projects describe "$project" --format='value(projectNumber)')"
  [[ "$project_number" =~ ^[0-9]+$ ]] || fail 'Unable to detect project number.'

  cluster_location="${LAB_CLUSTER_LOCATION:-}"
  if [[ -z "$cluster_location" ]]; then
    cluster_location="$(gcloud container clusters list --project="$project" --filter='name=cluster1' --format='value(location)' | head -n 1)"
  fi
  [[ -n "$cluster_location" ]] || fail 'Cluster cluster1 not found. Set LAB_CLUSTER_LOCATION if necessary.'
  info "Project: $project | GKE cluster: cluster1 ($cluster_location)"
  retry gcloud container clusters get-credentials cluster1 --location="$cluster_location" --project="$project" --quiet
  kubectl get nodes >/dev/null

  zone="${LAB_ZONE:-}"
  if [[ -z "$zone" ]]; then
    pool_json="$(gcloud netapp storage-pools list --project="$project" --format=json)"
    zone="$(printf '%s' "$pool_json" | python3 -c '
import json,re,sys
pools=json.load(sys.stdin)
zones=sorted({m.group(1) for p in pools for m in [re.search(r"/locations/([a-z]+-[a-z0-9]+-[a-z])/",p.get("name", ""))] if m})
print(zones[0] if len(zones)==1 else "")
')"
  fi
  if [[ -z "$zone" ]]; then zone="$(gcloud config get-value compute/zone 2>/dev/null || true)"; fi
  [[ "$zone" =~ ^[a-z]+-[a-z0-9]+-[a-z]$ ]] || fail 'Cannot uniquely determine zonal NetApp pool; set LAB_ZONE to its actual zone.'
  info "NetApp zonal pool location: $zone"

  work="$(mktemp -d)"
  chmod 700 "$work"
  trap 'rm -rf "$work"' EXIT

  info 'Task 1 — Install NetApp Trident v25.02.0'
  if ! kubectl get tridentorchestrator trident -n trident >/dev/null 2>&1; then
    retry curl -fLsS --retry 3 --connect-timeout 15 --max-time 120 \
      'https://github.com/NetApp/trident/releases/download/v25.02.0/trident-installer-25.02.0.tar.gz' \
      -o "$work/trident-installer.tar.gz"
    tar -tzf "$work/trident-installer.tar.gz" >/dev/null
    tar -xzf "$work/trident-installer.tar.gz" -C "$work"
    kubectl apply -f "$work/trident-installer/deploy/crds/trident.netapp.io_tridentorchestrators_crd_post1.16.yaml"
    kubectl create namespace trident --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "$work/trident-installer/deploy/bundle_post_1_25.yaml"
    kubectl -n trident rollout status deployment/trident-operator --timeout=300s
    kubectl apply -f "$work/trident-installer/deploy/crds/tridentorchestrator_cr.yaml"
  else
    ok 'Trident orchestrator already exists; reusing it.'
  fi
  local i ready=0
  for ((i=0;i<36;i++)); do
    if kubectl -n trident get deployment trident-controller >/dev/null 2>&1 && \
       kubectl -n trident rollout status deployment/trident-controller --timeout=10s >/dev/null 2>&1; then
      ready=1; break
    fi
    sleep 10
  done
  ((ready==1)) || fail 'Trident controller did not become ready in 6 minutes.'
  ok 'Task 1: Trident controller ready (grader unverified).'

  info 'Task 2 — Service account, Kubernetes Secret, backend and StorageClass'
  sa_email="netapp-trident@${project}.iam.gserviceaccount.com"
  if ! gcloud iam service-accounts describe "$sa_email" --project="$project" >/dev/null 2>&1; then
    gcloud iam service-accounts create netapp-trident --project="$project" \
      --description='Service account for NetApp Trident lab' --display-name='NetApp Trident'
  fi
  # This role is explicitly required by the official lab; scope is the temporary lab project.
  if ! gcloud projects get-iam-policy "$project" --flatten='bindings[].members' \
    --filter="bindings.role=roles/netapp.admin AND bindings.members=serviceAccount:$sa_email" \
    --format='value(bindings.role)' | grep -Fxq 'roles/netapp.admin'; then
    gcloud projects add-iam-policy-binding "$project" --member="serviceAccount:$sa_email" \
      --role='roles/netapp.admin' --condition=None --quiet >/dev/null
  fi

  if ! kubectl -n trident get secret gcnv-secret >/dev/null 2>&1 || \
     ! kubectl -n trident get tridentbackendconfig gcnv-zonal-flex >/dev/null 2>&1; then
    key_json="$work/netapp-trident-key.json"
    umask 077
    # The official lab requires a key-backed Trident backend. Never log or commit the key.
    gcloud iam service-accounts keys create "$key_json" --iam-account="$sa_email" \
      --project="$project" --quiet >/dev/null
    python3 - "$key_json" "$work" <<'PY'
import json, pathlib, sys
key=json.loads(pathlib.Path(sys.argv[1]).read_text())
for field in ('private_key_id','private_key'):
    pathlib.Path(sys.argv[2],field).write_text(key[field])
PY
    client_id="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["client_id"])' "$key_json")"
    [[ "$client_id" =~ ^[0-9]+$ ]] || fail 'Invalid OAuth client_id from newly created key.'
    kubectl -n trident create secret generic gcnv-secret \
      --from-file="private_key_id=$work/private_key_id" \
      --from-file="private_key=$work/private_key" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    # The private key is now only in Kubernetes Secret; remove local copies immediately.
    rm -f "$key_json" "$work/private_key_id" "$work/private_key"
  else
    ok 'Kubernetes Secret and backend already exist; no new key created.'
    client_id=''
  fi

  if ! kubectl -n trident get tridentbackendconfig gcnv-zonal-flex >/dev/null 2>&1; then
    [[ -n "$client_id" ]] || fail 'Cannot construct backend without OAuth client_id.'
    cat > "$work/backend.yaml" <<EOF
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: gcnv-zonal-flex
  namespace: trident
spec:
  version: 1
  storageDriverName: google-cloud-netapp-volumes
  backendName: gcnv-zonal-flex
  projectNumber: '$project_number'
  location: '$zone'
  apiKey:
    type: service_account
    project_id: '$project'
    client_email: '$sa_email'
    client_id: '$client_id'
    auth_uri: https://accounts.google.com/o/oauth2/auth
    token_uri: https://oauth2.googleapis.com/token
    auth_provider_x509_cert_url: https://www.googleapis.com/oauth2/v1/certs
    client_x509_cert_url: https://www.googleapis.com/robot/v1/metadata/x509/$sa_email
  credentials:
    name: gcnv-secret
  storage:
    - labels:
        performance: flex
        availability: zonal
      serviceLevel: flex
EOF
    kubectl apply -f "$work/backend.yaml"
  fi
  for ((i=0;i<30;i++)); do
    local phase
    phase="$(kubectl -n trident get tridentbackendconfig gcnv-zonal-flex -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "$phase" == 'Bound' ]] && break
    [[ "$phase" == 'Failed' ]] && fail 'Trident backend entered Failed state; inspect kubectl describe tridentbackendconfig.'
    sleep 10
  done
  kubectl -n trident get tridentbackendconfig gcnv-zonal-flex
  cat > "$work/storageclass.yaml" <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gcnv-zonal-flex
provisioner: csi.trident.netapp.io
parameters:
  backendType: google-cloud-netapp-volumes
  selector: 'performance=flex; availability=zonal'
allowVolumeExpansion: true
EOF
  kubectl apply -f "$work/storageclass.yaml"
  kubectl get storageclass gcnv-zonal-flex >/dev/null
  ok 'Task 2: Secret, backend and StorageClass created (grader unverified).'

  info 'Task 3 — Request 1Gi ReadWriteMany PVC'
  cat > "$work/pvc.yaml" <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-zonal-flex
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: gcnv-zonal-flex
  resources:
    requests:
      storage: 1Gi
EOF
  kubectl apply -f "$work/pvc.yaml"
  ready=0
  for ((i=0;i<36;i++)); do
    if [[ "$(kubectl get pvc pvc-zonal-flex -o jsonpath='{.status.phase}' 2>/dev/null || true)" == Bound ]]; then
      ready=1; break
    fi
    sleep 10
  done
  kubectl get pvc pvc-zonal-flex
  ((ready==1)) || fail 'PVC did not bind in 6 minutes; check NetApp pool capacity and Trident logs.'
  kubectl get pv
  ok 'Task 3: PVC Bound. Run Check my progress in Google Skills.'
  warn 'static validated only; runtime/grader unverified. No lab account used by the author.'
  warn 'The temporary lab service-account key remains in the Kubernetes Secret for Trident. Remove it after grading.'
)
_gsp1309_main "$@"
