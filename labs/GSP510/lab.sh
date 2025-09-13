#!/usr/bin/env bash
# ======================================================================
#  Manage Kubernetes in Google Cloud - Challenge Lab (GSP510-style)
#  Full automation script with colors & lightweight idempotency
#
#  © 2025 ePlus.dev – Authored for educational/lab use.
#  License: MIT. Use at your own risk. No warranty given.
# ======================================================================

set -euo pipefail

# --------------------------- Colors & Styles ---------------------------
if command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1) ; GREEN=$(tput setaf 2) ; YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4); MAGENTA=$(tput setaf 5); CYAN=$(tput setaf 6)
  BOLD=$(tput bold) ; RESET=$(tput sgr0)
else
  RED="" ; GREEN="" ; YELLOW="" ; BLUE="" ; MAGENTA="" ; CYAN=""
  BOLD="" ; RESET=""
fi

log() { echo -e "${CYAN}${BOLD}[INFO]${RESET} $*"; }
ok()  { echo -e "${GREEN}${BOLD}[OK]${RESET}   $*"; }
warn(){ echo -e "${YELLOW}${BOLD}[WARN]${RESET} $*"; }
err() { echo -e "${RED}${BOLD}[ERR]${RESET}  $*" >&2; }

# --------------------------- Config (edit if needed) -------------------
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)
CLUSTER="hello-world-k9el"
NAMESPACE="gmp-d252"
AR_REPO="demo-repo"                            # existing per lab
AR_HOST="${REGION}-docker.pkg.dev"             # us-east1-docker.pkg.dev
IMG_SAMPLE_FIX="us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0"
IMG_V2="${AR_HOST}/${PROJECT_ID}/${AR_REPO}/hello-app:v2"
SVC_NAME="helloweb-service-5lt3"
METRIC_NAME="pod-image-errors"
POLICY_DISPLAY="Pod Error Alert"

# --------------------------- Preflight checks --------------------------
preflight() {
  echo -e "${MAGENTA}${BOLD}==> ePlus.DEV - GSP510 ${RESET}"
  [[ -n "${PROJECT_ID}" ]] || { err "PROJECT_ID not set"; exit 1; }
  log "Project: ${PROJECT_ID}"
  log "Zone:    ${ZONE} | Region: ${REGION}"
  gcloud config set project "${PROJECT_ID}" -q >/dev/null
  gcloud services enable container.googleapis.com logging.googleapis.com monitoring.googleapis.com artifactregistry.googleapis.com -q
  ok "APIs enabled (or already enabled)."

  if ! kubectl version --client >/dev/null 2>&1; then
    err "kubectl not found. Use Cloud Shell or install kubectl."
    exit 1
  fi
}

# --------------------------- Task 1: Create GKE ------------------------
task1_create_gke() {
  log "Fetching available GKE versions in ${ZONE} ..."
  local minver="1.27.8"
  local ver
  ver="$(gcloud container get-server-config --zone "${ZONE}" \
        --format="value(validMasterVersions[0])")"
  if [[ -z "${ver}" ]]; then
    err "Cannot detect GKE version"; exit 1
  fi
  # Ensure >= 1.27.8. If lower, find a >= candidate; else fallback to detected.
  local pick="${ver}"
  mapfile -t vers < <(gcloud container get-server-config --zone "${ZONE}" \
      --format="csv[no-heading](validMasterVersions)" | tr ',' '\n')
  for v in "${vers[@]}"; do
    if printf '%s\n%s\n' "$minver" "$v" | sort -V | head -n1 | grep -qx "$minver"; then
      pick="$v"; break
    fi
  done
  warn "Using cluster version: ${pick}"

  if gcloud container clusters describe "${CLUSTER}" --zone "${ZONE}" >/dev/null 2>&1; then
    ok "Cluster ${CLUSTER} already exists."
  else
    log "Creating cluster ${CLUSTER} ..."
    gcloud container clusters create "${CLUSTER}" \
      --zone "${ZONE}" \
      --release-channel regular \
      --cluster-version "${pick}" \
      --enable-autoscaling --min-nodes 2 --max-nodes 6 \
      --num-nodes 3 -q
    ok "Cluster created."
  fi

  gcloud container clusters get-credentials "${CLUSTER}" --zone "${ZONE}" -q
  ok "kubectl context configured."
}

