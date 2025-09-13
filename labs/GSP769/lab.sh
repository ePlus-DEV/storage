#!/bin/bash
# ===============================================================
#  © 2025 ePlus.DEV. All rights reserved.
#  GKE Load Testing with Locust Automation Script
# ===============================================================

# ---- COLOR SCHEME ----
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---- HEADER ----
echo "${CYAN}${BOLD}"
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                                                                   ║"
echo "║      🚀 ePlus.DEV | GKE Load Testing with Locust (Automation)      ║"
echo "║                                                                   ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo "${RESET}"

# ---- VARIABLES ----
PROJECT_ID=$(gcloud config get-value project)
echo "${YELLOW}▶ Current Project:${RESET} ${CYAN}${PROJECT_ID}${RESET}"
echo

# ---- STEP 1. DOWNLOAD LOCUST SOURCE ----
echo "${GREEN}${BOLD}=== Step 1: Download Locust image files ===${RESET}"
gsutil -m cp -r gs://spls/gsp769/locust-image .
if [ $? -eq 0 ]; then
  echo "${GREEN}✔ Locust source downloaded!${RESET}"
else
  echo "${RED}✖ Failed to download Locust files.${RESET}"
  exit 1
fi

# ---- STEP 2. BUILD & PUSH IMAGE ----
echo "${GREEN}${BOLD}=== Step 2: Build & push Locust Docker image ===${RESET}"
gcloud builds submit \
  --tag gcr.io/${PROJECT_ID}/locust-tasks:latest locust-image
if [ $? -eq 0 ]; then
  echo "${GREEN}✔ Locust Docker image built & pushed!${RESET}"
else
  echo "${RED}✖ Docker build failed.${RESET}"
  exit 1
fi

# ---- STEP 3. VERIFY IMAGE ----
echo "${GREEN}${BOLD}=== Step 3: Verify image in Container Registry ===${RESET}"
gcloud container images list | grep locust-tasks && \
echo "${GREEN}✔ Image found in registry.${RESET}" || \
echo "${RED}✖ Image not found. Please check build logs.${RESET}"

# ---- STEP 4. DEPLOY LOCUST MAIN & WORKERS ----
echo "${GREEN}${BOLD}=== Step 4: Deploy Locust main + workers ===${RESET}"
gsutil cp gs://spls/gsp769/locust_deploy_v2.yaml .
sed "s/\${GOOGLE_CLOUD_PROJECT}/$PROJECT_ID/g" locust_deploy_v2.yaml | kubectl apply -f -
if [ $? -eq 0 ]; then
  echo "${GREEN}✔ Locust deployment applied!${RESET}"
else
  echo "${RED}✖ Failed to deploy Locust manifests.${RESET}"
  exit 1
fi

# ---- STEP 5. GET LOCUST UI IP ----
echo "${GREEN}${BOLD}=== Step 5: Retrieve Locust UI External IP ===${RESET}"
echo "${YELLOW}▶ Waiting for external IP...${RESET}"

while true; do
  EXT_IP=$(kubectl get service locust-main -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [[ -n "$EXT_IP" ]]; then
    echo "${CYAN}${BOLD}🌐 Locust UI available at:${RESET} http://${EXT_IP}:8089"
    break
  else
    echo "${YELLOW}...still pending, retrying in 10s...${RESET}"
    sleep 10
  fi
done

# ---- FOOTER ----
echo "${CYAN}${BOLD}"
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║         ✅ Locust Setup Completed | © 2025 ePlus.DEV               ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo "${RESET}"
