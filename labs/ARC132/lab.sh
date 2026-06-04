#!/bin/bash
set -e

# ================= COLOR CONFIG =================
BLACK=$(tput setaf 0 || true)
RED=$(tput setaf 1 || true)
GREEN=$(tput setaf 2 || true)
YELLOW=$(tput setaf 3 || true)
BLUE=$(tput setaf 4 || true)
MAGENTA=$(tput setaf 5 || true)
CYAN=$(tput setaf 6 || true)
WHITE=$(tput setaf 7 || true)

BG_BLACK=$(tput setab 0 || true)
BG_RED=$(tput setab 1 || true)
BG_GREEN=$(tput setab 2 || true)
BG_YELLOW=$(tput setab 3 || true)
BG_BLUE=$(tput setab 4 || true)
BG_MAGENTA=$(tput setab 5 || true)
BG_CYAN=$(tput setab 6 || true)
BG_WHITE=$(tput setab 7 || true)

BOLD=$(tput bold || true)
RESET=$(tput sgr0 || true)
# =================================================

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV${RESET}"

# ================= TASK CONFIG =================
echo "${CYAN}${BOLD}Please enter the required lab values below.${RESET}"

read -rp "Task 2 output file name: " task_2_file_name
read -rp "Task 3 request file name: " task_3_request_file
read -rp "Task 3 response file name: " task_3_response_file
read -rp "Task 4 Japanese sentence to translate into English: " task_4_sentence
read -rp "Task 4 output file name: " task_4_file
read -rp "Task 5 sentence for language detection: " task_5_sentence
read -rp "Task 5 output file name: " task_5_file

if [ -z "$task_2_file_name" ] || \
   [ -z "$task_3_request_file" ] || \
   [ -z "$task_3_response_file" ] || \
   [ -z "$task_4_sentence" ] || \
   [ -z "$task_4_file" ] || \
   [ -z "$task_5_sentence" ] || \
   [ -z "$task_5_file" ]; then
  echo "${RED}${BOLD}ERROR: All fields are required.${RESET}"
  exit 1
fi

export task_2_file_name
export task_3_request_file
export task_3_response_file
export task_4_sentence
export task_4_file
export task_5_sentence
export task_5_file
# ===============================================

export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
export DEVSHELL_PROJECT_ID="$PROJECT_ID"

if [ -z "$PROJECT_ID" ]; then
  echo "${RED}${BOLD}ERROR: Cannot detect PROJECT_ID.${RESET}"
  exit 1
fi

echo "${CYAN}Project ID: ${PROJECT_ID}${RESET}"

echo "${YELLOW}${BOLD}[1/5] Enabling required APIs...${RESET}"
gcloud services enable \
  speech.googleapis.com \
  texttospeech.googleapis.com \
  translate.googleapis.com \
  apikeys.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

echo "${YELLOW}${BOLD}[2/5] Creating or getting API key automatically...${RESET}"

KEY_DISPLAY_NAME="eplus-lab-api-key"

EXISTING_KEY_NAME=$(gcloud services api-keys list \
  --project="$PROJECT_ID" \
  --filter="displayName=${KEY_DISPLAY_NAME}" \
  --format="value(name)" \
  --limit=1 2>/dev/null || true)

if [ -n "$EXISTING_KEY_NAME" ]; then
  API_KEY=$(gcloud services api-keys get-key-string "$EXISTING_KEY_NAME" \
    --project="$PROJECT_ID" \
    --format="value(keyString)")
else
  API_KEY=$(gcloud services api-keys create \
    --project="$PROJECT_ID" \
    --display-name="$KEY_DISPLAY_NAME" \
    --format="value(keyString)" 2>/dev/null || true)

  if [ -z "$API_KEY" ]; then
    sleep 8
    NEW_KEY_NAME=$(gcloud services api-keys list \
      --project="$PROJECT_ID" \
      --filter="displayName=${KEY_DISPLAY_NAME}" \
      --format="value(name)" \
      --limit=1)

    API_KEY=$(gcloud services api-keys get-key-string "$NEW_KEY_NAME" \
      --project="$PROJECT_ID" \
      --format="value(keyString)")
  fi
