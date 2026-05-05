#!/bin/bash
set -e

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
TEAL_TEXT=$'\033[38;5;50m'
PURPLE_TEXT=$'\033[0;35m'
GOLD_TEXT=$'\033[0;33m'
LIME_TEXT=$'\033[0;92m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'
NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'

clear

echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}          INITIATING KMS LAB EXECUTION...${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
echo

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
export DEVSHELL_PROJECT_ID="$PROJECT_ID"
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"

KEYRING_NAME="labkey"
CRYPTOKEY_NAME="qwiklab"
BUCKET_NAME="${PROJECT_ID}_kms_lab"

echo "${YELLOW_TEXT}${BOLD_TEXT}[1/8] Project ID: ${PROJECT_ID}${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}[1/8] Bucket Name: ${BUCKET_NAME}${RESET_FORMAT}"
echo

echo "${CYAN_TEXT}${BOLD_TEXT}[2/8] Enable Cloud KMS API${RESET_FORMAT}"
gcloud services enable cloudkms.googleapis.com

echo "${CYAN_TEXT}${BOLD_TEXT}[3/8] Create Cloud Storage bucket${RESET_FORMAT}"
if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}Bucket already exists: gs://${BUCKET_NAME}${RESET_FORMAT}"
else
  gsutil mb "gs://${BUCKET_NAME}"
fi

echo "${CYAN_TEXT}${BOLD_TEXT}[4/8] Download sample financial document${RESET_FORMAT}"
gsutil cp "gs://${GOOGLE_CLOUD_PROJECT}-kms-lab-data/finance-dept/inbox/1.txt" .

echo "${GREEN_TEXT}${BOLD_TEXT}Sample file content:${RESET_FORMAT}"
tail 1.txt
echo

echo "${CYAN_TEXT}${BOLD_TEXT}[5/8] Create KMS keyring and cryptokey${RESET_FORMAT}"
if gcloud kms keyrings describe "$KEYRING_NAME" --location global >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}Keyring already exists: ${KEYRING_NAME}${RESET_FORMAT}"
else
  gcloud kms keyrings create "$KEYRING_NAME" --location global
fi

if gcloud kms keys describe "$CRYPTOKEY_NAME" \
  --location global \
  --keyring "$KEYRING_NAME" >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}CryptoKey already exists: ${CRYPTOKEY_NAME}${RESET_FORMAT}"
else
  gcloud kms keys create "$CRYPTOKEY_NAME" \
    --location global \
    --keyring "$KEYRING_NAME" \
    --purpose encryption
fi

echo "${CYAN_TEXT}${BOLD_TEXT}[6/8] Encrypt single file: 1.txt${RESET_FORMAT}"
PLAINTEXT=$(cat 1.txt | base64 -w0)

curl -s "https://cloudkms.googleapis.com/v1/projects/${DEVSHELL_PROJECT_ID}/locations/global/keyRings/${KEYRING_NAME}/cryptoKeys/${CRYPTOKEY_NAME}:encrypt" \
  -d "{\"plaintext\":\"${PLAINTEXT}\"}" \
  -H "Authorization:Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type:application/json" \
| jq .ciphertext -r > 1.encrypted

echo "${CYAN_TEXT}${BOLD_TEXT}Decrypt to verify:${RESET_FORMAT}"
curl -s "https://cloudkms.googleapis.com/v1/projects/${DEVSHELL_PROJECT_ID}/locations/global/keyRings/${KEYRING_NAME}/cryptoKeys/${CRYPTOKEY_NAME}:decrypt" \
  -d "{\"ciphertext\":\"$(cat 1.encrypted)\"}" \
  -H "Authorization:Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type:application/json" \
| jq .plaintext -r | base64 -d

echo
echo

echo "${CYAN_TEXT}${BOLD_TEXT}Upload encrypted single file${RESET_FORMAT}"
gsutil cp 1.encrypted "gs://${BUCKET_NAME}/"

echo "${CYAN_TEXT}${BOLD_TEXT}[7/8] Configure IAM permissions${RESET_FORMAT}"
USER_EMAIL=$(gcloud auth list --limit=1 2>/dev/null | grep '@' | awk '{print $2}')

gcloud kms keyrings add-iam-policy-binding "$KEYRING_NAME" \
  --location global \
  --member "user:${USER_EMAIL}" \
  --role roles/cloudkms.admin

gcloud kms keyrings add-iam-policy-binding "$KEYRING_NAME" \
  --location global \
  --member "user:${USER_EMAIL}" \
  --role roles/cloudkms.cryptoKeyEncrypterDecrypter

echo "${CYAN_TEXT}${BOLD_TEXT}[8/8] Encrypt all finance-dept inbox files and upload${RESET_FORMAT}"
gsutil -m cp -r "gs://${GOOGLE_CLOUD_PROJECT}-kms-lab-data/finance-dept" .

MYDIR="finance-dept"
FILES=$(find "$MYDIR" -type f -not -name "*.encrypted")

for file in $FILES; do
  echo "${TEAL_TEXT}Encrypting: ${file}${RESET_FORMAT}"

  PLAINTEXT=$(cat "$file" | base64 -w0)

  curl -s "https://cloudkms.googleapis.com/v1/projects/${DEVSHELL_PROJECT_ID}/locations/global/keyRings/${KEYRING_NAME}/cryptoKeys/${CRYPTOKEY_NAME}:encrypt" \
    -d "{\"plaintext\":\"${PLAINTEXT}\"}" \
    -H "Authorization:Bearer $(gcloud auth application-default print-access-token)" \
    -H "Content-Type:application/json" \
  | jq .ciphertext -r > "${file}.encrypted"
done

gsutil -m cp finance-dept/inbox/*.encrypted "gs://${BUCKET_NAME}/finance-dept/inbox/"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}              LAB COMPLETED SUCCESSFULLY!${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}Bucket:${RESET_FORMAT} gs://${BUCKET_NAME}"
echo "${CYAN_TEXT}${BOLD_TEXT}Keyring:${RESET_FORMAT} ${KEYRING_NAME}"
echo "${CYAN_TEXT}${BOLD_TEXT}CryptoKey:${RESET_FORMAT} ${CRYPTOKEY_NAME}"
echo
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"