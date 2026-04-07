#!/bin/bash
set -euo pipefail

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
TEAL_TEXT=$'\033[38;5;50m'
PURPLE_TEXT=$'\033[0;35m'
GOLD_TEXT=$'\033[0;33m'
LIME_TEXT=$'\033[0;92m'
MAROON_TEXT=$'\033[0;91m'
NAVY_TEXT=$'\033[0;94m'

BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'
BLINK_TEXT=$'\033[5m'
NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'
REVERSE_TEXT=$'\033[7m'

clear

echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}      ePlus.DEV - INITIATING EXECUTION...                          ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
echo

log() {
  echo "${GREEN_TEXT}✓ $1${RESET_FORMAT}"
}

warn() {
  echo "${YELLOW_TEXT}⚠ $1${RESET_FORMAT}"
}

err() {
  echo "${RED_TEXT}✗ $1${RESET_FORMAT}"
}

step() {
  echo
  echo "${YELLOW_TEXT}${BOLD_TEXT}$1${RESET_FORMAT}"
}

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [ -z "${PROJECT_ID}" ]; then
  PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi

if [ -z "${PROJECT_ID}" ]; then
  err "Không lấy được PROJECT_ID"
  exit 1
fi

REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"

if [ -z "${REGION}" ]; then
  REGION="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null || true)"
fi

if [ -z "${ZONE}" ]; then
  ZONE="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)"
fi

[ -z "${REGION}" ] && REGION="us-east4"
[ -z "${ZONE}" ] && ZONE="us-east4-b"

CLUSTER="gke-load-test"
TARGET="${PROJECT_ID}.appspot.com"
BASE_DIR="$HOME/distributed-load-testing-using-kubernetes"

echo "${GREEN_TEXT}✓ Configuration:${RESET_FORMAT}"
echo "  Project: ${PROJECT_ID}"
echo "  Region : ${REGION}"
echo "  Zone   : ${ZONE}"
echo "  Cluster: ${CLUSTER}"
echo

step "Step 1: Setting GCP Environment"
gcloud config set project "${PROJECT_ID}" >/dev/null
gcloud config set compute/region "${REGION}" >/dev/null
gcloud config set compute/zone "${ZONE}" >/dev/null
log "GCP configuration updated"

step "Step 2: Enabling required APIs"
gcloud services enable \
  cloudbuild.googleapis.com \
  containerregistry.googleapis.com \
  appengine.googleapis.com \
  container.googleapis.com >/dev/null
log "Required APIs enabled"

step "Step 3: Downloading Required Resources"
cd "$HOME"
if [ -d "${BASE_DIR}" ]; then
  warn "Directory already exists, skipping download"
else
  gsutil -m cp -r gs://spls/gsp182/distributed-load-testing-using-kubernetes .
fi
log "Resources ready"

step "Step 4: Configuring Sample Web Application"
cd "${BASE_DIR}/sample-webapp"
sed -i 's/python37/python312/g' app.yaml || true
grep -q "python312" app.yaml && log "app.yaml updated to python312" || warn "python312 may already be set"
cd "${BASE_DIR}"

step "Step 5: Building Locust Docker Image"
gcloud builds submit --tag "gcr.io/${PROJECT_ID}/locust-tasks:latest" docker-image/.

if gcloud container images list --repository="gcr.io/${PROJECT_ID}" 2>/dev/null | grep -q "locust-tasks"; then
  log "Docker image built and pushed successfully"
else
  err "Không thấy image locust-tasks trong gcr.io/${PROJECT_ID}"
  exit 1
fi

step "Step 6: Creating App Engine App if needed"
if gcloud app describe >/dev/null 2>&1; then
  warn "App Engine app already exists"
else
  gcloud app create --region="${REGION}"
  log "App Engine app created"
fi

step "Step 7: Deploying Web Application"
gcloud app deploy "${BASE_DIR}/sample-webapp/app.yaml" --quiet
log "Web application deployed"

step "Step 8: Creating GKE Cluster"
if gcloud container clusters describe "${CLUSTER}" --zone "${ZONE}" >/dev/null 2>&1; then
  warn "Cluster ${CLUSTER} already exists"
else
  gcloud container clusters create "${CLUSTER}" \
    --zone "${ZONE}" \
    --num-nodes=5 \
    --machine-type=e2-standard-4
  log "GKE cluster created"
fi

step "Step 9: Getting Cluster Credentials"
gcloud container clusters get-credentials "${CLUSTER}" --zone "${ZONE}"
log "kubectl configured"

step "Step 10: Configuring Load Testing Components"
cd "${BASE_DIR}"
sed -i "s/\[TARGET_HOST\]/${TARGET}/g" kubernetes-config/locust-master-controller.yaml
sed -i "s/\[TARGET_HOST\]/${TARGET}/g" kubernetes-config/locust-worker-controller.yaml
sed -i "s/\[PROJECT_ID\]/${PROJECT_ID}/g" kubernetes-config/locust-master-controller.yaml
sed -i "s/\[PROJECT_ID\]/${PROJECT_ID}/g" kubernetes-config/locust-worker-controller.yaml
log "Kubernetes config files updated"

step "Step 11: Deploying Locust Master"
kubectl apply -f kubernetes-config/locust-master-controller.yaml
kubectl apply -f kubernetes-config/locust-master-service.yaml
log "Locust master deployed"

step "Step 12: Checking Locust Master Service"
kubectl get svc locust-master
log "Locust master service listed"

step "Step 13: Deploying Locust Workers"
kubectl apply -f kubernetes-config/locust-worker-controller.yaml
log "Initial workers deployed"

step "Step 14: Scaling Workers"
kubectl scale deployment/locust-worker --replicas=20
log "Scaled to 20 workers"

echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}              LAB COMPLETED SUCCESSFULLY!              ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}${BOLD_TEXT}Project : ${PROJECT_ID}${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}Region  : ${REGION}${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}Zone    : ${ZONE}${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}Target  : ${TARGET}${RESET_FORMAT}"
echo
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}Don't forget to Like, Share and Subscribe for more Videos${RESET_FORMAT}"