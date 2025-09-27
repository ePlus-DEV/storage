#!/bin/bash
# =====================================================================
# ☁️ Task 1 - Create Vertex AI Workbench Instance (GSP398)
# ---------------------------------------------------------------------
# Author      : ePlus.DEV
# Website     : https://eplus.dev
# Version     : 2025.2
# Description : Automates Task 1 of the GSP398 challenge lab.
#               - Enables required APIs
#               - Creates a Vertex AI Workbench managed notebook instance
#               - Verifies instance creation
# License     : © 2025 ePlus.DEV. All rights reserved.
# =====================================================================

# 🎨 Colors
GREEN="\e[32m"; BLUE="\e[34m"; CYAN="\e[36m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"

echo -e "${CYAN}\n=== ☁️ Task 1: Create Vertex AI Workbench Instance (ePlus.DEV) ===${RESET}\n"

# ------------------ CONFIG ------------------
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export INSTANCE_NAME="cnn-challenge"

echo -e "${BLUE}📦 Using Project:${RESET} ${GREEN}$PROJECT_ID${RESET}"
echo -e "${BLUE}🌍 Region:${RESET} ${GREEN}$REGION${RESET}"
echo -e "${BLUE}📍 Zone:${RESET} ${GREEN}$ZONE${RESET}\n"

# ------------------ STEP 1: ENABLE REQUIRED APIs ------------------
echo -e "${YELLOW}🔑 Enabling required Google Cloud APIs...${RESET}"
gcloud services enable \
  compute.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  notebooks.googleapis.com \
  aiplatform.googleapis.com \
  artifactregistry.googleapis.com \
  container.googleapis.com

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ All required APIs are enabled.${RESET}\n"
else
  echo -e "${RED}❌ Failed to enable some APIs. Please check permissions.${RESET}"
  exit 1
fi

# ------------------ STEP 2: CREATE WORKBENCH INSTANCE ------------------
echo -e "${YELLOW}🧠 Creating Vertex AI Workbench managed instance...${RESET}"

# Note: Use `gcloud workbench instances` instead of deprecated notebooks
gcloud workbench instances create $INSTANCE_NAME \
  --location=$ZONE \
  --machine-type=n1-standard-4 \
  --boot-disk-type=PD_BALANCED \
  --boot-disk-size=200 \
  --data-disk-type=PD_BALANCED \
  --data-disk-size=200

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Workbench instance [$INSTANCE_NAME] created successfully.${RESET}"
else
  echo -e "${RED}❌ Instance creation failed. Please check error messages above.${RESET}"
  exit 1
fi

# ------------------ STEP 3: VERIFY STATUS ------------------
echo -e "${YELLOW}📊 Checking Workbench instance status...${RESET}"
gcloud workbench instances list --location=$ZONE

echo -e "${BLUE}\n📁 Task 1 Completed!"
echo -e "➡️ Instance Name : ${INSTANCE_NAME}"
echo -e "➡️ Location      : ${ZONE}${RESET}\n"
echo -e "${CYAN}🔗 Script provided by ePlus.DEV - https://eplus.dev${RESET}\n"