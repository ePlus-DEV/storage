#!/usr/bin/env bash
# ==============================================================================
#  GKE Lab Automation Script
#  © 2025 ePlus.DEV — MIT License
# ------------------------------------------------------------------------------
#  This script executes the exact commands from the lab:
#    1. Set default region & zone
#    2. Get cluster credentials
#    3. Deploy hello-app
#    4. Expose service & display external IP
# ==============================================================================

# Colors
GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║         GKE Lab Script — © ePlus.DEV 2025          ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}Setting default compute region...${RESET}"
gcloud config set compute/region us-west1
echo -e "${GREEN}✔ Done${RESET}"

echo -e "${YELLOW}Setting default compute zone...${RESET}"
gcloud config set compute/zone us-west1-c
echo -e "${GREEN}✔ Done${RESET}"

echo -e "${YELLOW}Getting GKE cluster credentials...${RESET}"
gcloud container clusters get-credentials lab-cluster
echo -e "${GREEN}✔ Credentials configured${RESET}"

echo -e "${YELLOW}Creating Deployment: hello-server...${RESET}"
kubectl create deployment hello-server --image=gcr.io/google-samples/hello-app:1.0
echo -e "${GREEN}✔ Deployment created${RESET}"

echo -e "${YELLOW}Exposing Deployment as LoadBalancer on port 8080...${RESET}"
kubectl expose deployment hello-server --type=LoadBalancer --port 8080
echo -e "${GREEN}✔ Service exposed${RESET}"

echo -e "${YELLOW}Checking service status...${RESET}"
kubectl get service hello-server
echo -e "${CYAN}Note: External IP may take 1–2 minutes to appear.${RESET}"

echo -e "${GREEN}Script completed!${RESET}"
echo -e "${CYAN}If EXTERNAL-IP is pending, run: kubectl get service hello-server${RESET}"