#!/usr/bin/env bash
set -uo pipefail

# ============================================================
#  GKE COST OPTIMIZATION + REGIONAL TRAFFIC LAB
#  Copyright © ePlus.DEV
# ============================================================

# ---------- Colors ----------
BLACK="$(tput setaf 0 2>/dev/null || true)"
RED="$(tput setaf 1 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
BLUE="$(tput setaf 4 2>/dev/null || true)"
MAGENTA="$(tput setaf 5 2>/dev/null || true)"
CYAN="$(tput setaf 6 2>/dev/null || true)"
WHITE="$(tput setaf 7 2>/dev/null || true)"
BOLD="$(tput bold 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"

banner() {
  clear
  echo "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║        GKE COST OPTIMIZATION + REGIONAL TRAFFIC LAB         ║"
  echo "║                    Copyright © ePlus.DEV                    ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo "${RESET}"
}

log() {
  echo
  echo "${GREEN}${BOLD}▶ $*${RESET}"
}

info() {
  echo "${CYAN}ℹ $*${RESET}"
}

warn() {
  echo "${YELLOW}⚠ $*${RESET}"
}

error() {
  echo "${RED}✖ $*${RESET}"
}

success() {
  echo "${GREEN}✓ $*${RESET}"
}

run_step() {
  local title="$1"
  shift
  log "$title"
  echo "${BLUE}$ $*${RESET}"
  "$@" || true
}

wait_for_seconds() {
  local seconds="$1"
  local message="$2"

  echo -n "${YELLOW}${message}${RESET}"
  for ((i=1; i<=seconds; i++)); do
    echo -n "."
    sleep 1
  done
  echo
}

banner

# ============================================================
# Config
# ============================================================

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
HELLO_CLUSTER="hello-demo-cluster"
REGIONAL_CLUSTER="regional-demo"
OLD_POOL="my-node-pool"
NEW_POOL="larger-pool"
DATASET="us_flow_logs"
SINK_NAME="FlowLogsSample"

if [[ -z "${PROJECT_ID}" ]]; then
  error "Cannot detect PROJECT_ID."
  echo "Please run:"
  echo "gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

success "Project ID: ${PROJECT_ID}"

# ============================================================
# Detect hello-demo-cluster location
# ============================================================

log "Detecting hello-demo-cluster location"

HELLO_LOCATION="$(gcloud container clusters list \
  --filter="name=${HELLO_CLUSTER}" \
  --format="value(location)" \
  --limit=1 2>/dev/null || true)"

if [[ -z "${HELLO_LOCATION}" ]]; then
  error "Cannot find ${HELLO_CLUSTER}."
  warn "Wait until the lab finishes provisioning resources, then run ./lab.sh again."
  exit 1
fi

if [[ "${HELLO_LOCATION}" =~ -[a-z]$ ]]; then
  HELLO_SCOPE_TYPE="zone"
  REGION="${HELLO_LOCATION%-*}"
else
  HELLO_SCOPE_TYPE="region"
  REGION="${HELLO_LOCATION}"
fi

hello_scope_args() {
  if [[ "${HELLO_SCOPE_TYPE}" == "zone" ]]; then
    echo "--zone=${HELLO_LOCATION}"
  else
    echo "--region=${HELLO_LOCATION}"
  fi
}

success "Hello cluster location: ${HELLO_LOCATION}"
success "Detected region: ${REGION}"

BIGQUERY_MAIN_URL="https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
BIGQUERY_DATASET_URL="https://console.cloud.google.com/bigquery?project=${PROJECT_ID}&p=${PROJECT_ID}&d=${DATASET}&page=dataset"
LOGS_ROUTER_URL="https://console.cloud.google.com/logs/router?project=${PROJECT_ID}"
LOGS_EXPLORER_URL="https://console.cloud.google.com/logs/query?project=${PROJECT_ID}"

# ============================================================
# Task 2: Scale up Hello app
# ============================================================

log "Getting credentials for ${HELLO_CLUSTER}"
gcloud container clusters get-credentials "${HELLO_CLUSTER}" $(hello_scope_args) || true

log "Scaling hello-server to 2 replicas"
kubectl scale deployment hello-server --replicas=2 || true
kubectl rollout status deployment/hello-server --timeout=300s || true

