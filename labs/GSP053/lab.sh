#!/bin/bash
# ==================================================================================
#  Kubernetes Deployment Strategies Lab - Full Automation Script
#  Copyright (c) 2025 (David) - ePlus.dev
#  Licensed for educational use in Google Cloud Skills Boost Labs
# ==================================================================================
#  Features:
#   - Cluster creation
#   - Deployment creation
#   - Scaling
#   - Rolling update (with rollback)
#   - Canary deployment
#   - Blue-Green deployment
# ==================================================================================

set -e

# ====== COLORS ======
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)
BOLD=$(tput bold)

# ====== CONFIG ======
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-east1-d"
CLUSTER_NAME="bootcamp"
IMAGE_PATH="us-central1-docker.pkg.dev/qwiklabs-resources/spl-lab-apps/fortune-service"
APP_NAME="fortune-app"

echo "${MAGENTA}${BOLD}=========================================================${RESET}"
echo "${CYAN}${BOLD} Kubernetes Deployment Strategies Lab - Automation Script ${RESET}"
echo "${MAGENTA}${BOLD}=========================================================${RESET}"
echo "Project: ${YELLOW}$PROJECT_ID${RESET}"
echo "Zone:    ${YELLOW}$ZONE${RESET}"
echo "Cluster: ${YELLOW}$CLUSTER_NAME${RESET}"
echo

# ====== STEP 1. Setup ======
echo "${BLUE}[STEP 1] Setting compute zone...${RESET}"
gcloud config set compute/zone $ZONE

echo "${BLUE}[STEP 1] Getting sample code...${RESET}"
gcloud storage cp -r gs://spls/gsp053/kubernetes . || true
cd kubernetes

echo "${BLUE}[STEP 1] Creating Kubernetes cluster...${RESET}"
gcloud container clusters create $CLUSTER_NAME \
  --machine-type e2-small \
  --num-nodes 3 \
  --scopes "https://www.googleapis.com/auth/projecthosting,storage-rw"

gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE

# ====== STEP 2. Create Deployment ======
echo "${GREEN}[STEP 2] Creating initial (blue v1.0.0) deployment...${RESET}"
kubectl create -f deployments/fortune-app-blue.yaml

kubectl get deployments
kubectl get pods

echo "${GREEN}[STEP 2] Exposing service...${RESET}"
kubectl create -f services/fortune-app.yaml

# Wait for service external IP
echo "${YELLOW}[WAIT] Waiting for External IP...${RESET}"
while [[ -z $(kubectl get svc $APP_NAME -o=jsonpath="{.status.loadBalancer.ingress[0].ip}") ]]; do
  sleep 5
  echo "${YELLOW}... still waiting ...${RESET}"
done
SERVICE_IP=$(kubectl get svc $APP_NAME -o=jsonpath="{.status.loadBalancer.ingress[0].ip}")
echo "${CYAN}Service IP: $SERVICE_IP${RESET}"

curl http://$SERVICE_IP/version

# ====== STEP 3. Scaling ======
echo "${GREEN}[STEP 3] Scaling deployment to 5 replicas...${RESET}"
kubectl scale deployment fortune-app-blue --replicas=5
sleep 10
kubectl get pods | grep fortune-app-blue | wc -l

echo "${GREEN}[STEP 3] Scaling back to 3 replicas...${RESET}"
kubectl scale deployment fortune-app-blue --replicas=3
sleep 10
kubectl get pods | grep fortune-app-blue | wc -l

# ====== STEP 4. Rolling Update ======
echo "${BLUE}[STEP 4] Rolling update to v2.0.0...${RESET}"
kubectl set image deployment/fortune-app-blue fortune-app=$IMAGE_PATH:2.0.0
kubectl set env deployment/fortune-app-blue APP_VERSION=2.0.0

kubectl rollout status deployment/fortune-app-blue

echo "${RED}[STEP 4] Rolling back to v1.0.0...${RESET}"
kubectl rollout undo deployment/fortune-app-blue
kubectl rollout status deployment/fortune-app-blue
curl http://$SERVICE_IP/version

# ====== STEP 5. Canary Deployment ======
echo "${GREEN}[STEP 5] Creating canary deployment (v2.0.0)...${RESET}"
kubectl create -f deployments/fortune-app-canary.yaml
kubectl get deployments

echo "${YELLOW}[STEP 5] Testing canary traffic (10 requests)...${RESET}"
for i in {1..10}; do
  curl -s http://$SERVICE_IP/version
  echo
done

# ====== STEP 6. Blue-Green Deployment ======
echo "${BLUE}[STEP 6] Blue-Green - pointing service to blue (v1.0.0)...${RESET}"
kubectl apply -f services/fortune-app-blue-service.yaml
curl http://$SERVICE_IP/version

echo "${GREEN}[STEP 6] Creating green deployment (v2.0.0)...${RESET}"
kubectl create -f deployments/fortune-app-green.yaml
sleep 10
curl http://$SERVICE_IP/version

echo "${YELLOW}[STEP 6] Switching service to green...${RESET}"
kubectl apply -f services/fortune-app-green-service.yaml
sleep 10
curl http://$SERVICE_IP/version

echo "${RED}[STEP 6] Rolling back to blue...${RESET}"
kubectl apply -f services/fortune-app-blue-service.yaml
sleep 10
curl http://$SERVICE_IP/version

# ====== DONE ======
echo "${MAGENTA}${BOLD}=========================================================${RESET}"
echo "${GREEN}${BOLD} ✅ Lab automation complete!${RESET}"
echo "Service endpoint: ${CYAN}http://$SERVICE_IP/version${RESET}"
echo "${MAGENTA}${BOLD}=========================================================${RESET}"