#!/bin/bash

# ==========================================================
# ePlus.DEV - Google Cloud Lab Script
# Copyright (c) ePlus.DEV
# All rights reserved.
# ==========================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}==========================================${RESET}"
echo -e "${YELLOW}   ePlus.DEV - Speech-to-Text API Script   ${RESET}"
echo -e "${CYAN}==========================================${RESET}"

# Check API_KEY
if [ -z "$API_KEY" ]; then
  echo -e "${YELLOW}⚠ API_KEY not found.${RESET}"
  read -p "$(echo -e "${CYAN}Enter API_KEY: ${RESET}")" API_KEY
  export API_KEY
  echo -e "${GREEN}✅ API_KEY saved for this session.${RESET}"
else
  echo -e "${GREEN}✅ API_KEY detected.${RESET}"
fi

echo -e "${CYAN}📌 Creating request.json...${RESET}"
cat > request.json <<'JSON'
{
  "config": {
      "encoding":"FLAC",
      "languageCode": "en-US"
  },
  "audio": {
      "uri":"gs://cloud-samples-data/speech/brooklyn_bridge.flac"
  }
}
JSON
echo -e "${GREEN}✅ request.json created.${RESET}"

echo -e "${CYAN}🚀 Calling Speech-to-Text API...${RESET}"
curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
"https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" > result.json

echo -e "${GREEN}✅ Done! Output saved to result.json${RESET}"
echo -e "${YELLOW}📄 API Response:${RESET}"
cat result.json