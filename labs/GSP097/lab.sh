#!/bin/bash

# ============================================================
#   Google Cloud Natural Language API Lab
#   Automated Lab Script
#   Copyright (c) ePlus.DEV
# ============================================================

# ---------------------- COLORS -------------------------------
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ---------------------- FUNCTIONS ----------------------------
header() {
  echo
  echo "${CYAN}${BOLD}============================================================${RESET}"
  echo "${MAGENTA}${BOLD}          Google Cloud Natural Language API Lab             ${RESET}"
  echo "${YELLOW}${BOLD}                     ePlus.DEV                              ${RESET}"
  echo "${CYAN}${BOLD}============================================================${RESET}"
  echo
}

step() {
  echo
  echo "${BLUE}${BOLD}▶ $1${RESET}"
}

success() {
  echo "${GREEN}${BOLD}✔ $1${RESET}"
}

warning() {
  echo "${YELLOW}${BOLD}⚠ $1${RESET}"
}

error() {
  echo "${RED}${BOLD}✘ $1${RESET}"
}

header

# ============================================================
# PROJECT CONFIGURATION
# ============================================================

step "Detecting Google Cloud project..."

export GOOGLE_CLOUD_PROJECT="$(gcloud config get-value core/project 2>/dev/null)"

if [[ -z "$GOOGLE_CLOUD_PROJECT" || "$GOOGLE_CLOUD_PROJECT" == "(unset)" ]]; then
  error "Unable to detect PROJECT_ID."
else
  success "PROJECT_ID: $GOOGLE_CLOUD_PROJECT"
fi

SERVICE_ACCOUNT_NAME="my-natlang-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"
KEY_FILE="$HOME/key.json"

# ============================================================
# TASK 1 - CREATE SERVICE ACCOUNT / API CREDENTIALS
# ============================================================

step "TASK 1 - Enabling Cloud Natural Language API..."

gcloud services enable language.googleapis.com \
  --project="$GOOGLE_CLOUD_PROJECT" \
  --quiet

if [[ $? -eq 0 ]]; then
  success "Cloud Natural Language API enabled."
else
  warning "API enable command returned an error."
  warning "Continuing because the lab may already have the API enabled."
fi


step "Checking service account..."

if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" \
  --project="$GOOGLE_CLOUD_PROJECT" \
  >/dev/null 2>&1; then

  success "Service account already exists: $SERVICE_ACCOUNT_NAME"

else

  step "Creating service account..."

  gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
    --display-name="my natural language service account" \
    --project="$GOOGLE_CLOUD_PROJECT"

  if [[ $? -eq 0 ]]; then
    success "Service account created."
  else
    error "Could not create service account."
  fi
fi


step "Creating service account JSON key..."

# Remove old local key only.
# This does NOT delete the service account.
rm -f "$KEY_FILE"

gcloud iam service-accounts keys create "$KEY_FILE" \
  --iam-account="$SERVICE_ACCOUNT_EMAIL" \
  --project="$GOOGLE_CLOUD_PROJECT"

if [[ $? -eq 0 ]]; then
  success "Credential key created: $KEY_FILE"
else
  error "Could not create service account key."
fi


step "Setting GOOGLE_APPLICATION_CREDENTIALS..."

export GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE"

success "GOOGLE_APPLICATION_CREDENTIALS=$GOOGLE_APPLICATION_CREDENTIALS"


echo
echo "${GREEN}${BOLD}============================================================${RESET}"
echo "${GREEN}${BOLD}                  TASK 1 COMPLETED                          ${RESET}"
echo "${GREEN}${BOLD}============================================================${RESET}"
echo
echo "${YELLOW}→ You can now click:${RESET}"
echo "${WHITE}${BOLD}   Check my progress → Create an API Key${RESET}"
echo


# ============================================================
# TASK 2 - ENTITY ANALYSIS
# ============================================================

step "TASK 2 - Sending Entity Analysis request..."

gcloud ml language analyze-entities \
  --content="Michelangelo Caravaggio, Italian painter, is known for 'The Calling of Saint Matthew'." \
  > "$HOME/result.json"

if [[ $? -eq 0 ]]; then
  success "Entity analysis completed."
else
  error "Entity analysis request failed."
fi


# ============================================================
# DISPLAY RESULT
# ============================================================

step "Displaying result.json..."

echo
echo "${CYAN}${BOLD}---------------- Natural Language API Result ---------------${RESET}"
echo

cat "$HOME/result.json"

echo
echo "${CYAN}${BOLD}------------------------------------------------------------${RESET}"


# ============================================================
# VERIFY FILES
# ============================================================

step "Verifying lab resources..."

echo
echo "${WHITE}Project:${RESET}"
echo "  $GOOGLE_CLOUD_PROJECT"

echo
echo "${WHITE}Service Account:${RESET}"
echo "  $SERVICE_ACCOUNT_EMAIL"

echo
echo "${WHITE}Credentials:${RESET}"
if [[ -f "$KEY_FILE" ]]; then
  echo "  ${GREEN}✔ $KEY_FILE${RESET}"
else
  echo "  ${RED}✘ $KEY_FILE not found${RESET}"
fi

echo
echo "${WHITE}Entity Analysis Result:${RESET}"
if [[ -f "$HOME/result.json" ]]; then
  echo "  ${GREEN}✔ $HOME/result.json${RESET}"
else
  echo "  ${RED}✘ $HOME/result.json not found${RESET}"
fi


# ============================================================
# FINISH
# ============================================================

echo
echo "${GREEN}${BOLD}============================================================${RESET}"
echo "${GREEN}${BOLD}             ✔ ALL LAB TASKS COMPLETED                     ${RESET}"
echo "${MAGENTA}${BOLD}                     ePlus.DEV                              ${RESET}"
echo "${GREEN}${BOLD}============================================================${RESET}"
echo
echo "${YELLOW}Now click:${RESET}"
echo "${WHITE}${BOLD}  ✔ Check my progress → Create an API Key${RESET}"
echo "${WHITE}${BOLD}  ✔ Check my progress → Make an Entity Analysis Request${RESET}"
echo