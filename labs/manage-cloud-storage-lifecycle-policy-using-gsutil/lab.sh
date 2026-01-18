#!/bin/bash
set -euo pipefail

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
echo "${CYAN_TEXT}${BOLD_TEXT}Manage Cloud Storage Lifecycle Policy using gsutil${RESET_FORMAT}"
echo "${YELLOW_TEXT}© Copyright ePlus.DEV${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_FORMAT}"

# Prefer Qwiklabs env var, fallback to gcloud config
PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"

if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null | tr -d '\r' | xargs || true)"
  if [[ "${PROJECT_ID}" == "unset" ]]; then
    PROJECT_ID=""
  fi
fi

# Require PROJECT_ID input if empty
if [[ -z "${PROJECT_ID}" ]]; then
  echo "${RED_TEXT}${BOLD_TEXT}⚠️ PROJECT_ID is not set!${RESET_FORMAT}"
  printf "%b" "${ORANGE_TEXT}${BOLD_TEXT}Enter PROJECT_ID [example: qwiklabs-gcp-xx-xxxx]: ${RESET_FORMAT}"
  read -r PROJECT_ID
fi

# Validate PROJECT_ID again
if [[ -z "${PROJECT_ID}" ]]; then
  echo "${RED_TEXT}${BOLD_TEXT}❌ PROJECT_ID cannot be empty. Exiting.${RESET_FORMAT}"
  return 1 2>/dev/null || exit 1
fi

BUCKET_NAME="${PROJECT_ID}-bucket"
BUCKET="gs://${BUCKET_NAME}"

echo "${GREEN_TEXT}${BOLD_TEXT}✅ Using PROJECT_ID:${RESET_FORMAT} ${WHITE_TEXT}${PROJECT_ID}${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Target bucket:${RESET_FORMAT} ${WHITE_TEXT}${BUCKET}${RESET_FORMAT}"

echo "${BLUE_TEXT}${BOLD_TEXT}🔧 Creating lifecycle.json${RESET_FORMAT}"

cat > lifecycle.json <<'JSON'
{
  "rule": [
    {
      "action": { "type": "SetStorageClass", "storageClass": "NEARLINE" },
      "condition": { "age": 30, "matchesPrefix": ["projects/active/"] }
    },
    {
      "action": { "type": "SetStorageClass", "storageClass": "NEARLINE" },
      "condition": { "age": 90, "matchesPrefix": ["archive/"] }
    },
    {
      "action": { "type": "SetStorageClass", "storageClass": "COLDLINE" },
      "condition": { "age": 180, "matchesPrefix": ["archive/"] }
    },
    {
      "action": { "type": "Delete" },
      "condition": { "age": 7, "matchesPrefix": ["processing/temp_logs/"] }
    }
  ]
}
JSON

echo "${BLUE_TEXT}${BOLD_TEXT}📌 Applying lifecycle policy...${RESET_FORMAT}"
gsutil lifecycle set lifecycle.json "${BUCKET}"

echo "${GREEN_TEXT}${BOLD_TEXT}✅ Done.${RESET_FORMAT}"
echo "${YELLOW_TEXT}© ePlus.DEV${RESET_FORMAT}"