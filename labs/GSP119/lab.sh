#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

#----------------------------------------------------start--------------------------------------------------#

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV ${RESET}"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
  echo "${RED}${BOLD}❌ Project ID not found.${RESET}"
  exit 1
fi

echo "${CYAN}${BOLD}Project:${RESET} $PROJECT_ID"

# ---------------- ENABLE REQUIRED APIS ----------------
echo "${YELLOW}${BOLD}🔧 Enabling required APIs...${RESET}"

gcloud services enable \
  apikeys.googleapis.com \
  speech.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

# ---------------- CREATE OR GET API KEY ----------------
KEY_DISPLAY_NAME="eplus-speech-api-key"

echo "${YELLOW}${BOLD}🔑 Checking API Key: ${KEY_DISPLAY_NAME}...${RESET}"

KEY_NAME=$(gcloud services api-keys list \
  --project="$PROJECT_ID" \
  --filter="displayName=${KEY_DISPLAY_NAME}" \
  --format="value(name)" \
  --limit=1 2>/dev/null)

if [[ -z "$KEY_NAME" ]]; then
  echo "${YELLOW}${BOLD}🔑 API Key not found. Creating new key...${RESET}"

  CREATE_JSON=$(gcloud services api-keys create \
    --project="$PROJECT_ID" \
    --display-name="$KEY_DISPLAY_NAME" \
    --format=json \
    --quiet)

  if [[ -z "$CREATE_JSON" ]]; then
    echo "${RED}${BOLD}❌ Failed to create API key.${RESET}"
    exit 1
  fi

  KEY_NAME=$(echo "$CREATE_JSON" | python3 -c 'import sys,json; data=json.load(sys.stdin); print(data.get("response", {}).get("name", ""))')

  if [[ -z "$KEY_NAME" ]]; then
    echo "${YELLOW}${BOLD}⏳ Waiting for API key to become available...${RESET}"
    sleep 10

    KEY_NAME=$(gcloud services api-keys list \
      --project="$PROJECT_ID" \
      --filter="displayName=${KEY_DISPLAY_NAME}" \
      --format="value(name)" \
      --limit=1)
  fi
else
  echo "${GREEN}${BOLD}✅ Existing API Key found.${RESET}"
fi

if [[ -z "$KEY_NAME" ]]; then
  echo "${RED}${BOLD}❌ Could not get API key name.${RESET}"
  exit 1
fi

API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" \
  --project="$PROJECT_ID" \
  --format="value(keyString)" 2>/dev/null)

if [[ -z "$API_KEY" ]]; then
  echo "${RED}${BOLD}❌ API key exists but could not retrieve key string.${RESET}"
  exit 1
fi

export API_KEY="$API_KEY"

echo "${GREEN}${BOLD}✅ API Key ready.${RESET}"
echo "${YELLOW}${BOLD}API_KEY=${RESET} ${GREEN}${API_KEY}${RESET}"
echo

# ---------------- CREATE REQUEST JSON ----------------
echo "${YELLOW}${BOLD}📝 Creating request.json...${RESET}"

cat > request.json <<EOF_END
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

# ---------------- CALL SPEECH API ----------------
echo "${YELLOW}${BOLD}🎤 Calling Cloud Speech-to-Text API...${RESET}"

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" \
  > result.json

echo
echo "${CYAN}${BOLD}===== API RESPONSE =====${RESET}"
cat result.json
echo

# ---------------- CHECK RESULT ----------------
if grep -q "how old is the Brooklyn Bridge" result.json; then
  echo "${GREEN}${BOLD}✅ Speech API test completed successfully.${RESET}"
else
  echo "${YELLOW}${BOLD}⚠️ API call completed, please check result.json manually.${RESET}"
fi

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#