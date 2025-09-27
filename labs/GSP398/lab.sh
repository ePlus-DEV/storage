#!/bin/bash
# =====================================================================
# 📁 Task 2 - Copy CNN Challenge Notebook & Patch Region (Auto Bucket)
# ---------------------------------------------------------------------
# Author      : ePlus.DEV
# Website     : https://eplus.dev
# Version     : 2025.2
# Description : Automates Task 2 of GSP398 challenge lab.
#               - Dynamically builds bucket name from PROJECT_ID
#               - Copies notebook from Cloud Storage
#               - Falls back to GitHub if copy fails
#               - Patches region from us-central1 to us-west1
# License     : © 2025 ePlus.DEV. All rights reserved.
# =====================================================================

# 🎨 Colors
GREEN="\e[32m"; BLUE="\e[34m"; CYAN="\e[36m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"

echo -e "${CYAN}\n=== 📁 Task 2: Copy Notebook & Patch Region (Auto Bucket - ePlus.DEV) ===${RESET}\n"

# ------------------ CONFIG ------------------
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud config get-value project)
NOTEBOOK_FILE="cnn_challenge_lab-v1.0.0.ipynb"
BUCKET_NAME="${PROJECT_ID}-labconfig-bucket"
BUCKET_PATH="gs://${BUCKET_NAME}/${NOTEBOOK_FILE}"
FALLBACK_URL="https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/GSP398/Drabhishek_fixed_fallback.ipynb"

echo -e "${BLUE}📦 Using PROJECT_ID: ${GREEN}$PROJECT_ID${RESET}"
echo -e "${BLUE}☁️  Constructed bucket path: ${GREEN}$BUCKET_PATH${RESET}\n"

# ------------------ STEP 1: COPY FROM GCS ------------------
echo -e "${YELLOW}📥 Attempting to copy notebook from Cloud Storage...${RESET}"
if gcloud storage cp "$BUCKET_PATH" .; then
  echo -e "${GREEN}✅ Notebook copied successfully from GCS.${RESET}"
else
  echo -e "${RED}⚠️ Failed to copy from $BUCKET_PATH. Trying fallback from GitHub...${RESET}"
  curl -L -o "$NOTEBOOK_FILE" "$FALLBACK_URL"
fi

# ------------------ STEP 2: VERIFY FILE ------------------
if [ ! -f "$NOTEBOOK_FILE" ]; then
  echo -e "${RED}❌ Notebook not found. Exiting.${RESET}"
  exit 1
fi
echo -e "${GREEN}✅ Notebook is ready: $NOTEBOOK_FILE${RESET}\n"

# ------------------ STEP 3: PATCH REGION ------------------
echo -e "${YELLOW}✏️ Replacing region 'us-central1' with '$REGION'...${RESET}"
sed -i "s/us-central1/$REGION/g" "$NOTEBOOK_FILE"

# ------------------ STEP 4: VERIFY PATCH ------------------
if grep -q "$REGION" "$NOTEBOOK_FILE"; then
  echo -e "${GREEN}✅ Region successfully updated to: $REGION${RESET}"
else
  echo -e "${RED}⚠️ Region replacement could not be verified. Please check manually.${RESET}"
fi

# ------------------ DONE ------------------
echo -e "${BLUE}\n📁 Task 2 Completed!"
echo -e "➡️ Notebook ready: ${NOTEBOOK_FILE}"
echo -e "➡️ Region set to: ${REGION}${RESET}\n"
echo -e "${CYAN}🔗 Script provided by ePlus.DEV - https://eplus.dev${RESET}\n"