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

banner() {
  echo ""
  echo "${BG_MAGENTA}${WHITE}${BOLD}============================================================${RESET}"
  echo "${BG_MAGENTA}${WHITE}${BOLD}              Google Cloud Speech API Lab                  ${RESET}"
  echo "${BG_MAGENTA}${WHITE}${BOLD}                    © ePlus.DEV                             ${RESET}"
  echo "${BG_MAGENTA}${WHITE}${BOLD}============================================================${RESET}"
  echo ""
}

step() {
  echo ""
  echo "${BG_BLUE}${WHITE}${BOLD} $1 ${RESET}"
}

success() {
  echo "${GREEN}${BOLD}✔ $1${RESET}"
}

info() {
  echo "${CYAN}${BOLD}ℹ $1${RESET}"
}

warn() {
  echo "${YELLOW}${BOLD}➜ $1${RESET}"
}

error() {
  echo "${RED}${BOLD}✘ $1${RESET}"
}

ask_required() {
  local prompt="$1"
  local var_name="$2"
  local value=""

  while true; do
    read -rp "$prompt" value
    if [ -n "$value" ]; then
      printf -v "$var_name" '%s' "$value"
      break
    fi
    echo "${RED}${BOLD}This field is required. Please enter a value.${RESET}"
  done
}

banner

# ================= REQUIRED INPUT =================
step "Required lab values"

echo "${YELLOW}${BOLD}Enter the exact values required by your lab.${RESET}"
echo ""

ask_required "Task 2 output file name: " task_2_file_name
ask_required "Task 3 request file name: " task_3_request_file
ask_required "Task 3 response file name: " task_3_response_file
ask_required "Task 4 Japanese sentence to translate into English: " task_4_sentence
ask_required "Task 4 output file name: " task_4_file
ask_required "Task 5 sentence for language detection: " task_5_sentence
ask_required "Task 5 output file name: " task_5_file

export task_2_file_name
export task_3_request_file
export task_3_response_file
export task_4_sentence
export task_4_file
export task_5_sentence
export task_5_file

success "All required values have been entered."
# ==================================================

# ================= PROJECT CONFIG =================
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
  error "Cannot detect PROJECT_ID."
  exit 1
fi

export PROJECT_ID
export DEVSHELL_PROJECT_ID="$PROJECT_ID"

info "Project ID: ${PROJECT_ID}"
# ==================================================

step "[1/5] Enabling required APIs"

gcloud services enable \
  speech.googleapis.com \
  texttospeech.googleapis.com \
  translate.googleapis.com \
  apikeys.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

success "Required APIs are enabled."

# ================= CREATE API KEY =================
step "[2/5] Creating restricted API key automatically"

KEY_DISPLAY_NAME="API key 3"

warn "Creating new API key with Cloud Speech-to-Text API restriction..."

gcloud services enable apikeys.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

gcloud alpha services api-keys create \
  --project="$PROJECT_ID" \
  --display-name="$KEY_DISPLAY_NAME" \
  --api-target=service=speech.googleapis.com \
  --quiet

warn "Waiting for API key to become available..."
sleep 15

KEY_NAME=$(gcloud alpha services api-keys list \
  --project="$PROJECT_ID" \
  --filter="displayName='${KEY_DISPLAY_NAME}'" \
  --format="value(name)" \
  --limit=1 2>/dev/null || true)

if [ -z "$KEY_NAME" ]; then
  error "Cannot find created API key."
  exit 1
fi

API_KEY=$(gcloud alpha services api-keys get-key-string "$KEY_NAME" \
  --project="$PROJECT_ID" \
  --format="value(keyString)" 2>/dev/null || true)

if [ -z "$API_KEY" ]; then
  warn "Failed to get key string by resource name. Trying to parse from key list..."

  API_KEY=$(gcloud alpha services api-keys list \
    --project="$PROJECT_ID" \
    --filter="displayName='${KEY_DISPLAY_NAME}'" \
    --format="value(keyString)" \
    --limit=1 2>/dev/null || true)
fi

if [ -z "$API_KEY" ]; then
  error "Cannot create or get API key string."
  echo "${YELLOW}${BOLD}Please check APIs & Services > Credentials manually.${RESET}"
  exit 1
fi

export API_KEY
echo "$API_KEY" > api_key.txt

info "API key resource: ${KEY_NAME}"
success "API key is ready and restricted to Cloud Speech-to-Text API."
success "API key saved to api_key.txt."
# ==================================================

# ================= GET VM ZONE =================
step "[3/5] Getting lab-vm zone"

ZONE=$(gcloud compute instances list \
  --project="$PROJECT_ID" \
  --filter="name=lab-vm" \
  --format="value(zone)" \
  --limit=1)

if [ -z "$ZONE" ]; then
  error "lab-vm not found."
  exit 1
fi

export ZONE
success "lab-vm zone: ${ZONE}"
# ===============================================

# ================= RUN TASKS ON VM =================
step "[4/5] Running tasks 2 to 5 on lab-vm"

gcloud compute ssh lab-vm \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  --command="API_KEY='$API_KEY' \
task_2_file_name='$task_2_file_name' \
task_3_request_file='$task_3_request_file' \
task_3_response_file='$task_3_response_file' \
task_4_sentence='$task_4_sentence' \
task_4_file='$task_4_file' \
task_5_sentence='$task_5_sentence' \
task_5_file='$task_5_file' \
bash -s" <<'REMOTE_SCRIPT'

set -e

