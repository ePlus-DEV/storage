#!/bin/bash
# =======================================================
#  Google Cloud Speech-to-Text API Demo (with API Key)
#  Author: ePlus.DEV
#  License: For educational/lab use only.
#  Copyright (c) 2025 ePlus.DEV. All rights reserved.
# =======================================================

set -e

# --- Vars ---
PROJECT_ID=$(gcloud config get-value project -q)
KEY_NAME="speech-api-key"

echo -e "\033[1;36m[INFO] Project: $PROJECT_ID\033[0m"

# --- Enable APIs ---
echo -e "\033[1;33m[STEP] Enabling required APIs...\033[0m"
gcloud services enable speech.googleapis.com apikeys.googleapis.com

# --- Create API Key (returns keyString directly) ---
echo -e "\033[1;33m[STEP] Creating API Key: $KEY_NAME ...\033[0m"
API_KEY=$(gcloud alpha services api-keys create \
  --display-name="$KEY_NAME" \
  --format="value(keyString)")

export API_KEY=$API_KEY
echo -e "\033[1;32m[SUCCESS] API_KEY created and exported.\033[0m"
echo -e "\033[1;36m[INFO] API_KEY: $API_KEY\033[0m"

# --- Create request.json ---
echo -e "\033[1;33m[STEP] Creating request.json ...\033[0m"
cat > request.json <<'EOF'
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

# --- Call Speech-to-Text API