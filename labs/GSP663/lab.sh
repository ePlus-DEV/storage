#!/bin/bash

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Welcome message
echo -e "${YELLOW}=============================================${NC}"
echo -e "${GREEN} Welcome to ePlus.DEV Tutorials! ${NC}"
echo -e "${YELLOW}=============================================${NC}"
echo -e "${CYAN}Don't forget to subscribe to our YouTube channel:${NC}"
echo -e "${BLUE}https://eplus.dev/videos${NC}"
echo -e "${YELLOW}=============================================${NC}"
echo -e "\n"

# Step 1: List authenticated accounts
echo -e "${GREEN}[Step 1] Checking authenticated accounts...${NC}"
gcloud auth list
echo -e "\n"

# Step 2: Set compute zone
echo -e "${GREEN}[Step 2] Setting compute zone...${NC}"
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
gcloud config set compute/zone $ZONE
echo -e "${CYAN}Zone set to: $ZONE${NC}"
echo -e "\n"

# Step 3: Enable container API
echo -e "${GREEN}[Step 3] Enabling container API...${NC}"
gcloud services enable container.googleapis.com
echo -e "\n"

# Step 4: Create GKE cluster
echo -e "${GREEN}[Step 4] Creating GKE cluster...${NC}"
gcloud container clusters create fancy-cluster --num-nodes 3
echo -e "\n"

# Step 5: List instances
echo -e "${GREEN}[Step 5] Listing compute instances...${NC}"
gcloud compute instances list
echo -e "\n"

# Step 6: Clone repository
echo -e "${GREEN}[Step 6] Cloning monolith-to-microservices repository...${NC}"
cd ~
git clone https://github.com/googlecodelabs/monolith-to-microservices.git
echo -e "\n"

# Step 7: Run setup script
echo -e "${GREEN}[Step 7] Running setup script...${NC}"
cd ~/monolith-to-microservices
./setup.sh
echo -e "\n"

# Step 8: Install Node.js LTS
echo -e "${GREEN}[Step 8] Installing Node.js LTS...${NC}"
nvm install --lts
echo -e "\n"

# Step 9: Enable Cloud Build API
echo -e "${GREEN}[Step 9] Enabling Cloud Build API...${NC}"
gcloud services enable cloudbuild.googleapis.com
echo -e "\n"

# Step 10: Build and deploy monolith
echo -e "${GREEN}[Step 10] Building and deploying monolith...${NC}"
cd ~/monolith-to-microservices/monolith
gcloud builds submit --tag gcr.io/${GOOGLE_CLOUD_PROJECT}/monolith:1.0.0 .
kubectl create deployment monolith --image=gcr.io/${GOOGLE_CLOUD_PROJECT}/monolith:1.0.0
echo -e "\n"

# Step 11: Verify deployment
echo -e "${GREEN}[Step 11] Verifying deployment...${NC}"
kubectl get all
echo -e "\n"

# Step 12: Expose service
echo -e "${GREEN}[Step 12] Exposing monolith service...${NC}"
kubectl expose deployment monolith --type=LoadBalancer --port 80 --target-port 8080
kubectl get service
echo -e "\n"

# Step 13: Scale deployment
echo -e "${GREEN}[Step 13] Scaling deployment...${NC}"
kubectl scale deployment monolith --replicas=3
kubectl get all
echo -e "\n"

# Step 14: Update React app
echo -e "${GREEN}[Step 14] Updating React app...${NC}"
cd ~/monolith-to-microservices/react-app/src/pages/Home
mv index.js.new index.js
cat ~/monolith-to-microservices/react-app/src/pages/Home/index.js
echo -e "\n"

# Step 15: Build React app
echo -e "${GREEN}[Step 15] Building React app...${NC}"
cd ~/monolith-to-microservices/react-app
npm run build:monolith
echo -e "\n"

# Step 16: Update monolith image
echo -e "${GREEN}[Step 16] Updating monolith image...${NC}"
cd ~/monolith-to-microservices/monolith
gcloud builds submit --tag gcr.io/${GOOGLE_CLOUD_PROJECT}/monolith:2.0.0 .
kubectl set image deployment/monolith monolith=gcr.io/${GOOGLE_CLOUD_PROJECT}/monolith:2.0.0
kubectl get pods
echo -e "\n"

# Completion message
echo -e "${YELLOW}=============================================${NC}"
echo -e "${GREEN} Deployment completed successfully! ${NC}"
echo -e "${CYAN}Thanks for following ePlus.DEV Tutorials!${NC}"
echo -e "${BLUE}For more tutorials, visit:${NC}"
echo -e "${BLUE}https://eplus.dev/videos${NC}"
echo -e "${YELLOW}=============================================${NC}"