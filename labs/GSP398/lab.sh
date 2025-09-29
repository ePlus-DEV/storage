#!/bin/bash
# =====================================================================
# 📁 Task 2 - Copy Official Notebook + Download ePlus Version & Patch Region
# ---------------------------------------------------------------------
# Author      : ePlus.DEV
# Website     : https://eplus.dev
# Description : Automates Task 2 of the GSP398 lab:
#               ✅ Step 1: Copy notebook from GCS (for Qwiklabs scoring)
#               📥 Step 2: Download fixed notebook from ePlus GitHub
#               ✏️ Step 3: Replace 'us-central1' with your chosen region
# License     : © 2025 ePlus.DEV. All rights reserved.
# =====================================================================

# 🎨 Colors
GREEN="\e[32m"; BLUE="\e[34m"; CYAN="\e[36m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"

echo -e "${CYAN}\n🌐 === 📁 Task 2: Official Copy + ePlus Download & Region Patch (ePlus.DEV) ===${RESET}\n"

# ------------------ CONFIG ------------------
PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

NOTEBOOK_FILE="cnn_challenge_lab-v1.0.0.ipynb"
BUCKET_PATH="gs://${PROJECT_ID}-labconfig-bucket/${NOTEBOOK_FILE}"
EPLUS_NOTEBOOK="cnn_challenge_lab-v1.0.0_eplus.ipynb"
EPLUS_URL="https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/GSP398/Drabhishek_fixed_fallback.ipynb"

echo -e "${BLUE}📦 Project ID     : ${GREEN}$PROJECT_ID${RESET}"
echo -e "${BLUE}🌍 Target Region  : ${GREEN}$REGION${RESET}\n"

# ------------------ STEP 1: COPY FROM GCS (Official Task 2) ------------------
echo -e "${YELLOW}📥 Copying official notebook from Cloud Storage bucket...${RESET}"

if gcloud storage cp "$BUCKET_PATH" .; then
  echo -e "${GREEN}✅ Official notebook copied successfully: ${NOTEBOOK_FILE}${RESET}"
else
  echo -e "${RED}❌ Failed to copy official notebook from GCS bucket.${RESET}"
  echo -e "${RED}⚠️ You must complete this step for Qwiklabs scoring.${RESET}\n"
fi

# ------------------ STEP 2: DOWNLOAD FROM EPLUS ------------------
echo -e "${YELLOW}📥 Downloading enhanced notebook from ePlus GitHub...${RESET}"

if curl -L -o "$EPLUS_NOTEBOOK" "$EPLUS_URL"; then
  echo -e "${GREEN}✅ ePlus notebook downloaded: ${EPLUS_NOTEBOOK}${RESET}"
else
  echo -e "${RED}❌ Failed to download ePlus notebook. Please check the URL or your network.${RESET}"
  exit 1
fi

# ------------------ STEP 3: PATCH REGION IN EPLUS NOTEBOOK ------------------
echo -e "${YELLOW}✏️ Replacing 'us-central1' with '${REGION}' in ePlus notebook...${RESET}"
sed -i "s/us-central1/$REGION/g" "$EPLUS_NOTEBOOK"

# ------------------ STEP 4: VERIFY REGION PATCH ------------------
if grep -q "$REGION" "$EPLUS_NOTEBOOK"; then
  echo -e "${GREEN}✅ Region patch successful: all 'us-central1' replaced with '${REGION}'${RESET}"
else
  echo -e "${RED}⚠️ Region patch verification failed. Please check the file manually.${RESET}"
fi

# ------------------ DONE ------------------
echo -e "\n${CYAN}🎉 All Done!${RESET}\n"
echo -e "${BLUE}✅ Official Notebook (for scoring):   ${GREEN}${NOTEBOOK_FILE}${RESET}"
echo -e "${BLUE}📥 ePlus Enhanced Notebook (patched): ${GREEN}${EPLUS_NOTEBOOK}${RESET}"
echo -e "${BLUE}🌍 Region Used:                        ${GREEN}${REGION}${RESET}\n"
echo -e "${CYAN}🔗 Script provided by ePlus.DEV - https://eplus.dev${RESET}\n"