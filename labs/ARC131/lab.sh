#!/bin/bash

set -e

# Define color variables
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

#----------------------------------------------------start--------------------------------------------------#

echo "${YELLOW}${BOLD}Starting${RESET} ${GREEN}${BOLD}Execution - ePlus.DEV${RESET}"
echo

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} Google Cloud project was not detected."
  exit 1
fi

echo "${CYAN}${BOLD}Project ID:${RESET} $PROJECT_ID"
echo

# Required terminal input
read -r -p "Enter REQUEST1: " REQUEST1
read -r -p "Enter RESPONSE1: " RESPONSE1
read -r -p "Enter REQUEST2: " REQUEST2
read -r -p "Enter RESPONSE2: " RESPONSE2

if [[ -z "$REQUEST1" || -z "$RESPONSE1" || -z "$REQUEST2" || -z "$RESPONSE2" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} All request and response file names are required."
  exit 1
fi

export REQUEST1
export RESPONSE1
export REQUEST2
export RESPONSE2

echo
echo "${YELLOW}${BOLD}Enabling required APIs...${RESET}"

gcloud services enable \
  speech.googleapis.com \
  apikeys.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

echo
echo "${YELLOW}${BOLD}Creating API key automatically...${RESET}"

KEY_ID="speech-key-$(date +%s)"
API_KEY=""

KEY_RESOURCE=$(gcloud services api-keys create \
  --project="$PROJECT_ID" \
  --key-id="$KEY_ID" \
  --display-name="Speech API Key - ePlus.DEV" \
  --api-target="service=speech.googleapis.com" \
  --format="value(name)" \
  --quiet 2>/dev/null || true)

if [[ -n "$KEY_RESOURCE" ]]; then
  sleep 5

  API_KEY=$(gcloud services api-keys get-key-string "$KEY_RESOURCE" \
    --project="$PROJECT_ID" \
    --format="value(keyString)" \
    --quiet 2>/dev/null || true)
fi

if [[ -z "$API_KEY" ]]; then
  echo "${YELLOW}${BOLD}API key could not be created automatically.${RESET}"
  read -r -p "Enter API_KEY: " API_KEY
else
  echo "${GREEN}${BOLD}API key created successfully.${RESET}"
fi

if [[ -z "$API_KEY" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} API_KEY is required."
  exit 1
fi

export API_KEY

echo
echo "${CYAN}${BOLD}Environment variables:${RESET}"
echo "export API_KEY=********"
echo "export REQUEST1=$REQUEST1"
echo "export RESPONSE1=$RESPONSE1"
echo "export REQUEST2=$REQUEST2"
echo "export RESPONSE2=$RESPONSE2"

cat > "$REQUEST1" <<EOF_REQUEST1
{
  "config": {
    "encoding": "LINEAR16",
    "languageCode": "en-US",
    "audioChannelCount": 2
  },
  "audio": {
    "uri": "gs://spls/arc131/question_en.wav"
  }
}
EOF_REQUEST1

echo
echo "${YELLOW}${BOLD}Processing the first audio file...${RESET}"

curl -s \
  -X POST \
  -H "Content-Type: application/json" \
  --data-binary "@$REQUEST1" \
  "https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY" \
  > "$RESPONSE1"

cat > "$REQUEST2" <<EOF_REQUEST2
{
  "config": {
    "encoding": "FLAC",
    "languageCode": "es-ES"
  },
  "audio": {
    "uri": "gs://spls/arc131/multi_es.flac"
  }
}
EOF_REQUEST2

echo "${YELLOW}${BOLD}Processing the second audio file...${RESET}"

curl -s \
  -X POST \
  -H "Content-Type: application/json" \
  --data-binary "@$REQUEST2" \
  "https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY" \
  > "$RESPONSE2"

echo
echo "${BLUE}${BOLD}Response 1:${RESET}"
cat "$RESPONSE1"

echo
echo
echo "${BLUE}${BOLD}Response 2:${RESET}"
cat "$RESPONSE2"

echo
echo
echo "${RED}${BOLD}Congratulations${RESET} ${WHITE}${BOLD}for${RESET} ${GREEN}${BOLD}Completing the Lab !!! - ePlus.DEV${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#