log "Resizing old node pool ${OLD_POOL} to 4 nodes"
if gcloud container node-pools describe "${OLD_POOL}" \
  --cluster="${HELLO_CLUSTER}" $(hello_scope_args) >/dev/null 2>&1; then

  gcloud container clusters resize "${HELLO_CLUSTER}" \
    --node-pool="${OLD_POOL}" \
    --num-nodes=4 \
    $(hello_scope_args) \
    --quiet || true

  success "Old node pool resized"
else
  warn "Node pool ${OLD_POOL} not found. Skipping resize."
fi

# ============================================================
# Create optimized node pool
# ============================================================

log "Creating optimized node pool ${NEW_POOL}"

if gcloud container node-pools describe "${NEW_POOL}" \
  --cluster="${HELLO_CLUSTER}" $(hello_scope_args) >/dev/null 2>&1; then
  warn "Node pool ${NEW_POOL} already exists. Skipping creation."
else
  gcloud container node-pools create "${NEW_POOL}" \
    --cluster="${HELLO_CLUSTER}" \
    --machine-type=e2-standard-2 \
    --num-nodes=1 \
    $(hello_scope_args) \
    --quiet || true

  success "Created ${NEW_POOL}"
fi

log "Waiting for ${NEW_POOL} node to be ready"
kubectl wait --for=condition=Ready nodes \
  -l cloud.google.com/gke-nodepool="${NEW_POOL}" \
  --timeout=600s || true

log "Cordoning old node pool ${OLD_POOL}"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="${OLD_POOL}" -o=name 2>/dev/null || true); do
  kubectl cordon "$node" || true
done

log "Draining old node pool ${OLD_POOL}"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="${OLD_POOL}" -o=name 2>/dev/null || true); do
  kubectl drain "$node" \
    --force \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --grace-period=10 || true
done

log "Checking pods after migration"
kubectl get pods -o wide || true

log "Deleting old node pool ${OLD_POOL}"
if gcloud container node-pools describe "${OLD_POOL}" \
  --cluster="${HELLO_CLUSTER}" $(hello_scope_args) >/dev/null 2>&1; then

  gcloud container node-pools delete "${OLD_POOL}" \
    --cluster="${HELLO_CLUSTER}" \
    $(hello_scope_args) \
    --quiet || true

  success "Deleted ${OLD_POOL}"
else
  warn "Node pool ${OLD_POOL} already deleted or not found."
fi

# ============================================================
# Task 3: Regional cluster
# ============================================================

log "Creating regional cluster ${REGIONAL_CLUSTER} in ${REGION}"

if gcloud container clusters describe "${REGIONAL_CLUSTER}" --region="${REGION}" >/dev/null 2>&1; then
  warn "Cluster ${REGIONAL_CLUSTER} already exists. Skipping creation."
else
  gcloud container clusters create "${REGIONAL_CLUSTER}" \
    --region="${REGION}" \
    --num-nodes=1 \
    --quiet || true

  success "Created regional cluster ${REGIONAL_CLUSTER}"
fi

log "Getting credentials for ${REGIONAL_CLUSTER}"
gcloud container clusters get-credentials "${REGIONAL_CLUSTER}" --region="${REGION}" || true

# ============================================================
# Create pods with podAntiAffinity first
# ============================================================

log "Creating pod-1 and pod-2 with podAntiAffinity"

kubectl delete pod pod-1 pod-2 --ignore-not-found >/dev/null 2>&1 || true

cat > pod-1.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: pod-1
  labels:
    security: demo
spec:
  containers:
  - name: container-1
    image: wbitt/network-multitool
YAML

cat > pod-2.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: pod-2
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - demo
        topologyKey: "kubernetes.io/hostname"
  containers:
  - name: container-2
    image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
YAML

kubectl apply -f pod-1.yaml || true
kubectl apply -f pod-2.yaml || true

log "Waiting for pod-1 and pod-2"
kubectl wait --for=condition=Ready pod/pod-1 --timeout=300s || true
kubectl wait --for=condition=Ready pod/pod-2 --timeout=300s || true

log "Pods before moving chatty pod"
kubectl get pod pod-1 pod-2 -o wide || true

# ============================================================
# Enable APIs, VPC Flow Logs, BigQuery dataset, and Logging sink
# ============================================================

log "Enabling required APIs"
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  logging.googleapis.com \
  bigquery.googleapis.com \
  networkmanagement.googleapis.com \
  --quiet || true