# ================= COLOR CONFIG INSIDE VM =================
BLACK=$(tput setaf 0 || true)
RED=$(tput setaf 1 || true)
GREEN=$(tput setaf 2 || true)
YELLOW=$(tput setaf 3 || true)
BLUE=$(tput setaf 4 || true)
CYAN=$(tput setaf 6 || true)
WHITE=$(tput setaf 7 || true)

BG_BLUE=$(tput setab 4 || true)
BG_GREEN=$(tput setab 2 || true)
BG_MAGENTA=$(tput setab 5 || true)
BG_RED=$(tput setab 1 || true)

BOLD=$(tput bold || true)
RESET=$(tput sgr0 || true)

vm_step() {
  echo ""
  echo "${BG_BLUE}${WHITE}${BOLD} $1 ${RESET}"
}

vm_success() {
  echo "${GREEN}${BOLD}✔ $1${RESET}"
}

vm_info() {
  echo "${CYAN}${BOLD}ℹ $1${RESET}"
}

vm_warn() {
  echo "${YELLOW}${BOLD}➜ $1${RESET}"
}

get_access_token() {
  gcloud auth application-default print-access-token 2>/dev/null || gcloud auth print-access-token
}

echo ""
echo "${BG_MAGENTA}${WHITE}${BOLD} Running inside lab-vm - © ePlus.DEV ${RESET}"

if [ -f "venv/bin/activate" ]; then
  source venv/bin/activate
  vm_success "Python virtual environment activated."
else
  vm_warn "venv/bin/activate not found. Continuing without activating venv."
fi

# ================= TASK 2 =================
vm_step "Task 2: Create synthetic speech from text"

vm_info "Creating synthesize-text.json..."

cat > synthesize-text.json <<'EOF'
{
  "input": {
    "text": "Cloud Text-to-Speech API allows developers to include natural-sounding, synthetic human speech as playable audio in their applications. The Text-to-Speech API converts text or Speech Synthesis Markup Language (SSML) input into audio data like MP3 or LINEAR16 (the encoding used in WAV files)."
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

vm_info "Calling Text-to-Speech API..."

ACCESS_TOKEN=$(get_access_token)

curl -s -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @synthesize-text.json \
  "https://texttospeech.googleapis.com/v1/text:synthesize" \
  -o "$task_2_file_name"

vm_info "Creating tts_decode.py..."

cat > tts_decode.py <<'EOF'
import argparse
from base64 import decodebytes
import json

def decode_tts_output(input_file, output_file):
    with open(input_file) as input:
        response = json.load(input)
        audio_data = response['audioContent']
        with open(output_file, "wb") as new_file:
            new_file.write(decodebytes(audio_data.encode('utf-8')))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    decode_tts_output(args.input, args.output)
EOF

vm_info "Decoding MP3 audio file..."

python tts_decode.py \
  --input "$task_2_file_name" \
  --output synthesize-text-audio.mp3

vm_success "Task 2 completed."

# ================= TASK 3 =================
vm_step "Task 3: Speech-to-Text transcription in French"

vm_info "Creating ${task_3_request_file}..."

cat > "$task_3_request_file" <<'EOF'
{
  "config": {
    "encoding": "FLAC",
    "sampleRateHertz": 44100,
    "languageCode": "fr-FR"
  },
  "audio": {
    "uri": "gs://cloud-samples-data/speech/corbeau_renard.flac"
  }
}
EOF

vm_info "Calling Cloud Speech-to-Text API with restricted API key..."

curl -s -X POST \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-binary @"$task_3_request_file" \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" \
  -o "$task_3_response_file"

vm_success "Task 3 completed."

# ================= TASK 4 =================
vm_step "Task 4: Translate Japanese to English"

vm_info "Translating: ${task_4_sentence}"

ACCESS_TOKEN=$(get_access_token)

curl -s -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-urlencode "q=${task_4_sentence}" \
  --data "source=ja" \
  --data "target=en" \
  --data "format=text" \
  "https://translation.googleapis.com/language/translate/v2" \
  -o "$task_4_file"

vm_success "Task 4 completed."

# ================= TASK 5 =================
vm_step "Task 5: Detect language"

vm_info "Detecting language for: ${task_5_sentence}"

ACCESS_TOKEN=$(get_access_token)

curl -s -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-urlencode "q=${task_5_sentence}" \
  "https://translation.googleapis.com/language/translate/v2/detect" \
  -o "$task_5_file"

vm_success "Task 5 completed."

echo ""
echo "${BG_GREEN}${BLACK}${BOLD} Generated files ${RESET}"

ls -lh \
  synthesize-text.json \
  "$task_2_file_name" \
  tts_decode.py \
  synthesize-text-audio.mp3 \
  "$task_3_request_file" \
  "$task_3_response_file" \
  "$task_4_file" \
  "$task_5_file"

echo ""
echo "${BG_BLUE}${WHITE}${BOLD} Preview: ${task_3_response_file} ${RESET}"
cat "$task_3_response_file" || true

echo ""
echo "${BG_BLUE}${WHITE}${BOLD} Preview: ${task_4_file} ${RESET}"
cat "$task_4_file" || true

echo ""
echo "${BG_BLUE}${WHITE}${BOLD} Preview: ${task_5_file} ${RESET}"
cat "$task_5_file" || true

echo ""
echo "${BG_GREEN}${BLACK}${BOLD} All VM tasks completed successfully - © ePlus.DEV ${RESET}"

REMOTE_SCRIPT

step "[5/5] Lab completed"
success "All tasks completed successfully."

echo ""
echo "${BG_RED}${WHITE}${BOLD} Congratulations For Completing The Lab !!! - ePlus.DEV ${RESET}"