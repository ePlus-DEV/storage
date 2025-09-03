#!/bin/bash
# =======================================================
#  Google Cloud Speech-to-Text API Demo
#  Author: ePlus.DEV
#  License: For educational/lab use only.
#  Copyright (c) 2025 ePlus.DEV. All rights reserved.
# =======================================================

set -e

# --- Variables ---
PROJECT_ID=$(gcloud config get-value project -q)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
KEY_NAME="speech-api-key"

echo -e "\033[1;36m[INFO] Project: $PROJECT_ID ($PROJECT_NUMBER)\033[0m"

# --- Enable required API ---
echo -e "\033[1;33m[STEP] Enabling Speech-to-Text API...\033[0m"
gcloud services enable speech.googleapis.com apikeys.googleapis.com

# --- Create API Key ---
echo -e "\033[1;33m[STEP] Creating API Key: $KEY_NAME ...\033[0m"
API_KEY_RESOURCE=$(gcloud alpha services api-keys create \
  --display-name="$KEY_NAME" \
  --format="value(name)")

# --- Extract key string ---
API_KEY=$(gcloud alpha services api-keys get-key-string "$API_KEY_RESOURCE" \
  --format="value(keyString)")
export API_KEY=$API_KEY
echo -e "\033[1;32m[SUCCESS] API_KEY created and exported.\033[0m"

# --- Create request.json ---
echo -e "\033[1;33m[STEP] Creating request.json ...\033[0m"
cat > request.json <<'EOF_END'
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

# --- Call Speech-to-Text API ---
echo -e "\033[1;33m[STEP] Sending request to Speech-to-Text API...\033[0m"
curl -s -X POST -H "Content-Type: application/json" \
  --data-binary @request.json \
  "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" > result.json

echo -e "\033[1;32m[SUCCESS] Response saved to result.json\033[0m"

# --- Show transcript ---
echo -e "\033[1;36m[INFO] Transcript result:\033[0m"
cat result.json | jq '.results[].alternatives[] | {transcript, confidence}'