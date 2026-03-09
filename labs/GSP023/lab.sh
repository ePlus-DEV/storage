#!/bin/bash

# ==================================================
#  ePlus.DEV - Google Cloud Lab Automation Script
#  Lab: App Engine Flex + Vision API
# ==================================================

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "============================================"
echo "     ePlus.DEV - Cloud Lab Automation"
echo "     App Engine Flex + Vision API"
echo "============================================"
echo -e "${NC}"

# ------------------------------------------------
# Get Project ID
# ------------------------------------------------
echo -e "${BLUE}Getting Project ID...${NC}"

PROJECT_ID=$(gcloud config get-value project)

echo -e "${GREEN}Project: $PROJECT_ID${NC}"

export PROJECT_ID

# ------------------------------------------------
# Download sample code
# ------------------------------------------------
echo -e "${YELLOW}Downloading sample project...${NC}"

gcloud storage cp -r gs://spls/gsp023/flex_and_vision/ .

cd flex_and_vision

# ------------------------------------------------
# Create Service Account
# ------------------------------------------------
echo -e "${BLUE}Creating Service Account...${NC}"

gcloud iam service-accounts create qwiklab \
--display-name="My Qwiklab Service Account" 2>/dev/null

echo -e "${BLUE}Granting permissions...${NC}"

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:qwiklab@$PROJECT_ID.iam.gserviceaccount.com" \
--role="roles/owner" --quiet

echo -e "${BLUE}Creating Service Account Key...${NC}"

gcloud iam service-accounts keys create ~/key.json \
--iam-account qwiklab@$PROJECT_ID.iam.gserviceaccount.com

export GOOGLE_APPLICATION_CREDENTIALS="/home/$USER/key.json"

echo -e "${GREEN}Service Account ready${NC}"

# ------------------------------------------------
# Install dependencies
# ------------------------------------------------
echo -e "${YELLOW}Installing Python dependencies...${NC}"

pip install -r requirements.txt

# ------------------------------------------------
# Create App Engine
# ------------------------------------------------
echo -e "${BLUE}Creating App Engine environment...${NC}"

AE_REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

gcloud app create --region=$AE_REGION --quiet 2>/dev/null

# ------------------------------------------------
# Create Storage Bucket
# ------------------------------------------------
echo -e "${BLUE}Creating Cloud Storage bucket...${NC}"

export CLOUD_STORAGE_BUCKET=$PROJECT_ID

gsutil mb -p $PROJECT_ID -l $AE_REGION gs://$PROJECT_ID 2>/dev/null

echo -e "${GREEN}Bucket created: gs://$PROJECT_ID${NC}"

# ------------------------------------------------
# Create app.yaml automatically
# ------------------------------------------------
echo -e "${YELLOW}Generating app.yaml configuration...${NC}"

cat > app.yaml <<EOF
runtime: python
env: flex
entrypoint: gunicorn -b :\$PORT main:app

runtime_config:
  operating_system: "ubuntu22"
  runtime_version: "3.12"

env_variables:
  CLOUD_STORAGE_BUCKET: $PROJECT_ID

manual_scaling:
  instances: 1
EOF

echo -e "${GREEN}app.yaml configured${NC}"

# ------------------------------------------------
# Deploy App
# ------------------------------------------------
echo -e "${BLUE}Deploying application to App Engine...${NC}"

gcloud config set app/cloud_build_timeout 1000

gcloud app deploy --quiet

# ------------------------------------------------
# Finished
# ------------------------------------------------

echo -e "${CYAN}"
echo "============================================"
echo "        Deployment Completed"
echo "============================================"
echo -e "${NC}"

echo -e "${GREEN}Application URL:${NC}"

echo -e "${YELLOW}https://$PROJECT_ID.appspot.com${NC}"

echo ""
echo -e "${CYAN}© ePlus.DEV Cloud Automation Script${NC}"