#!/bin/bash

# ==========================================================
#  Google Cloud API Key + Speech-to-Text Test
#  Author: ePlus.DEV
#  Copyright (c) 2026 ePlus.DEV
# ==========================================================

# ----------------------------- Colors -----------------------------
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)
NC="$RESET"

# ----------------------------- Start -----------------------------
echo "${BG_MAGENTA}${BOLD} Starting Execution - ePlus.DEV ${RESET}"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  echo "${RED}❌ No active project found.${RESET}"
  echo "${YELLOW}Run:${RESET} gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

echo "${CYAN}${BOLD}Project:${RESET} ${PROJECT_ID}"

echo "${YELLOW}⚙️ Enabling required APIs...${NC}"
gcloud services enable apikeys.googleapis.com speech.googleapis.com --quiet

echo "${YELLOW}🔑 Creating API Key...${NC}"

CREATE_JSON=$(gcloud services api-keys create \
  --display-name="eplus-api-key" \
  --format=json)

if [ -z "$CREATE_JSON" ]; then
  echo "${RED}❌ Failed to create API key.${RESET}"
  exit 1
fi

KEY_NAME=$(echo "$CREATE_JSON" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("response", {}).get("name", ""))')
API_KEY=$(echo "$CREATE_JSON" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("response", {}).get("keyString", ""))')

# Fallback: if keyString not returned directly, fetch again using key resource name
if [ -z "$API_KEY" ] && [ -n "$KEY_NAME" ]; then
  API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format="value(keyString)")
fi

if [ -z "$API_KEY" ]; then
  echo "${RED}❌ API key was created, but key string could not be retrieved.${RESET}"
  echo "${YELLOW}Key resource:${RESET} ${KEY_NAME}"
  exit 1
fi

echo
echo "${GREEN}✅ API Key Created Successfully!${NC}"
echo "${YELLOW}Key Resource:${NC} ${KEY_NAME}"
echo "${YELLOW}API KEY:${NC} ${GREEN}${API_KEY}${NC}"
echo

cat > request.json <<'EOF_END'
{
  "config": {
    "encoding": "FLAC",
    "languageCode": "en-US"
  },
  "audio": {
    "uri": "gs://cloud-samples-tests/speech/brooklyn.flac"
  }
}
EOF_END

echo "${YELLOW}🎤 Sending Speech-to-Text request...${NC}"

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" | tee result.json

echo
echo "${BG_RED}${BOLD} Congratulations For Completing!!! - ePlus.DEV ${RESET}"