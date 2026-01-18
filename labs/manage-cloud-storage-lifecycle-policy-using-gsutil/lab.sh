#!/bin/bash

# =======================
#  ePlus.DEV - Qwiklabs
# =======================

# Define color variables
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
ORANGE_TEXT=$'\033[38;5;214m'

echo "${MAGENTA_TEXT}${BOLD_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}Configure Cloud Storage Bucket for Website Hosting using gsutil${RESET_FORMAT}"
echo "${YELLOW_TEXT}© Copyright ePlus.DEV${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_FORMAT}"

PROJECT_ID=$(gcloud config get-value project)

# Require PROJECT_ID input if empty
if [[ -z "${PROJECT_ID}" ]]; then
  echo "${RED_TEXT}${BOLD_TEXT}⚠️ PROJECT_ID is not set!${RESET_FORMAT}"
  read -p "${ORANGE_TEXT}${BOLD_TEXT}Enter PROJECT_ID (example: qwiklabs-gcp-xx-xxxx): ${RESET_FORMAT}" PROJECT_ID
fi

# Validate PROJECT_ID again
if [[ -z "${PROJECT_ID}" ]]; then
  echo "${RED_TEXT}${BOLD_TEXT}❌ PROJECT_ID cannot be empty. Exiting.${RESET_FORMAT}"
  exit 1
fi

echo "${GREEN_TEXT}${BOLD_TEXT}✅ Using PROJECT_ID:${RESET_FORMAT} ${WHITE_TEXT}${PROJECT_ID}${RESET_FORMAT}"

echo "${BLUE_TEXT}${BOLD_TEXT}🔧 Creating file lifecycle.json${RESET_FORMAT}"

cat <<EOF > lifecycle.json
{
  "rule": [
    {
      "action": {
        "type": "SetStorageClass",
        "storageClass": "NEARLINE"
      },
      "condition": {
        "daysSinceNoncurrentTime": 30,
        "matchesPrefix": ["projects/active/"]
      }
    },
    {
      "action": {
        "type": "SetStorageClass",
        "storageClass": "NEARLINE"
      },
      "condition": {
        "daysSinceNoncurrentTime": 90,
        "matchesPrefix": ["archive/"]
      }
    },
    {
      "action": {
        "type": "SetStorageClass",
        "storageClass": "COLDLINE"
      },
      "condition": {
        "daysSinceNoncurrentTime": 180,
        "matchesPrefix": ["archive/"]
      }
    },
    {
      "action": {
        "type": "Delete"
      },
      "condition": {
        "age": 7,
        "matchesPrefix": ["processing/temp_logs/"]
      }
    }
  ]
}
EOF


gsutil lifecycle set lifecycle.json gs://$PROJECT_ID-bucket

echo "${YELLOW_TEXT}© ePlus.DEV${RESET_FORMAT}"