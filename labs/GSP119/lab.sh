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

# ---------------- CREATE API KEY ----------------
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
echo "${YELLOW}API_KEY=${RESET} ${GREEN}${API_KEY}${RESET}"
echo

cat > request.json <<EOF_END
{
    "config": {
        "encoding":"FLAC",
        "languageCode": "en-US"
    },
    "audio": {
        "uri":"gs://cloud-samples-tests/speech/brooklyn.flac"
    }
  }
EOF_END


curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
"https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}"


curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
"https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" > result.json

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#