fi

if [ -z "$API_KEY" ]; then
  echo "${RED}${BOLD}ERROR: Cannot create or get API key.${RESET}"
  exit 1
fi

export API_KEY
echo "${GREEN}API key is ready.${RESET}"

echo "${YELLOW}${BOLD}[3/5] Getting zone of lab-vm...${RESET}"

ZONE=$(gcloud compute instances list \
  --project="$PROJECT_ID" \
  --filter="name=lab-vm" \
  --format="value(zone)" \
  --limit=1)

if [ -z "$ZONE" ]; then
  echo "${RED}${BOLD}ERROR: lab-vm not found.${RESET}"
  exit 1
fi

export ZONE
echo "${GREEN}lab-vm zone: ${ZONE}${RESET}"

echo "${YELLOW}${BOLD}[4/5] Connecting to lab-vm and running lab tasks...${RESET}"

gcloud compute ssh lab-vm \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  --command="API_KEY='$API_KEY' \
PROJECT_ID='$PROJECT_ID' \
task_2_file_name='$task_2_file_name' \
task_3_request_file='$task_3_request_file' \
task_3_response_file='$task_3_response_file' \
task_4_sentence='$task_4_sentence' \
task_4_file='$task_4_file' \
task_5_sentence='$task_5_sentence' \
task_5_file='$task_5_file' \
bash -s" <<'REMOTE_SCRIPT'

set -e

echo "Running inside lab-vm..."

audio_uri="gs://cloud-samples-data/speech/corbeau_renard.flac"

if [ -f "venv/bin/activate" ]; then
  source venv/bin/activate
fi

echo "[Task 2] Creating Text-to-Speech request file..."

cat > synthesize-text.json <<EOF
{
  "input": {
    "text": "Cloud Text-to-Speech API allows developers to include natural-sounding, synthetic human speech as playable audio in their applications. The Text-to-Speech API converts text or Speech Synthesis Markup Language input into audio data like MP3 or LINEAR16."
  },
  "voice": {
    "languageCode": "en-gb",
    "name": "en-GB-Standard-A",
    "ssmlGender": "FEMALE"
  },
  "audioConfig": {
    "audioEncoding": "MP3"
  }
}
EOF

echo "[Task 2] Calling Text-to-Speech API..."

curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @synthesize-text.json \
  "https://texttospeech.googleapis.com/v1/text:synthesize" \
  -o "$task_2_file_name"

echo "[Task 3] Creating Speech-to-Text request file..."

cat > "$task_3_request_file" <<EOF
{
  "config": {
    "encoding": "FLAC",
    "sampleRateHertz": 44100,
    "languageCode": "fr-FR"
  },
  "audio": {
    "uri": "$audio_uri"
  }
}
EOF

echo "[Task 3] Calling Speech-to-Text API for French..."

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @"$task_3_request_file" \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" \
  -o "$task_3_response_file"

echo "[Task 4] Calling Translation API: Japanese to English..."

curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "{\"q\": \"$task_4_sentence\"}" \
  "https://translation.googleapis.com/language/translate/v2?key=${API_KEY}&source=ja&target=en" \
  -o "$task_4_file"

echo "[Task 5] Calling Translation Detect API..."

curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "{\"q\": [\"$task_5_sentence\"]}" \
  "https://translation.googleapis.com/language/translate/v2/detect?key=${API_KEY}" \
  -o "$task_5_file"

echo ""
echo "Generated files:"
ls -lh \
  "$task_2_file_name" \
  "$task_3_request_file" \
  "$task_3_response_file" \
  "$task_4_file" \
  "$task_5_file"

echo ""
echo "Preview response files:"
echo "----- $task_3_response_file -----"
cat "$task_3_response_file" || true
echo ""
echo "----- $task_4_file -----"
cat "$task_4_file" || true
echo ""
echo "----- $task_5_file -----"
cat "$task_5_file" || true
echo ""

REMOTE_SCRIPT

echo "${YELLOW}${BOLD}[5/5] Lab tasks completed.${RESET}"
echo "${BG_RED}${BOLD}Congratulations For Completing The Lab !!! - ePlus.DEV${RESET}"