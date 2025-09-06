#!/bin/bash
# ==================================================================================
#  Kubernetes Deployment Strategies Lab - ePlus.DEV
#  Author: (David) - ePlus.dev
# ==================================================================================

set -e

# ===== COLORS =====
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)
BOLD=$(tput bold)

# ===== CONFIG =====
PROJECT_ID=$(gcloud config get-value project)
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
CLUSTER_NAME="bootcamp"
APP_NAME="fortune-app"

echo "${MAGENTA}${BOLD}=========================================================${RESET}"
echo "${CYAN}${BOLD} Kubernetes Deployment Strategies Lab - ePlus.DEV ${RESET}"
echo "${MAGENTA}${BOLD}=========================================================${RESET}"
echo "Project: ${YELLOW}$PROJECT_ID${RESET}"
echo "Zone:    ${YELLOW}$ZONE${RESET}"
echo "Cluster: ${YELLOW}$CLUSTER_NAME${RESET}"
echo

# ---------------------------------------------------------
# TASK 1: Setup
# ---------------------------------------------------------
echo "${BLUE}[TASK 1] Setup...${RESET}"
gcloud storage cp -r gs://spls/gsp053/kubernetes . || true
cd kubernetes

gcloud container clusters create $CLUSTER_NAME \
  --machine-type e2-small \
  --num-nodes 3 \
  --scopes "https://www.googleapis.com/auth/projecthosting,storage-rw" \
  --zone $ZONE

gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE

# ---------------------------------------------------------
# TASK 2: Create Deployment & Service
# ---------------------------------------------------------
echo "${GREEN}[TASK 2] Create deployment & service...${RESET}"
kubectl create -f deployments/fortune-app-blue.yaml
kubectl create -f services/fortune-app.yaml

echo "${YELLOW}[WAIT] Waiting for External IP...${RESET}"
while [[ -z $(kubectl get svc $APP_NAME -o=jsonpath="{.status.loadBalancer.ingress[0].ip}") ]]; do
  sleep 5
  echo "${YELLOW}... still waiting ...${RESET}"
done
SERVICE_IP=$(kubectl get svc $APP_NAME -o=jsonpath="{.status.loadBalancer.ingress[0].ip}")
echo "${CYAN}Service IP: $SERVICE_IP${RESET}"
curl http://$SERVICE_IP/version

# ---------------------------------------------------------
# TASK 2b: Scale Deployment
# ---------------------------------------------------------
echo "${GREEN}[TASK 2b] Scaling...${RESET}"
kubectl scale deployment fortune-app-blue --replicas=5
sleep 10
kubectl scale deployment fortune-app-blue --replicas=3
sleep 10

# ---------------------------------------------------------
# TASK 3: Rolling Update
# ---------------------------------------------------------
echo "${BLUE}[TASK 3] Rolling update to v2.0.0...${RESET}"
kubectl set image deployment/fortune-app-blue fortune-app=us-central1-docker.pkg.dev/qwiklabs-resources/spl-lab-apps/fortune-service:2.0.0
kubectl set env deployment/fortune-app-blue APP_VERSION=2.0.0
kubectl rollout status deployment/fortune-app-blue

echo "${RED}[TASK 3] Rollback to v1.0.0...${RESET}"
kubectl rollout undo deployment/fortune-app-blue
kubectl rollout status deployment/fortune-app-blue
curl http://$SERVICE_IP/version

# ---------------------------------------------------------
# TASK 4: Canary Deployment
# ---------------------------------------------------------
echo "${GREEN}[TASK 4] Canary deployment...${RESET}"
kubectl create -f deployments/fortune-app-canary.yaml
kubectl get deployments

echo "${YELLOW}[TASK 4] Testing canary traffic...${RESET}"
for i in {1..10}; do
  curl -s http://$SERVICE_IP/version
  echo
done

# ---------------------------------------------------------
# TASK 5: Blue-Green Deployment
# ---------------------------------------------------------
echo "${BLUE}[TASK 5] Blue-Green deployment...${RESET}"

# Service trỏ về blue
kubectl apply -f services/fortune-app-blue-service.yaml
curl http://$SERVICE_IP/version

# Tạo green deployment
kubectl create -f deployments/fortune-app-green.yaml
sleep 10
curl http://$SERVICE_IP/version

# Switch sang green
kubectl apply -f services/fortune-app-green-service.yaml
sleep 10
curl http://$SERVICE_IP/version

# Rollback về blue
kubectl apply -f services/fortune-app-blue-service.yaml
sleep 10
curl http://$SERVICE_IP/version

# ---------------------------------------------------------
# DONE
# ---------------------------------------------------------
echo "${MAGENTA}${BOLD}=========================================================${RESET}"
echo "${GREEN}${BOLD} ✅ Lab complete!${RESET}"
echo "Service endpoint: ${CYAN}http://$SERVICE_IP/version${RESET}"
echo "${MAGENTA}${BOLD}=========================================================${RESET}"