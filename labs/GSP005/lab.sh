#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  full_gke_node_lab_auto.sh
#  One-shot, end-to-end automation for "Deploy Node.js to GKE" lab
#  - Builds images (v1/v2), pushes to Artifact Registry
#  - Creates GKE cluster, deploys, exposes LoadBalancer, scales, rolling update
#  - Non-interactive (quiet where possible)
#  - Color output for terminal
#  © 2025 David. All rights reserved.
# -----------------------------------------------------------------------------
#
# USAGE:
#   ./full_gke_node_lab_auto.sh [PROJECT_ID]
#
# NOTES:
#   - Run this in Cloud Shell (recommended) to avoid auth/quota issues.
#   - If PROJECT_ID is not provided, the script will use `gcloud config get-value project`.
#   - The script is intended to run end-to-end without prompts.
# -----------------------------------------------------------------------------

set -euo pipefail

# ---------- Colors ----------
if test -t 1; then
  BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"
  RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"; CYAN="\033[36m"
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""
fi

info(){ echo -e "${BOLD}${CYAN}[INFO]${RESET} $*"; }
ok(){ echo -e "${GREEN}[OK]${RESET} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail(){ echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

# ---------- Config (edit if needed) ----------
REGION="${REGION:-us-east4}"
ZONE="${ZONE:-us-east4-b}"
REPO="${REPO:-my-docker-repo}"
APP="${APP:-hello-node}"
CLUSTER_NAME="${CLUSTER_NAME:-hello-world}"

# Project detection
PROJECT_ID="${1:-${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  fail "PROJECT_ID not set. Usage: ./full_gke_node_lab_auto.sh <PROJECT_ID>"
fi

REG_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${APP}"

info "Project: ${PROJECT_ID}"
info "Region:  ${REGION}  Zone: ${ZONE}"
info "Repo:    ${REPO}"
info "App:     ${APP}"
info "Cluster: ${CLUSTER_NAME}"
echo

# ---------- Safety / cleanup trap ----------
cleanup_on_exit() {
  status=$?
  if [[ $status -ne 0 ]]; then
    warn "Script failed with status $status. Leaving resources for debugging."
  fi
  # do not auto-delete resources on failure; provide cleanup script separately
}
trap cleanup_on_exit EXIT

# ---------- Enable APIs ----------
info "Enabling required APIs..."
gcloud services enable container.googleapis.com artifactregistry.googleapis.com --project "${PROJECT_ID}" >/dev/null
ok "APIs enabled."

# ---------- Create Node.js app (v1) ----------
info "Creating server.js (v1)..."
cat > server.js <<'JS'
var http = require('http');
var handleRequest = function(request, response) {
  response.writeHead(200);
  response.end("Hello World!");
}
var www = http.createServer(handleRequest);
www.listen(8080);
JS
ok "server.js created."

# ---------- Dockerfile ----------
info "Creating Dockerfile..."
cat > Dockerfile <<'DOCKER'
FROM node:6.9.2
EXPOSE 8080
COPY server.js .
CMD ["node", "server.js"]
DOCKER
ok "Dockerfile created."

# ---------- Build Docker image v1 ----------
info "Building Docker image (v1)..."
docker build -t "${APP}:v1" .
ok "Built ${APP}:v1"

# ---------- Create Artifact Registry repo if needed ----------
info "Ensuring Artifact Registry repository exists..."
if ! gcloud artifacts repositories describe "${REPO}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud artifacts repositories create "${REPO}" \
    --repository-format=docker \
    --location="${REGION}" \
    --project="${PROJECT_ID}" >/dev/null
  ok "Repository ${REPO} created in ${REGION}."
else
  ok "Repository ${REPO} already exists."
fi

# ---------- Docker auth to Artifact Registry ----------
info "Configuring Docker auth for Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" -q >/dev/null
ok "Docker authenticated to Artifact Registry."

# ---------- Tag & push v1 ----------
info "Tagging and pushing ${APP}:v1 → ${REG_PATH}:v1 ..."
docker tag "${APP}:v1" "${REG_PATH}:v1"
docker push "${REG_PATH}:v1" >/dev/null
ok "Pushed ${REG_PATH}:v1"

# ---------- Create GKE cluster (if not exists) ----------
info "Creating or reusing GKE cluster '${CLUSTER_NAME}'..."
gcloud config set project "${PROJECT_ID}" >/dev/null
if ! gcloud container clusters describe "${CLUSTER_NAME}" --zone "${ZONE}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud container clusters create "${CLUSTER_NAME}" \
    --num-nodes 2 \
    --machine-type e2-medium \
    --zone "${ZONE}" \
    --project "${PROJECT_ID}" >/dev/null
  ok "Cluster ${CLUSTER_NAME} created."
else
  ok "Cluster ${CLUSTER_NAME} already exists."
fi

# ---------- Get credentials ----------
info "Fetching kube credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone "${ZONE}" --project "${PROJECT_ID}" >/dev/null
ok "kubectl configured for cluster."

# ---------- Create or update deployment (v1) ----------
info "Deploying ${APP} (v1) to cluster..."
if kubectl get deployment "${APP}" >/dev/null 2>&1; then
  kubectl set image deployment/"${APP}" "${APP}"="${REG_PATH}:v1" --record >/dev/null
  ok "Updated existing deployment to image v1."
else
  kubectl create deployment "${APP}" --image="${REG_PATH}:v1" >/dev/null
  ok "Deployment created."
fi
kubectl rollout status deployment/"${APP}" >/dev/null
ok "Deployment is ready."

# ---------- Expose via LoadBalancer ----------
info "Exposing deployment via LoadBalancer (:8080)..."
if kubectl get svc "${APP}" >/dev/null 2>&1; then
  warn "Service ${APP} already exists."
else
  kubectl expose deployment "${APP}" --type=LoadBalancer --port=8080 >/dev/null
  ok "Service created."
fi

# ---------- Wait for External IP ----------
info "Waiting for External IP (this can take a minute)..."
EXTERNAL_IP=""
for i in {1..60}; do
  EXTERNAL_IP="$(kubectl get svc "${APP}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "${EXTERNAL_IP}" ]]; then
    break
  fi
  sleep 5
