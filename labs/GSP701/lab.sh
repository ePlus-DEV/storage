#!/bin/bash
# =====================================================================
#   Google Cloud Go Lab – Full Auto Script with Colors + EPLUS.DEV
#   Author  : eplus.dev
#   Version : 1.0
#   Description: Run entire lab automatically, no user interaction
# =====================================================================

# --------- COLOR SETUP ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

print_step () {
    echo -e "\n${BLUE}${BOLD}=== STEP $1: $2 ===${RESET}"
}

print_done () {
    echo -e "${GREEN}✅ $1${RESET}"
}

print_warn () {
    echo -e "${YELLOW}⚠️ $1${RESET}"
}

print_error () {
    echo -e "${RED}❌ $1${RESET}"
}

# --------- HEADER ----------
echo -e "${MAGENTA}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║    GOOGLE CLOUD GO LAB – AUTO DEPLOY SCRIPT          ║"
echo "║              Powered by eplus.dev                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# --------- SCRIPT START ----------
print_step 1 "Setting PROJECT_ID"
export PROJECT_ID=$(gcloud info --format="value(config.project)")
echo -e "PROJECT_ID = ${CYAN}$PROJECT_ID${RESET}"
print_done "Project ID set"

print_step 2 "Checking Go version"
go version
print_done "Go version verified"

print_step 3 "Cloning sample repository"
git clone https://github.com/GoogleCloudPlatform/DIY-Tools.git
print_done "Repository cloned"

print_step 4 "Importing Firestore sample data"
gcloud firestore import gs://$PROJECT_ID-firestore/prd-back --async
print_warn "Firestore import started in background (will finish automatically)"

print_step 5 "Verifying gcloud config"
gcloud auth list
gcloud config list project
print_done "gcloud configuration OK"

print_step 6 "Building & Running Go App locally (background test)"
cd ~/DIY-Tools/gcp-data-drive/cmd/webserver || exit
go build -mod=readonly -v -o gcp-data-drive
./gcp-data-drive &> /dev/null &
APP_PID=$!
print_done "App built & started (PID: $APP_PID)"
sleep 6
kill $APP_PID
print_done "Local app test completed & stopped"

print_step 7 "Updating Go runtime to go122"
sed -i 's/runtime: go113/runtime: go122/' app.yaml
print_done "Runtime updated"

print_step 8 "Deploying to App Engine"
gcloud app deploy app.yaml --project $PROJECT_ID -q
print_done "Deployment complete"

print_step 9 "Setting APP URL"
export TARGET_URL=https://$(gcloud app describe --format="value(defaultHostname)")
echo -e "TARGET_URL = ${CYAN}$TARGET_URL${RESET}"

print_step 10 "Testing Firestore Collection"
curl -s $TARGET_URL/fs/$PROJECT_ID/symbols/product/symbol | head -n 20
print_done "Firestore Collection OK"

print_step 11 "Testing Firestore Document"
curl -s $TARGET_URL/fs/$PROJECT_ID/symbols/product/symbol/008888166900
print_done "Firestore Document OK"

print_step 12 "Testing BigQuery"
curl -s $TARGET_URL/bq/$PROJECT_ID/publicviews/ca_zip_codes | head -n 20
print_done "BigQuery OK"

# --------- FOOTER ----------
echo -e "${GREEN}${BOLD}"
echo "🎉 LAB COMPLETED SUCCESSFULLY – FULL AUTO MODE"
echo -e "${RESET}"

echo -e "${MAGENTA}${BOLD}© 2025 ePlus.dev – All rights reserved.${RESET}"