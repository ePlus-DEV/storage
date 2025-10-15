#!/bin/bash
# ==============================================
# 🌐 IAP Lab Full Script (Background Deploy)
# ✨ Auto deploy + log + color output
# 🧑 Author: David (eplus.dev)
# ==============================================

# --- COLOR CODES ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
RESET='\033[0m'

set -e

# --- STEP 0: VARIABLES ---
PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
APP_NAME="IAP Example"
LOG_DIR="$HOME/iap_logs"
mkdir -p "$LOG_DIR"

echo -e "${CYAN}==============================================${RESET}"
echo -e " ${PURPLE}🚀 IAP Full Lab Deploy Script${RESET}"
echo -e " ${GREEN}Project:${RESET} $PROJECT_ID"
echo -e " ${GREEN}Region:${RESET} $REGION"
echo -e " ${GREEN}Logs:${RESET} $LOG_DIR"
echo -e "${CYAN}==============================================${RESET}"

# --- STEP 1: DOWNLOAD STARTER CODE ---
echo -e "${YELLOW}📥 Downloading starter code...${RESET}"
if [ ! -d "user-authentication-with-iap" ]; then
  gsutil cp gs://spls/gsp499/user-authentication-with-iap.zip .
  unzip -q user-authentication-with-iap.zip
fi
cd user-authentication-with-iap

# 📦 FUNCTION: Background deploy
deploy_bg() {
  local folder=$1
  local step=$2
  echo -e "${BLUE}🚀 [Step $step] Deploying: $folder${RESET}"
  cd "$folder"
  sed -i 's/python37/python39/g' app.yaml
  nohup gcloud app deploy --quiet > "$LOG_DIR/step${step}.log" 2>&1 &
  DEPLOY_PID=$!
  echo -e "👉 ${YELLOW}Deployment is running in the background (PID: $DEPLOY_PID)${RESET}"
  echo -e "📄 View logs with: ${GREEN}tail -f $LOG_DIR/step${step}.log${RESET}"
  cd ..
}

# --- STEP 2: Deploy Hello World ---
deploy_bg "1-HelloWorld" 1
echo -e "⏳ ${CYAN}Please wait 2–3 minutes for deployment to finish...${RESET}"

# --- STEP 3: Disable Flex API ---
echo -e "${YELLOW}⚡ Disabling Flex API (IAP requirement)...${RESET}"
gcloud services disable appengineflex.googleapis.com --quiet

# --- STEP 4: Enable IAP API ---
echo -e "${YELLOW}🔐 Enabling IAP API...${RESET}"
gcloud services enable iap.googleapis.com --quiet

echo -e "${PURPLE}⚠️ Manual step required:${RESET}"
echo -e "👉 Open the link: ${BLUE}https://console.cloud.google.com/apis/credentials/consent?project=$PROJECT_ID${RESET}"
echo -e "👉 Configure the OAuth consent screen → Enable IAP → Add your email with 'IAP-Secured Web App User' role."
read -p "⏸️ Press ENTER once you have finished the IAP configuration..."

# --- STEP 5: Deploy Hello User ---
deploy_bg "2-HelloUser" 2
echo -e "⏳ ${CYAN}Please wait 2–3 minutes for deployment to finish...${RESET}"

# --- STEP 6: Demo spoof (optional) ---
APP_URL=$(gcloud app browse --no-launch-browser)
echo -e "${RED}💀 Spoof test when IAP is OFF:${RESET}"
echo -e "${YELLOW}curl -X GET $APP_URL -H \"X-Goog-Authenticated-User-Email: fakeuser@gmail.com\"${RESET}"

# --- STEP 7: Deploy Hello Verified User ---
deploy_bg "3-HelloVerifiedUser" 3
echo -e "⏳ ${CYAN}Please wait 2–3 minutes for deployment to finish...${RESET}"

# --- STEP 8: SUMMARY ---
echo -e ""
echo -e "${GREEN}🎉 All deployment processes are now running in the background!${RESET}"
echo -e "📡 App URL: ${BLUE}$APP_URL${RESET}"
echo -e "📝 Logs:"
echo -e "   tail -f $LOG_DIR/step1.log  # Hello World"
echo -e "   tail -f $LOG_DIR/step2.log  # Hello User"
echo -e "   tail -f $LOG_DIR/step3.log  # Hello Verified User"
echo -e ""
echo -e "${YELLOW}📌 After re-enabling IAP, refresh the web page to test user authentication.${RESET}"
echo -e "${CYAN}==============================================${RESET}"
echo -e "  © 2025 ${PURPLE}ePlus.DEV${RESET} | 🌐 https://eplus.dev"
echo -e "  🧑 Script by David | Identity-Aware Proxy Lab Helper"
echo -e "${CYAN}==============================================${RESET}"