done
if [[ -z "${EXTERNAL_IP}" ]]; then
  warn "External IP not available yet. You can check with: kubectl get svc ${APP}"
else
  ok "Service External IP: ${EXTERNAL_IP}"
  info "Test endpoint: curl http://${EXTERNAL_IP}:8080"
  set +e
  curl --max-time 5 "http://${EXTERNAL_IP}:8080" || true
  set -e
fi

# ---------- Scale to 4 replicas ----------
info "Scaling deployment to 4 replicas..."
kubectl scale deployment "${APP}" --replicas=4 >/dev/null
kubectl get deployment "${APP}" >/dev/null
ok "Scaled to 4 replicas."

# ---------- Prepare v2 (Hello Kubernetes World!) ----------
info "Preparing v2 (Hello Kubernetes World!)..."
cat > server.js <<'JS'
var http = require('http');
var handleRequest = function(request, response) {
  response.writeHead(200);
  response.end("Hello Kubernetes World!");
}
var www = http.createServer(handleRequest);
www.listen(8080);
JS
ok "server.js updated to v2."

info "Building Docker image (v2)..."
docker build -t "${APP}:v2" .
ok "Built ${APP}:v2"

info "Tagging & pushing v2 → ${REG_PATH}:v2 ..."
docker tag "${APP}:v2" "${REG_PATH}:v2"
docker push "${REG_PATH}:v2" >/dev/null
ok "Pushed ${REG_PATH}:v2"

# ---------- Rolling update to v2 ----------
info "Rolling update to v2..."
kubectl set image deployment/"${APP}" "${APP}"="${REG_PATH}:v2" --record >/dev/null
kubectl rollout status deployment/"${APP}" >/dev/null
ok "Rolling update finished."

# ---------- Final verification ----------
if [[ -n "${EXTERNAL_IP}" ]]; then
  info "Final test (v2) at http://${EXTERNAL_IP}:8080"
  set +e
  OUT="$(curl -s --max-time 5 "http://${EXTERNAL_IP}:8080" || true)"
  set -e
  echo -e "${BOLD}${CYAN}Response:${RESET} ${OUT}"
fi

echo
echo -e "${BOLD}${GREEN}========== COMPLETE ==========${RESET}"
echo -e "Project   : ${PROJECT_ID}"
echo -e "Cluster   : ${CLUSTER_NAME} (${ZONE})"
echo -e "Images    : ${REG_PATH}:v1 , ${REG_PATH}:v2"
echo -e "Service   : ${APP} (LoadBalancer :8080)"
[[ -n "${EXTERNAL_IP}" ]] && echo -e "ExternalIP: ${EXTERNAL_IP}"
echo -e "${BOLD}${GREEN}==============================${RESET}"
echo
echo "© 2025 David. All rights reserved."