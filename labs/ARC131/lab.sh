#!/bin/bash

set -euo pipefail

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

echo
echo "${YELLOW}${BOLD}Starting${RESET} ${GREEN}${BOLD}Execution - ePlus.DEV${RESET}"
echo
echo "${WHITE}${BOLD}Enter the required environment variables:${RESET}"
echo

# API key created manually from:
# APIs & Services > Credentials > Create credentials > API key
read -r -p "${MAGENTA}${BOLD}export API_KEY=${RESET}" API_KEY

read -r -p "${CYAN}${BOLD}export REQUEST1=${RESET}" REQUEST1

read -r -p "${GREEN}${BOLD}export RESPONSE1=${RESET}" RESPONSE1

read -r -p "${BLUE}${BOLD}export REQUEST2=${RESET}" REQUEST2

read -r -p "${YELLOW}${BOLD}export RESPONSE2=${RESET}" RESPONSE2

echo

# Validate required values
if [[ -z "$API_KEY" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} API_KEY is required."
  exit 1
fi

if [[ -z "$REQUEST1" || -z "$RESPONSE1" || -z "$REQUEST2" || -z "$RESPONSE2" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} All request and response file names are required."
  exit 1
fi

# Validate filenames required by the lab grader
if [[ "$REQUEST1" != "request.json" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} REQUEST1 must be: request.json"
  exit 1
fi

if [[ "$RESPONSE1" != "speech_response_en.json" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} RESPONSE1 must be: speech_response_en.json"
  exit 1
fi

if [[ "$REQUEST2" != "request_sp.json" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} REQUEST2 must be: request_sp.json"
  exit 1
fi

if [[ "$RESPONSE2" != "response_speech_sp.json" ]]; then
  echo "${RED}${BOLD}ERROR:${RESET} RESPONSE2 must be: response_speech_sp.json"
  exit 1
fi

# Export variables
export API_KEY
export REQUEST1
export RESPONSE1
export REQUEST2
export RESPONSE2

echo "${GREEN}${BOLD}Environment variables configured successfully.${RESET}"
echo
echo "${MAGENTA}export API_KEY=********${RESET}"
echo "${CYAN}export REQUEST1=$REQUEST1${RESET}"
echo "${GREEN}export RESPONSE1=$RESPONSE1${RESET}"
echo "${BLUE}export REQUEST2=$REQUEST2${RESET}"
echo "${YELLOW}export RESPONSE2=$RESPONSE2${RESET}"

#----------------------------------------------------Task 2-------------------------------------------------#

echo
echo "${CYAN}${BOLD}Task 2: Creating English transcription request...${RESET}"

cat > "$REQUEST1" <<'EOF_REQUEST1'
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

echo "${YELLOW}${BOLD}Calling Cloud Speech-to-Text API...${RESET}"

curl -sS \
  -X POST \
  -H "Content-Type: application/json" \
  --data-binary "@$REQUEST1" \
  "https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY" \
  > "$RESPONSE1"

if grep -q '"error"' "$RESPONSE1"; then
  echo
  echo "${RED}${BOLD}English transcription failed:${RESET}"

  if command -v jq >/dev/null 2>&1; then
    jq . "$RESPONSE1"
  else
    cat "$RESPONSE1"
  fi

  exit 1
fi

echo "${GREEN}${BOLD}English transcription completed successfully.${RESET}"
echo
echo "${WHITE}${BOLD}English response:${RESET}"

if command -v jq >/dev/null 2>&1; then
  jq . "$RESPONSE1"
else
  cat "$RESPONSE1"
fi

#----------------------------------------------------Task 3-------------------------------------------------#

echo
echo "${BLUE}${BOLD}Task 3: Creating Spanish transcription request...${RESET}"

cat > "$REQUEST2" <<'EOF_REQUEST2'
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

echo "${YELLOW}${BOLD}Calling Cloud Speech-to-Text API...${RESET}"

curl -sS \
  -X POST \
  -H "Content-Type: application/json" \
  --data-binary "@$REQUEST2" \
  "https://speech.googleapis.com/v1/speech:recognize?key=$API_KEY" \
  > "$RESPONSE2"

if grep -q '"error"' "$RESPONSE2"; then
  echo
  echo "${RED}${BOLD}Spanish transcription failed:${RESET}"

  if command -v jq >/dev/null 2>&1; then
    jq . "$RESPONSE2"
  else
    cat "$RESPONSE2"
  fi

  exit 1
fi

echo "${GREEN}${BOLD}Spanish transcription completed successfully.${RESET}"
echo
echo "${WHITE}${BOLD}Spanish response:${RESET}"

if command -v jq >/dev/null 2>&1; then
  jq . "$RESPONSE2"
else
  cat "$RESPONSE2"
fi

#----------------------------------------------------Result-------------------------------------------------#

echo
echo "${CYAN}${BOLD}Generated files:${RESET}"
echo "${CYAN}Request 1 : $REQUEST1${RESET}"
echo "${GREEN}Response 1: $RESPONSE1${RESET}"
echo "${BLUE}Request 2 : $REQUEST2${RESET}"
echo "${YELLOW}Response 2: $RESPONSE2${RESET}"

echo
echo "${RED}${BOLD}Congratulations${RESET} ${WHITE}${BOLD}for${RESET} ${GREEN}${BOLD}Completing the Lab !!! - ePlus.DEV${RESET}"

#-----------------------------------------------------end---------------------------------------------------#