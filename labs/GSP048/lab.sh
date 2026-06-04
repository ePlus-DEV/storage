#!/bin/bash
set -euo pipefail

# ==========================================================
#  Google Cloud Speech-to-Text API Lab
#  Copyright © ePlus.DEV
# ==========================================================

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
BOLD="\033[1m"
NC="\033[0m"

banner() {
  echo -e "${CYAN}${BOLD}"
  echo "============================================================"
  echo "        Google Cloud Speech-to-Text API Lab"
  echo "                    © ePlus.DEV"
  echo "============================================================"
  echo -e "${NC}"
}

step() {
  echo -e "${YELLOW}${BOLD}[$1] $2${NC}"
}

ok() {
  echo -e "${GREEN}[OK] $1${NC}"
}

err() {
  echo -e "${RED}[ERROR] $1${NC}"
}

banner

# ----------------------------------------------------------
# 1. Get project info
# ----------------------------------------------------------
step "1/7" "Detecting Google Cloud project..."

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [ -z "${PROJECT_ID}" ]; then
  err "Cannot detect PROJECT_ID. Make sure you are logged in inside the lab VM."
  exit 1
fi

ok "PROJECT_ID = ${PROJECT_ID}"

# ----------------------------------------------------------
# 2. Enable required APIs
# ----------------------------------------------------------
step "2/7" "Enabling required APIs..."

gcloud services enable speech.googleapis.com --project="${PROJECT_ID}"
gcloud services enable apikeys.googleapis.com --project="${PROJECT_ID}"

ok "Enabled Speech-to-Text API and API Keys API."

# ----------------------------------------------------------
# 3. Create API key automatically
# ----------------------------------------------------------
step "3/7" "Creating API key restricted to Cloud Speech-to-Text API..."

KEY_NAME="speech-lab-key-$(date +%s)"

CREATE_OK=0

if gcloud services api-keys create \
  --project="${PROJECT_ID}" \
  --display-name="${KEY_NAME}" \
  --api-target=service=speech.googleapis.com >/tmp/create_key.log 2>&1; then
  CREATE_OK=1
else
  echo -e "${YELLOW}[WARN] Stable api-keys command failed. Trying alpha command...${NC}"

  if gcloud alpha services api-keys create \
    --project="${PROJECT_ID}" \
    --display-name="${KEY_NAME}" \
    --api-target=service=speech.googleapis.com >/tmp/create_key.log 2>&1; then
    CREATE_OK=2
  fi
fi

if [ "${CREATE_OK}" = "0" ]; then
  err "Failed to create API key."
  echo "----- Error log -----"
  cat /tmp/create_key.log
  echo "---------------------"
  exit 1
fi

sleep 5

if [ "${CREATE_OK}" = "1" ]; then
  KEY_ID="$(gcloud services api-keys list \
    --project="${PROJECT_ID}" \
    --filter="displayName=${KEY_NAME}" \
    --format="value(name)" \
    --limit=1)"
else
  KEY_ID="$(gcloud alpha services api-keys list \
    --project="${PROJECT_ID}" \
    --filter="displayName=${KEY_NAME}" \
    --format="value(name)" \
    --limit=1)"
fi

if [ -z "${KEY_ID}" ]; then
  err "API key was created but KEY_ID cannot be found."
  exit 1
fi

if [ "${CREATE_OK}" = "1" ]; then
  API_KEY="$(gcloud services api-keys get-key-string "${KEY_ID}" \
    --project="${PROJECT_ID}" \
    --format="value(keyString)")"
else
  API_KEY="$(gcloud alpha services api-keys get-key-string "${KEY_ID}" \
    --project="${PROJECT_ID}" \
    --format="value(keyString)")"
fi

if [ -z "${API_KEY}" ]; then
  err "Cannot get API key string."
  exit 1
fi

export API_KEY

ok "API key created successfully."
echo -e "${BLUE}API_KEY=${API_KEY}${NC}"
echo

echo -e "${CYAN}${BOLD}>>> Now click: Check my progress - Create an API Key${NC}"
echo

# ----------------------------------------------------------
# 4. Create English request
# ----------------------------------------------------------
step "4/7" "Creating English Speech API request..."

cat > request.json <<'JSON'
{
  "config": {
    "encoding": "FLAC",
    "languageCode": "en-US"
  },
  "audio": {
    "uri": "gs://cloud-samples-data/speech/brooklyn_bridge.flac"
  }
}
JSON

ok "Created request.json for English audio."
echo
cat request.json
echo

echo -e "${CYAN}${BOLD}>>> Now click: Check my progress - Create your Speech API request${NC}"
echo

# ----------------------------------------------------------
# 5. Call English Speech API
# ----------------------------------------------------------
step "5/7" "Calling Speech-to-Text API for English audio..."

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" \
  > result.json

ok "English transcription result saved to result.json."
echo
cat result.json
echo

if grep -qi "Brooklyn Bridge" result.json; then
  ok "English transcript looks correct."
else
  echo -e "${YELLOW}[WARN] Could not verify expected English transcript. Check result.json above.${NC}"
fi

echo
echo -e "${CYAN}${BOLD}>>> Now click: Check my progress - Call the Speech API for English language${NC}"
echo

# ----------------------------------------------------------
# 6. Create French request
# ----------------------------------------------------------
step "6/7" "Creating French Speech API request..."

cat > request.json <<'JSON'
{
  "config": {
    "encoding": "FLAC",
    "languageCode": "fr"
  },
  "audio": {
    "uri": "gs://cloud-samples-data/speech/corbeau_renard.flac"
  }
}
JSON

ok "Updated request.json for French audio."
echo
cat request.json
echo

# ----------------------------------------------------------
# 7. Call French Speech API
# ----------------------------------------------------------
step "7/7" "Calling Speech-to-Text API for French audio..."

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" \
  > result.json

ok "French transcription result saved to result.json."
echo
cat result.json
echo

if grep -qi "corbeau" result.json; then
  ok "French transcript looks correct."
else
  echo -e "${YELLOW}[WARN] Could not verify expected French transcript. Check result.json above.${NC}"
fi

echo
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}  DONE - Speech-to-Text API Lab completed © ePlus.DEV${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo
echo -e "${CYAN}${BOLD}Final step:${NC}"
echo "Click: Check my progress - Call the Speech API for French language"
echo