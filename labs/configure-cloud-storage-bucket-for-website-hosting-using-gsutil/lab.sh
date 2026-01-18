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

# Require BUCKET input if empty
if [[ -z "${BUCKET}" ]]; then
  echo "${RED_TEXT}${BOLD_TEXT}⚠️  BUCKET is not set!${RESET_FORMAT}"
  read -p "${ORANGE_TEXT}${BOLD_TEXT}Enter BUCKET name (example: qwiklabs-gcp-xx-xxxx-bucket): ${RESET_FORMAT}" BUCKET
fi

# Validate BUCKET again
if [[ -z "${BUCKET}" ]]; then
  echo "${RED_TEXT}${BOLD_TEXT}❌ BUCKET cannot be empty. Exiting.${RESET_FORMAT}"
  exit 1
fi

echo "${GREEN_TEXT}${BOLD_TEXT}✅ Using BUCKET:${RESET_FORMAT} ${WHITE_TEXT}gs://${BUCKET}${RESET_FORMAT}"

echo "${BLUE_TEXT}${BOLD_TEXT}🔧 Setting website config...${RESET_FORMAT}"
gsutil web set -m index.html -e error.html "gs://${BUCKET}"

echo "${BLUE_TEXT}${BOLD_TEXT}🔧 Disable uniform bucket-level access...${RESET_FORMAT}"
gsutil uniformbucketlevelaccess set off "gs://${BUCKET}"

echo "${BLUE_TEXT}${BOLD_TEXT}🔧 Set default ACL public-read...${RESET_FORMAT}"
gsutil defacl set public-read "gs://${BUCKET}"

echo "${BLUE_TEXT}${BOLD_TEXT}🌍 Making files public...${RESET_FORMAT}"
gsutil acl set -a public-read "gs://${BUCKET}/index.html"
gsutil acl set -a public-read "gs://${BUCKET}/error.html"
gsutil acl set -a public-read "gs://${BUCKET}/style.css"
gsutil acl set -a public-read "gs://${BUCKET}/logo.jpg"

echo "${GREEN_TEXT}${BOLD_TEXT}🎉 DONE! Your static website is public now.${RESET_FORMAT}"
echo "${YELLOW_TEXT}© ePlus.DEV${RESET_FORMAT}"