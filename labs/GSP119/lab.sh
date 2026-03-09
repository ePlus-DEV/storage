#!/bin/bash

# ==========================================================
# Google Cloud Speech-to-Text Lab Automation
# Author: ePlus.DEV
# Copyright (c) 2026 ePlus.DEV
# ==========================================================

# ---------- COLORS ----------
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
BOLD=$(tput bold)
RESET=$(tput sgr0)
BG_MAGENTA=$(tput setab 5)
BG_RED=$(tput setab 1)

echo "${BG_MAGENTA}${BOLD} Starting Execution - ePlus.DEV ${RESET}"
echo

# ---------- CHECK PROJECT ----------
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    echo "${RED}❌ No active project found${RESET}"
    echo "${YELLOW}Run:${RESET} gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "${CYAN}${BOLD}Project:${RESET} ${PROJECT_ID}"
echo

# ---------- ENABLE REQUIRED APIS ----------
echo "${YELLOW}⚙️ Enabling required APIs...${RESET}"
gcloud services enable apikeys.googleapis.com speech.googleapis.com --quiet

if [[ $? -ne 0 ]]; then
    echo "${RED}❌ Failed to enable required APIs${RESET}"
    exit 1
fi

echo "${GREEN}✅ Required APIs enabled${RESET}"
echo

# ---------- CREATE API KEY ----------
echo "${YELLOW}🔑 Creating API Key...${RESET}"

CREATE_JSON=$(gcloud services api-keys create \
  --display-name="eplus-speech-api-key" \
  --format=json)

if [[ -z "$CREATE_JSON" ]]; then
    echo "${RED}❌ Failed to create API key${RESET}"
    exit 1
fi

API_KEY=$(echo "$CREATE_JSON" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("response", {}).get("keyString", ""))')

KEY_NAME=$(echo "$CREATE_JSON" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("response", {}).get("name", ""))')

if [[ -z "$API_KEY" && -n "$KEY_NAME" ]]; then
    API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format="value(keyString)")
fi

if [[ -z "$API_KEY" ]]; then
    echo "${RED}❌ API key created but could not retrieve key string${RESET}"
    exit 1
fi

export API_KEY="$API_KEY"

echo "${GREEN}✅ API Key Created${RESET}"
echo "${YELLOW}API_KEY=${RESET}${GREEN}${API_KEY}${RESET}"
echo

# ---------- CREATE request.json ----------
echo "${YELLOW}📄 Creating request.json...${RESET}"

cat > request.json <<EOF
{
  "config": {
    "encoding":"FLAC",
    "languageCode": "en-US"
  },
  "audio": {
    "uri":"gs://cloud-samples-tests/speech/brooklyn.flac"
  }
}
EOF

if [[ ! -f request.json ]]; then
    echo "${RED}❌ Failed to create request.json${RESET}"
    exit 1
fi

echo "${GREEN}✅ request.json created${RESET}"
echo
cat request.json
echo
echo

# ---------- CALL API AND SHOW RESULT ----------
echo "${YELLOW}📡 Calling Speech-to-Text API...${RESET}"
echo

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" | tee result.json

echo
echo

# ---------- VERIFY result.json ----------
if [[ -f result.json ]]; then
    echo "${GREEN}✅ result.json created${RESET}"
else
    echo "${RED}❌ Failed to create result.json${RESET}"
    exit 1
fi

echo
echo "${BG_RED}${BOLD} Congratulations For Completing!!! - ePlus.DEV ${RESET}"