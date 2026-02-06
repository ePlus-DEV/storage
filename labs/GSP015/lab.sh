#!/bin/bash
set -euo pipefail

# =========================
# Qwiklabs - GKE Hello App Lab Script
# Author: ePlus.DEV
# =========================

# ---- Colors ----
BLACK=$(tput setaf 0 || true)
RED=$(tput setaf 1 || true)
GREEN=$(tput setaf 2 || true)
YELLOW=$(tput setaf 3 || true)
BLUE=$(tput setaf 4 || true)
MAGENTA=$(tput setaf 5 || true)
CYAN=$(tput setaf 6 || true)
WHITE=$(tput setaf 7 || true)
BOLD=$(tput bold || true)
RESET=$(tput sgr0 || true)

BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

log()  { echo "${CYAN}${BOLD}➜${RESET} $*"; }
ok()   { echo "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo "${YELLOW}${BOLD}!${RESET} $*"; }
err()  { echo "${RED}${BOLD}✗${RESET} $*" >&2; }

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV${RESET}"

# ---- Config ----
ZONE="${ZONE:-us-central1-c}"
CLUSTER_NAME="${CLUSTER_NAME:-hello-world}"
IMAGE_NAME="${IMAGE_NAME:-hello-app}"
IMAGE_TAG="${IMAGE_TAG:-1.0}"
DEPLOY_NAME="${DEPLOY_NAME:-hello-app}"
SVC_NAME="${SVC_NAME:-hello-app}"
REPO_DIR="${REPO_DIR:-kubernetes-engine-samples}"
APP_DIR="${APP_DIR:-kubernetes-engine-samples/quickstarts/hello-app}"

# ---- Helpers ----
need() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }
}

get_project_id() {
  if [[ -n "${DEVSHELL_PROJECT_ID:-}" ]]; then
    echo "$DEVSHELL_PROJECT_ID"
  else
    gcloud config get-value project 2>/dev/null || true
  fi
}

# ---- Preflight ----
need gcloud
need kubectl
need git
need docker

log "Checking Project ID..."
PROJECT_ID="$(get_project_id)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  err "Project ID not found. In Cloud Shell, it should be set. Try: gcloud config set project <PROJECT_ID>"
  exit 1
fi
ok "Project: ${BOLD}${PROJECT_ID}${RESET}"

log "Set compute zone: ${BOLD}${ZONE}${RESET}"
gcloud config set compute/zone "${ZONE}" >/dev/null
ok "Compute zone set."

# ---- Create Cluster ----
log "Creating GKE cluster: ${BOLD}${CLUSTER_NAME}${RESET} (skip if exists)"
if gcloud container clusters describe "${CLUSTER_NAME}" --zone "${ZONE}" >/dev/null 2>&1; then
  warn "Cluster already exists: ${CLUSTER_NAME} (skipping create)"
else
  gcloud container clusters create "${CLUSTER_NAME}"
  ok "Cluster created."
fi

log "Fetching cluster credentials"
gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone "${ZONE}" >/dev/null
ok "kubectl is now configured."

# ---- Get sample code ----
log "Cloning sample repo (skip if exists): ${BOLD}${REPO_DIR}${RESET}"
if [[ -d "${REPO_DIR}" ]]; then
  warn "Repo already exists: ${REPO_DIR} (skipping clone)"
else
  git clone https://github.com/GoogleCloudPlatform/kubernetes-engine-samples
  ok "Repo cloned."
fi

log "Changing directory: ${BOLD}${APP_DIR}${RESET}"
cd "${APP_DIR}"

# ---- Build image ----
IMAGE="gcr.io/${PROJECT_ID}/${IMAGE_NAME}:${IMAGE_TAG}"

log "Building Docker image: ${BOLD}${IMAGE}${RESET}"
docker build -t "${IMAGE}" .
ok "Docker build done."

# ---- Push image ----
log "Pushing image to Google Cloud: ${BOLD}${IMAGE}${RESET}"
# This matches lab command style
gcloud docker -- push "${IMAGE}"
ok "Image pushed."

# ---- Deploy ----
log "Creating deployment: ${BOLD}${DEPLOY_NAME}${RESET} (image: ${IMAGE})"
if kubectl get deployment "${DEPLOY_NAME}" >/dev/null 2>&1; then
  warn "Deployment already exists: ${DEPLOY_NAME} (updating image)"
  kubectl set image deployment/"${DEPLOY_NAME}" "${DEPLOY_NAME}"="${IMAGE}" >/dev/null
else
  kubectl create deployment "${DEPLOY_NAME}" --image="${IMAGE}"
fi
ok "Deployment ready."

log "Waiting for rollout..."
kubectl rollout status deployment/"${DEPLOY_NAME}" --timeout=180s
ok "Rollout completed."

# ---- Expose service ----
log "Exposing deployment as LoadBalancer service: ${BOLD}${SVC_NAME}${RESET}"
if kubectl get svc "${SVC_NAME}" >/dev/null 2>&1; then
  warn "Service already exists: ${SVC_NAME} (skipping expose)"
else
  kubectl expose deployment "${DEPLOY_NAME}" --name="${SVC_NAME}" --type=LoadBalancer --port=80 --target-port=8080
  ok "Service created."
fi

# ---- Show status ----
echo
log "Current resources:"
kubectl get deployments
kubectl get pods
kubectl get svc "${SVC_NAME}"

echo
log "Waiting for EXTERNAL-IP (may take 1-3 minutes)..."
for i in {1..40}; do
  EXTERNAL_IP="$(kubectl get svc "${SVC_NAME}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "${EXTERNAL_IP}" ]]; then
    ok "EXTERNAL-IP: ${BOLD}${EXTERNAL_IP}${RESET}"
    echo "${MAGENTA}${BOLD}Open:${RESET} http://${EXTERNAL_IP}"
    exit 0
  fi
  echo -n "."
  sleep 5
done

warn "EXTERNAL-IP still pending. Run: kubectl get svc ${SVC_NAME} (wait a bit more)"
exit 0

echo "${BG_RED}${BOLD}Congratulations For Completing The Lab !!! - ePlus.DEV${RESET}"