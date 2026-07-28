#!/bin/bash

# Colors
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
CYAN=$'\033[0;96m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

echo "${CYAN}${BOLD}============================================${RESET}"
echo "${CYAN}${BOLD}      CLOUD VISION LAB - ePlus.DEV${RESET}"
echo "${CYAN}${BOLD}============================================${RESET}"

# Get project, bucket and image automatically
export PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

BUCKET="$(
  gcloud storage buckets list \
    --project="$PROJECT_ID" \
    --format="value(name)" |
    head -n 1
)"

IMAGE_URI="$(
  gsutil ls -r "gs://${BUCKET}/**" 2>/dev/null |
    grep -Ei '\.(jpg|jpeg|png)$' |
    head -n 1
)"

if [[ -z "$BUCKET" || -z "$IMAGE_URI" ]]; then
  echo "${RED}${BOLD}Failed to detect bucket or image.${RESET}"
  exit 1
fi

echo "${YELLOW}Project: $PROJECT_ID${RESET}"
echo "${YELLOW}Bucket : gs://$BUCKET${RESET}"
echo "${YELLOW}Image  : $IMAGE_URI${RESET}"

# Enable required APIs
echo "${CYAN}${BOLD}Enabling APIs...${RESET}"

gcloud services enable \
  vision.googleapis.com \
  apikeys.googleapis.com \
  --quiet

# Create API key
echo "${CYAN}${BOLD}Creating API key...${RESET}"

KEY_NAME="$(
  gcloud services api-keys list \
    --filter="displayName=vision-lab-key" \
    --format="value(name)" |
    head -n 1
)"

if [[ -z "$KEY_NAME" ]]; then
  gcloud services api-keys create \
    --display-name="vision-lab-key" \
    --api-target="service=vision.googleapis.com" \
    --quiet

  KEY_NAME="$(
    gcloud services api-keys list \
      --filter="displayName=vision-lab-key" \
      --format="value(name)" |
      head -n 1
  )"
fi

export API_KEY="$(
  gcloud services api-keys get-key-string "$KEY_NAME" \
    --format="value(keyString)"
)"

echo "export API_KEY='$API_KEY'" > "$HOME/vision-api-key.sh"

echo "${GREEN}${BOLD}API key created.${RESET}"

# Make image public
echo "${CYAN}${BOLD}Making image public...${RESET}"

gsutil acl ch -u AllUsers:R "$IMAGE_URI"

# TEXT_DETECTION
echo "${CYAN}${BOLD}Running TEXT_DETECTION...${RESET}"

cat > request.json <<JSON
{
  "requests": [
    {
      "image": {
        "source": {
          "gcsImageUri": "$IMAGE_URI"
        }
      },
      "features": [
        {
          "type": "TEXT_DETECTION",
          "maxResults": 10
        }
      ]
    }
  ]
}
JSON

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @request.json \
  "https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}" \
  -o text-response.json

gsutil cp text-response.json "gs://${BUCKET}/"

echo "${GREEN}${BOLD}TEXT_DETECTION completed.${RESET}"

# LANDMARK_DETECTION
echo "${CYAN}${BOLD}Running LANDMARK_DETECTION...${RESET}"

cat > request.json <<JSON
{
  "requests": [
    {
      "image": {
        "source": {
          "gcsImageUri": "$IMAGE_URI"
        }
      },
      "features": [
        {
          "type": "LANDMARK_DETECTION",
          "maxResults": 10
        }
      ]
    }
  ]
}
JSON

curl -s -X POST \
  -H "Content-Type: application/json" \
  --data-binary @request.json \
  "https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}" \
  -o landmark-response.json

gsutil cp landmark-response.json "gs://${BUCKET}/"

echo "${GREEN}${BOLD}LANDMARK_DETECTION completed.${RESET}"

echo
echo "${GREEN}${BOLD}============================================${RESET}"
echo "${GREEN}${BOLD}          LAB COMPLETED SUCCESSFULLY${RESET}"
echo "${GREEN}${BOLD}============================================${RESET}"
echo
echo "Text response: gs://${BUCKET}/text-response.json"
echo "Landmark response: gs://${BUCKET}/landmark-response.json"