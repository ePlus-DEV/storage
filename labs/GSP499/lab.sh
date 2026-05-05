#!/bin/bash

set -e

# =========================
# Colors
# =========================
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
CYAN='\033[0;96m'
BOLD='\033[1m'
NC='\033[0m'

clear

echo -e "${CYAN}${BOLD}============================================================${NC}"
echo -e "${CYAN}${BOLD}        User Authentication with IAP - ePlus.DEV       ${NC}"
echo -e "${CYAN}${BOLD}============================================================${NC}"
echo ""

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
APP_URL="https://${PROJECT_ID}.appspot.com"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo -e "${RED}Project ID not found. Please make sure Cloud Shell is using the correct lab project.${NC}"
  exit 1
fi

if [[ -z "$ACCOUNT" || "$ACCOUNT" == "(unset)" ]]; then
  echo -e "${RED}Active account not found. Please run: gcloud auth list${NC}"
  exit 1
fi

echo -e "${GREEN}Project:${NC} $PROJECT_ID"
echo -e "${GREEN}Account:${NC} $ACCOUNT"
echo -e "${GREEN}App URL:${NC} $APP_URL"
echo ""

# =========================
# Enable APIs
# =========================
echo -e "${BLUE}Enabling required APIs...${NC}"
gcloud services enable \
  appengine.googleapis.com \
  iap.googleapis.com \
  cloudbuild.googleapis.com \
  --quiet

# Lab note:
# Disable App Engine Flex API before enabling IAP for App Engine.
# This avoids the missing Flex service account issue in some lab projects.
echo -e "${BLUE}Disabling App Engine Flex API if it is enabled...${NC}"
gcloud services disable appengineflex.googleapis.com --quiet || true

# =========================
# Create App Engine app if needed
# =========================
echo -e "${BLUE}Checking App Engine application...${NC}"
if ! gcloud app describe --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo -e "${YELLOW}App Engine application does not exist. Creating it in us-central...${NC}"
  gcloud app create --region=us-central --project="$PROJECT_ID" --quiet
else
  echo -e "${GREEN}App Engine application already exists.${NC}"
fi

# =========================
# Download source code
# =========================
echo -e "${BLUE}Downloading lab source code...${NC}"
cd "$HOME"
rm -rf user-authentication-with-iap user-authentication-with-iap.zip

gsutil cp gs://spls/gsp499/user-authentication-with-iap.zip .
unzip -q user-authentication-with-iap.zip

# =========================
# Helper deploy function
# =========================
deploy_step() {
  local STEP_DIR="$1"
  local STEP_NAME="$2"

  echo ""
  echo -e "${CYAN}${BOLD}============================================================${NC}"
  echo -e "${CYAN}${BOLD}Deploying ${STEP_NAME}${NC}"
  echo -e "${CYAN}${BOLD}============================================================${NC}"

  cd "$HOME/user-authentication-with-iap/${STEP_DIR}"

  if [[ -f app.yaml ]]; then
    sed -i 's/python37/python313/g' app.yaml
  fi

  gcloud app deploy app.yaml --quiet

  echo -e "${GREEN}Finished deploying ${STEP_NAME}.${NC}"
  echo -e "${GREEN}Open app:${NC} $APP_URL"
}

# =========================
# Task 1 - Hello World
# =========================
deploy_step "1-HelloWorld" "Task 1 - HelloWorld"

echo ""
echo -e "${YELLOW}${BOLD}TASK 1 CHECKPOINT${NC}"
echo -e "${YELLOW}Open the URL below and verify the Hello World page:${NC}"
echo -e "${CYAN}$APP_URL${NC}"
echo ""
echo -e "${YELLOW}Then click 'Check my progress' for:${NC}"
echo -e "${YELLOW}- Deploy an App Engine application${NC}"
echo ""

# =========================
# Add current student account to IAP role
# =========================
echo -e "${BLUE}Adding the current student account to the IAP-Secured Web App User role...${NC}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:${ACCOUNT}" \
  --role="roles/iap.httpsResourceAccessor" \
  --quiet >/dev/null

echo -e "${GREEN}IAP access role has been added for:${NC} $ACCOUNT"