log "Enabling VPC Flow Logs for default subnet in ${REGION}"
gcloud compute networks subnets update default \
  --region="${REGION}" \
  --enable-flow-logs \
  --logging-flow-sampling=1 \
  --logging-aggregation-interval=interval-5-sec \
  --logging-metadata=include-all \
  --quiet || true

success "VPC Flow Logs enabled"

log "Creating BigQuery dataset ${DATASET}"
if bq --location=US ls -d "${PROJECT_ID}:${DATASET}" >/dev/null 2>&1; then
  warn "Dataset ${DATASET} already exists."
else
  bq --location=US mk --dataset "${PROJECT_ID}:${DATASET}" || true
  success "Dataset ${DATASET} created"
fi

log "Recreating Logging sink ${SINK_NAME}"

gcloud logging sinks delete "${SINK_NAME}" --quiet >/dev/null 2>&1 || true

gcloud logging sinks create "${SINK_NAME}" \
  "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${DATASET}" \
  --log-filter="resource.type=\"gce_subnetwork\" AND logName=\"projects/${PROJECT_ID}/logs/compute.googleapis.com%2Fvpc_flows\"" \
  --use-partitioned-tables \
  --quiet || true

WRITER_IDENTITY="$(gcloud logging sinks describe "${SINK_NAME}" --format="value(writerIdentity)" 2>/dev/null || true)"

if [[ -n "${WRITER_IDENTITY}" ]]; then
  info "Sink writer identity: ${WRITER_IDENTITY}"

  log "Granting BigQuery Data Editor to the sink writer at project level"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${WRITER_IDENTITY}" \
    --role="roles/bigquery.dataEditor" \
    --quiet >/dev/null 2>&1 || true

  log "Granting BigQuery Data Editor to the sink writer at dataset level"
  bq add-iam-policy-binding \
    --member="${WRITER_IDENTITY}" \
    --role="roles/bigquery.dataEditor" \
    "${PROJECT_ID}:${DATASET}" >/dev/null 2>&1 || true
fi

success "Logging sink configured"

# ============================================================
# Generate cross-zone traffic before affinity change
# ============================================================

log "Generating traffic before affinity change"

POD2_IP="$(kubectl get pod pod-2 -o jsonpath='{.status.podIP}' 2>/dev/null || true)"

if [[ -n "${POD2_IP}" ]]; then
  info "pod-2 IP: ${POD2_IP}"
  info "Generating traffic for about 3 minutes..."
  kubectl exec pod-1 -- sh -c "
    for i in \$(seq 1 180); do
      ping -c 1 ${POD2_IP} >/dev/null 2>&1 || true
      wget -qO- --timeout=1 http://${POD2_IP}:8080 >/dev/null 2>&1 || true
      sleep 1
    done
  " || true
else
  warn "Cannot get pod-2 IP. Skipping traffic generation."
fi

# ============================================================
# Wait for BigQuery table and run query
# ============================================================

log "Waiting for VPC Flow Logs table in BigQuery"

TABLE_ID=""

for i in $(seq 1 36); do
  TABLE_ID="$(bq ls --format=prettyjson "${PROJECT_ID}:${DATASET}" 2>/dev/null \
    | grep -o '"tableId": "[^"]*"' \
    | sed 's/"tableId": "//;s/"//' \
    | grep 'compute_googleapis_com_vpc_flows' \
    | head -n 1 || true)"

  if [[ -n "${TABLE_ID}" ]]; then
    break
  fi

  echo "${YELLOW}Waiting for BigQuery table... ${i}/36${RESET}"
  sleep 10
done

log "BigQuery dataset link"
echo "${GREEN}${BIGQUERY_DATASET_URL}${RESET}"

if [[ -n "${TABLE_ID}" ]]; then
  success "Found BigQuery table: ${TABLE_ID}"

  log "Running the desired query to check frequent traffic between different zones"

  bq query --use_legacy_sql=false "
SELECT
  jsonPayload.src_instance.zone AS src_zone,
  jsonPayload.src_instance.vm_name AS src_vm,
  jsonPayload.dest_instance.zone AS dest_zone,
  jsonPayload.dest_instance.vm_name AS dest_vm,
  COUNT(*) AS traffic_count
