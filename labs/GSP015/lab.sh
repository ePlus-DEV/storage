#!/bin/bash
set -e

# =========================
#  QWIKLABS GKE HELLO APP
#  Author : ePlus.DEV
#  License: Internal Lab Script
# =========================

# ---- COLORS ----
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---- CONFIG ----
ZONE="us-central1-c"
CLUSTER="hello-world"
DEPLOY="hello-app"
SERVICE="hello-app"
IMAGE="gcr.io/$DEVSHELL_PROJECT_ID/hello-app:1.0"

# ---- BANNER ----
clear
echo "${MAGENTA}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║        QWIKLABS GKE HELLO APP SCRIPT           ║"
echo "║              © ePlus.DEV                      ║"
echo "╚══════════════════════════════════════════════╝"
echo "${RESET}"

log()  { echo "${CYAN}${BOLD}➜${RESET} $1"; }
ok()   { echo "${GREEN}${BOLD}✔${RESET} $1"; }
warn() { echo "${YELLOW}${BOLD}⚠${RESET} $1"; }

# ---- Config ----
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
CLUSTER_NAME="${CLUSTER_NAME:-hello-world}"
IMAGE_NAME="${IMAGE_NAME:-hello-app}"
IMAGE_TAG="${IMAGE_TAG:-1.0}"
DEPLOY_NAME="${DEPLOY_NAME:-hello-app}"
SVC_NAME="${SVC_NAME:-hello-app}"
REPO_DIR="${REPO_DIR:-kubernetes-engine-samples}"
APP_DIR="${APP_DIR:-kubernetes-engine-samples/quickstarts/hello-app}"

# ---- TASK 2: CREATE CLUSTER ----
log "Create GKE cluster: ${CLUSTER}"
gcloud container clusters create $CLUSTER >/dev/null 2>&1 || warn "Cluster already exists"
ok "Cluster ready"

# ---- GET CREDENTIALS ----
log "Get cluster credentials"
gcloud container clusters get-credentials $CLUSTER >/dev/null
ok "kubectl configured"

# ---- TASK 3: BUILD & PUSH IMAGE ----
log "Clone sample source"
git clone https://github.com/GoogleCloudPlatform/kubernetes-engine-samples >/dev/null 2>&1 || warn "Repo already exists"
cd kubernetes-engine-samples/quickstarts/hello-app

log "Build Docker image"
docker build -t $IMAGE . >/dev/null
ok "Image built"

log "Push image to Google Cloud"
gcloud docker -- push $IMAGE >/dev/null
ok "Image pushed"

# ---- TASK 4: DEPLOY APP ----
log "Create deployment: ${DEPLOY}"
kubectl create deployment $DEPLOY --image=$IMAGE >/dev/null 2>&1 || warn "Deployment already exists"
ok "Deployment ready"

log "Expose service (LoadBalancer)"
kubectl expose deployment $DEPLOY \
  --name=$SERVICE \
  --type=LoadBalancer \
  --port=80 \
  --target-port=8080 >/dev/null 2>&1 || warn "Service already exists"
ok "Service exposed"

# ---- FINAL ----
echo
echo "${GREEN}${BOLD}🎉 ALL TASKS COMPLETED${RESET}"
echo "${WHITE}👉 Ready to click ${BOLD}Check my progress${RESET}${WHITE} in Qwiklabs${RESET}"
echo "${MAGENTA}© ePlus.DEV${RESET}"