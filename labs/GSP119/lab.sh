#!/bin/bash

# ==========================================================
#  Google Cloud Speech API Test Script
#  Author: ePlus.DEV
#  Copyright (c) 2026 ePlus.DEV
# ==========================================================

# ---------------- COLORS ----------------
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_MAGENTA=$(tput setab 5)
BG_RED=$(tput setab 1)

BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---------------- START ----------------

echo "${BG_MAGENTA}${BOLD} Starting Execution - ePlus.DEV ${RESET}"
echo

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    echo "${RED}❌ No active project found${RESET}"
    echo "${YELLOW}Run:${RESET} gcloud config set project PROJECT_ID"
    exit 1
fi

echo "${CYAN}📦 Project:${RESET} ${PROJECT_ID}"
echo

echo "${YELLOW}⚙️ Enabling APIs...${RESET}"
gcloud services enable apikeys.googleapis.com speech.googleapis.com --quiet

echo
echo "${YELLOW}🔑 Creating API Key...${RESET}"

CREATE_JSON=$(gcloud services api-keys create \
    --display-name="eplus-api-key" \
    --format=json)

KEY_NAME=$(echo "$CREATE_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["response"]["name"])')
API_KEY=$(echo "$CREATE_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["response"]["keyString"])')

if [ -z "$API_KEY" ]; then
    API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format="value(keyString)")
fi

echo
echo "${GREEN}✅ API Key Created${RESET}"
echo "${YELLOW}API KEY:${RESET} ${GREEN}${API_KEY}${RESET}"
echo

# ---------------- REQUEST JSON ----------------

cat > request.json <<EOF
{
  "config": {
    "encoding": "FLAC",
    "languageCode": "en-US"
  },
  "audio": {
    "uri": "gs://cloud-samples-tests/speech/brooklyn.flac"
  }
}
EOF

echo "${CYAN}📄 Request JSON created${RESET}"
echo

# ---------------- CALL API ----------------

echo "${YELLOW}📡 Calling Speech-to-Text API...${RESET}"
echo

curl -s -X POST \
-H "Content-Type: application/json" \
--data-binary @request.json \
"https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" \
| tee result.json

echo
echo "${GREEN}📁 Result saved to result.json${RESET}"
echo

echo "${BG_RED}${BOLD} Congratulations For Completing!!! - ePlus.DEV ${RESET}"