FROM \`${PROJECT_ID}.${DATASET}.compute_googleapis_com_vpc_flows*\`
WHERE jsonPayload.src_instance.vm_name LIKE 'gke-${REGIONAL_CLUSTER}%'
  AND jsonPayload.dest_instance.vm_name LIKE 'gke-${REGIONAL_CLUSTER}%'
  AND jsonPayload.src_instance.zone IS NOT NULL
  AND jsonPayload.dest_instance.zone IS NOT NULL
  AND jsonPayload.src_instance.zone != jsonPayload.dest_instance.zone
GROUP BY src_zone, src_vm, dest_zone, dest_vm
ORDER BY traffic_count DESC
LIMIT 20;
" || true

else
  warn "BigQuery table is not visible yet."
  warn "Open the BigQuery dataset link above and click Refresh after 2-5 minutes."
  warn "The table should be created automatically after vpc_flows logs are exported."
fi

# ============================================================
# Move chatty pod: podAntiAffinity -> podAffinity
# ============================================================

log "Moving the chatty pod to the same node using podAffinity"

cat > pod-2.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: pod-2
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - demo
        topologyKey: "kubernetes.io/hostname"
  containers:
  - name: container-2
    image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
YAML

kubectl delete pod pod-2 --ignore-not-found || true
kubectl create -f pod-2.yaml || true

log "Waiting for pod-2 after affinity change"
kubectl wait --for=condition=Ready pod/pod-2 --timeout=300s || true

log "Pods after affinity change"
kubectl get pod pod-1 pod-2 -o wide || true

POD2_IP="$(kubectl get pod pod-2 -o jsonpath='{.status.podIP}' 2>/dev/null || true)"

if [[ -n "${POD2_IP}" ]]; then
  log "Generating traffic again after affinity change"
  info "pod-2 IP: ${POD2_IP}"
  kubectl exec pod-1 -- ping -c 20 "${POD2_IP}" || true
fi

# ============================================================
# Final summary
# ============================================================

echo
echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo "${GREEN}${BOLD}║                         FINISHED                           ║${RESET}"
echo "${GREEN}${BOLD}║                    Copyright © ePlus.DEV                   ║${RESET}"
echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo

echo "${CYAN}${BOLD}Open BigQuery:${RESET}"
echo "${GREEN}${BIGQUERY_MAIN_URL}${RESET}"
echo

echo "${CYAN}${BOLD}Open us_flow_logs dataset:${RESET}"
echo "${GREEN}${BIGQUERY_DATASET_URL}${RESET}"
echo

echo "${CYAN}${BOLD}Open Logs Router:${RESET}"
echo "${GREEN}${LOGS_ROUTER_URL}${RESET}"
echo

echo "${CYAN}${BOLD}Open Logs Explorer:${RESET}"
echo "${GREEN}${LOGS_EXPLORER_URL}${RESET}"
echo

echo "${CYAN}${BOLD}Click Check my progress in the lab:${RESET}"
echo "1) Scale Up Hello App"
echo "2) Create node pool"
echo "3) Check Pod Creation"
echo "4) Simulate Traffic"
echo

echo "${YELLOW}${BOLD}If the BigQuery table does not appear yet:${RESET}"
echo "Open the us_flow_logs dataset link above, then click Refresh after 2-5 minutes."
echo "The table should be created automatically by the Logging sink after new vpc_flows logs are exported."
echo

echo "${YELLOW}${BOLD}Manual BigQuery query:${RESET}"
cat <<SQL
SELECT
  jsonPayload.src_instance.zone AS src_zone,
  jsonPayload.src_instance.vm_name AS src_vm,
  jsonPayload.dest_instance.zone AS dest_zone,
  jsonPayload.dest_instance.vm_name AS dest_vm,
  COUNT(*) AS traffic_count
FROM \`${PROJECT_ID}.${DATASET}.compute_googleapis_com_vpc_flows*\`
WHERE jsonPayload.src_instance.vm_name LIKE 'gke-${REGIONAL_CLUSTER}%'
  AND jsonPayload.dest_instance.vm_name LIKE 'gke-${REGIONAL_CLUSTER}%'
  AND jsonPayload.src_instance.zone IS NOT NULL
  AND jsonPayload.dest_instance.zone IS NOT NULL
  AND jsonPayload.src_instance.zone != jsonPayload.dest_instance.zone
GROUP BY src_zone, src_vm, dest_zone, dest_vm
ORDER BY traffic_count DESC
LIMIT 20;
SQL