# -------------------- Task 2: Managed Prometheus & Mon -----------------
task2_prometheus() {
  log "Enabling Managed Prometheus ..."
  gcloud container clusters update "${CLUSTER}" --zone "${ZONE}" --enable-managed-prometheus -q || true
  ok "Managed Prometheus enabled (or already)."

  if kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
    ok "Namespace ${NAMESPACE} exists."
  else
    kubectl create namespace "${NAMESPACE}"
    ok "Namespace ${NAMESPACE} created."
  fi

  log "Fetching sample prometheus app manifest ..."
  gsutil cp gs://spls/gsp510/prometheus-app.yaml . >/dev/null
  # Replace <todo> blocks (image, name, port name)
  sed -i \
    -e 's#\(image:\s*\).*#\1nilebox/prometheus-example-app:latest#' \
    -e 's#\(name:\s*\)<todo>.*#\1prometheus-test#' \
    -e 's#\(name:\s*\)http#\1metrics#' \
    prometheus-app.yaml

  kubectl apply -n "${NAMESPACE}" -f prometheus-app.yaml
  ok "prometheus-app applied."

  log "Fetching pod-monitoring manifest ..."
  gsutil cp gs://spls/gsp510/pod-monitoring.yaml . >/dev/null
  # Replace <todo> in pod-monitoring
  sed -i \
    -e 's#^\(\s*name:\s*\).*#\1prometheus-test#' \
    -e 's#^\(\s*app\.kubernetes\.io/name:\s*\).*#\1prometheus-test#' \
    -e 's#^\(\s*app:\s*\).*#\1prometheus-test#' \
    -e 's#^\(\s*interval:\s*\).*#\130s#' \
    pod-monitoring.yaml

  kubectl apply -n "${NAMESPACE}" -f pod-monitoring.yaml
  ok "pod-monitoring applied."
}

# -------- Task 3: Deploy app with invalid image (per lab flow) ---------
task3_deploy_invalid() {
  log "Copying hello-app manifests ..."
  gsutil -m cp -r gs://spls/gsp510/hello-app/ . >/dev/null 2>&1 || true

  log "Applying helloweb (expected to have invalid image initially) ..."
  kubectl apply -n "${NAMESPACE}" -f hello-app/manifests/helloweb-deployment.yaml
  ok "helloweb applied (will show InvalidImageName until fixed)."
}

# -------- Task 4: Logs-based metric & alerting policy via gcloud -------
task4_logging_alerting() {
  log "Creating logs-based metric '${METRIC_NAME}' if missing ..."
  # Metric filter: K8s container, severity ERROR, InvalidImageName or invalid image tag parse
  local FILTER='resource.type="k8s_container" severity=ERROR ("InvalidImageName" OR "couldn'\''t parse image reference" OR "Failed to apply default image tag")'
  if gcloud logging metrics describe "${METRIC_NAME}" >/dev/null 2>&1; then
    ok "Metric ${METRIC_NAME} already exists."
  else
    gcloud logging metrics create "${METRIC_NAME}" \
      --description="Count pod image errors" \
      --log-filter="${FILTER}"
    ok "Metric ${METRIC_NAME} created."
  fi

  log "Creating alerting policy '${POLICY_DISPLAY}' if missing ..."
  # Check by display name
  if gcloud monitoring policies list --format="value(displayName)" | grep -Fxq "${POLICY_DISPLAY}"; then
    ok "Alert policy already exists."
  else
    cat > /tmp/policy.json <<'JSON'
{
  "displayName": "Pod Error Alert",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "pod-image-errors > 0 (Sum, rolling 10m)",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/pod-image-errors\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "600s",
        "aggregations": [
          { "alignmentPeriod": "600s", "perSeriesAligner": "ALIGN_DELTA" },
          { "alignmentPeriod": "600s", "perSeriesAligner": "ALIGN_SUM", "crossSeriesReducer": "REDUCE_SUM", "groupByFields": [] }
        ],
        "trigger": { "count": 1 }
      }
    }
  ],
  "notificationChannels": []
}
JSON
    gcloud monitoring policies create --policy-from-file=/tmp/policy.json >/dev/null
    ok "Alert policy created."
  fi
}