# =========================
# Try to enable IAP from gcloud
# =========================
echo ""
echo -e "${BLUE}Trying to enable IAP for App Engine using gcloud...${NC}"

set +e
IAP_ENABLE_OUTPUT="$(gcloud iap web enable --resource-type=app-engine --versions=default 2>&1)"
IAP_ENABLE_STATUS=$?
set -e

if [[ $IAP_ENABLE_STATUS -eq 0 ]]; then
  echo -e "${GREEN}IAP was enabled successfully using gcloud.${NC}"
else
  echo -e "${YELLOW}IAP could not be fully enabled using gcloud in this lab environment.${NC}"
  echo -e "${YELLOW}This usually happens because the OAuth consent screen has not been configured yet.${NC}"
  echo ""
  echo -e "${CYAN}${BOLD}Please complete these steps manually in the Google Cloud Console:${NC}"
  echo ""
  echo -e "1. Go to: ${BOLD}Security > Identity-Aware Proxy${NC}"
  echo -e "2. If asked to configure the OAuth consent screen:"
  echo -e "   - App name: ${BOLD}IAP Example${NC}"
  echo -e "   - Audience: ${BOLD}Internal${NC}"
  echo -e "   - User support email: ${BOLD}${ACCOUNT}${NC}"
  echo -e "   - Contact email: ${BOLD}${ACCOUNT}${NC}"
  echo -e "   - Agree to the User Data Policy"
  echo -e "   - Click ${BOLD}Create${NC}"
  echo -e "3. Return to the Identity-Aware Proxy page and refresh it."
  echo -e "4. Turn ON IAP for the ${BOLD}App Engine app${NC} row."
  echo -e "5. Select the checkbox next to ${BOLD}App Engine app${NC}."
  echo -e "6. Click ${BOLD}Add Principal${NC}."
  echo -e "7. Principal: ${BOLD}${ACCOUNT}${NC}"
  echo -e "8. Role: ${BOLD}Cloud IAP > IAP-Secured Web App User${NC}"
  echo -e "9. Click ${BOLD}Save${NC}"
  echo ""
  echo -e "${YELLOW}gcloud error details:${NC}"
  echo "$IAP_ENABLE_OUTPUT"
fi

echo ""
echo -e "${YELLOW}${BOLD}TASK 1 IAP CHECKPOINT${NC}"
echo -e "${YELLOW}After enabling IAP and adding the principal, click 'Check my progress' for:${NC}"
echo -e "${YELLOW}- Enable and add policy to IAP${NC}"
echo ""

read -p "After finishing the Task 1 / IAP checkpoint in the Console, press Enter to continue with Task 2..."

# =========================
# Task 2 - Hello User
# =========================
deploy_step "2-HelloUser" "Task 2 - HelloUser"

echo ""
echo -e "${YELLOW}${BOLD}TASK 2 CHECKPOINT${NC}"
echo -e "${YELLOW}Open the app and verify that your email and persistent user ID are displayed:${NC}"
echo -e "${CYAN}$APP_URL${NC}"
echo ""
echo -e "${YELLOW}Then click 'Check my progress' for:${NC}"
echo -e "${YELLOW}- Access User Identity Information${NC}"
echo ""

read -p "After finishing the Task 2 checkpoint, press Enter to continue with Task 3..."

# =========================
# Task 3 - Hello Verified User
# =========================
deploy_step "3-HelloVerifiedUser" "Task 3 - HelloVerifiedUser"

echo ""
echo -e "${YELLOW}${BOLD}TASK 3 CHECKPOINT${NC}"
echo -e "${YELLOW}If you turned IAP off earlier for testing, turn it back on now.${NC}"
echo -e "${YELLOW}Refresh the app and verify the Verified User information:${NC}"
echo -e "${CYAN}$APP_URL${NC}"
echo ""
echo -e "${YELLOW}Then click 'Check my progress' for:${NC}"
echo -e "${YELLOW}- Use Cryptographic Verification${NC}"

echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}Lab script finished.${NC}" - ePlus.DEV
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}App URL:${NC} $APP_URL"
echo -e "${GREEN}Student account:${NC} $ACCOUNT"
echo ""