# ----------------- Task 5: Fix image & redeploy cleanly ----------------
task5_fix_and_redeploy() {
  log "Fixing image in manifest to sample good image ..."
  sed -i "s#image:.*#image: ${IMG_SAMPLE_FIX}#g" hello-app/manifests/helloweb-deployment.yaml

  log "Deleting old helloweb deployment (if present) ..."
  kubectl delete deployment helloweb -n "${NAMESPACE}" --ignore-not-found=true
  sleep 2

  log "Re-applying corrected helloweb deployment ..."
  kubectl apply -n "${NAMESPACE}" -f hello-app/manifests/helloweb-deployment.yaml
  ok "helloweb re-deployed with valid image."

  log "Waiting for pods to be Ready ..."
  kubectl rollout status deployment/helloweb -n "${NAMESPACE}" --timeout=180s
  ok "helloweb is Ready."
}

# ------------- Task 6: Build v2 image, push & expose service ----------
task6_build_push_expose() {
  log "Updating hello-app/main.go to Version: 2.0.0 ..."
  # Robust replace: change the line that prints Version:
  if grep -R "Version:" -n hello-app/main.go >/dev/null 2>&1; then
    sed -i 's/Version: .*/Version: 2.0.0\\n" +/g' hello-app/main.go || true
  fi
  # Safer direct replacement of the common format:
  sed -i 's/Version: 1\.0\.0/Version: 2\.0\.0/g' hello-app/main.go || true
  # Or explicit Go printf line variant:
  sed -i 's#fmt\.Fprintf(w, "Hello, world!\\nVersion: .*#fmt.Fprintf(w, "Hello, world!\\nVersion: 2.0.0\\nHostname: %s\\n", host)#' hello-app/main.go || true

  log "Configuring Docker auth for Artifact Registry ${AR_HOST} ..."
  gcloud auth configure-docker "${AR_HOST}" -q

  log "Building Docker image ${IMG_V2} ..."
  (cd hello-app && docker build -t "${IMG_V2}" .)

  log "Pushing image ${IMG_V2} ..."
  docker push "${IMG_V2}"
  ok "Image pushed."

  log "Updating helloweb deployment image to v2 ..."
  kubectl set image deployment/helloweb helloweb="${IMG_V2}" -n "${NAMESPACE}"
  kubectl rollout status deployment/helloweb -n "${NAMESPACE}" --timeout=180s
  ok "helloweb updated to v2."

  log "Exposing service ${SVC_NAME} (LoadBalancer: port 8080 -> targetPort 8080) ..."
  if kubectl get svc "${SVC_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    ok "Service ${SVC_NAME} already exists."
  else
    kubectl expose deployment helloweb \
      --name="${SVC_NAME}" \
      --type=LoadBalancer \
      --port=8080 --target-port=8080 \
      -n "${NAMESPACE}"
    ok "Service exposed."
  fi

  log "Waiting for External IP ..."
  for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc "${SVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -n "${EXTERNAL_IP}" ]]; then break; fi
    sleep 5
  done
  if [[ -n "${EXTERNAL_IP}" ]]; then
    ok "Service External IP: ${BOLD}${EXTERNAL_IP}${RESET}"
    echo -e "${BLUE}${BOLD}Open:${RESET} http://${EXTERNAL_IP}:8080"
  else
    warn "External IP not ready yet; check again with:
  kubectl get svc ${SVC_NAME} -n ${NAMESPACE} -w"
  fi
}

# ------------------------------ Run All --------------------------------
main() {
  preflight
  task1_create_gke
  task2_prometheus
  task3_deploy_invalid
  task4_logging_alerting
  task5_fix_and_redeploy
  task6_build_push_expose
  ok "All tasks completed. Check My Progress in the lab UI."
}

main "$@"