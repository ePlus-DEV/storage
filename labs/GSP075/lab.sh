#!/usr/bin/env bash
# GSP075 - Extract, Analyze, and Translate Text from Images with the Cloud ML APIs
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -Eeuo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  CYAN=$'\033[1;36m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' RED=$'\033[0;31m' RESET=$'\033[0m'
else
  CYAN='' GREEN='' YELLOW='' RED='' RESET=''
fi
printf '%s\n' "${CYAN}==========================================================${RESET}" \
  "${CYAN} ePlus.DEV - Starting Execution | GSP075${RESET}" \
  "${YELLOW} Copyright (c) 2026 ePlus.DEV | Unlicense${RESET}" \
  "${CYAN}==========================================================${RESET}"

log() { printf '\n%s\n' "${CYAN}[$1] $2${RESET}"; }
ok() { printf '%s\n' "${GREEN}OK: $*${RESET}"; }
die() { printf '%s\n' "${RED}ERROR: $*${RESET}" >&2; exit 1; }
trap 'printf "ERROR: command failed at line %s (exit %s)\n" "$LINENO" "$?" >&2' ERR

for command in gcloud curl jq; do
  command -v "$command" >/dev/null 2>&1 || die "Missing required command: $command"
done

prompt_if_missing() {
  local name="$1" description="$2" value="${!1:-}"
  if [[ -z "$value" || "$value" == '(unset)' ]]; then
    [[ -t 0 ]] || die "Set $name ($description) and rerun in non-interactive mode."
    read -r -p "Enter $description: " value
  fi
  [[ -n "$value" ]] || die "$name cannot be empty"
  printf -v "$name" '%s' "$value"
}

PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-}}"
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi
prompt_if_missing PROJECT_ID 'lab project ID'
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,61}[a-z0-9]$ ]] || die "Invalid Google Cloud project ID: $PROJECT_ID"

REGION="${REGION:-}"
if [[ -z "$REGION" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || true)}"
  if [[ "$ZONE" =~ ^[a-z]+-[a-z0-9]+[0-9]-[a-z]$ ]]; then
    REGION="${ZONE%-*}"
  fi
fi
prompt_if_missing REGION 'lab region (for the Cloud Storage bucket)'
[[ "$REGION" =~ ^[a-z]+-[a-z0-9]+[0-9]$ ]] || die "Invalid region: $REGION"

BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-bucket}"
[[ "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$ ]] || die "Invalid bucket name"
WORKDIR="${WORKDIR:-${HOME}/gsp075}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

log 'Setup' "Project: $PROJECT_ID | Region: $REGION | Bucket: $BUCKET_NAME"
gcloud services enable --project="$PROJECT_ID" \
  apikeys.googleapis.com vision.googleapis.com translate.googleapis.com \
  language.googleapis.com storage.googleapis.com --quiet

log 'Task 1/6' 'Create or reuse a restricted API key'
if [[ -z "${API_KEY:-}" ]]; then
  KEY_NAME="$(gcloud services api-keys list --project="$PROJECT_ID" \
    --filter='displayName=eplus-gsp075' --format='value(name)' --limit=1 2>/dev/null || true)"
  if [[ -z "$KEY_NAME" ]]; then
    KEY_NAME="$(gcloud services api-keys create --project="$PROJECT_ID" \
      --display-name=eplus-gsp075 \
      --api-target=service=vision.googleapis.com \
      --api-target=service=translate.googleapis.com \
      --api-target=service=language.googleapis.com \
      --format='value(name)' --quiet)"
  fi
  [[ -n "$KEY_NAME" ]] || die 'API key resource could not be found or created'
  for attempt in 1 2 3 4 5; do
    API_KEY="$(gcloud services api-keys get-key-string "$KEY_NAME" \
      --project="$PROJECT_ID" --format='value(keyString)' 2>/dev/null || true)"
    [[ -n "$API_KEY" ]] && break
    [[ "$attempt" == 5 ]] || sleep 5
  done
fi
[[ -n "${API_KEY:-}" ]] || die 'API key string unavailable; inspect API Keys permissions'
export API_KEY
ok 'API key available (value not printed). Check my progress: Create an API Key.'

log 'Task 2/6' 'Create the bucket and upload the lab sign image'
if gcloud storage buckets describe "gs://$BUCKET_NAME" --format='value(name)' >/dev/null 2>&1; then
  PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
  OWNER_NUMBER="$(gcloud storage buckets describe "gs://$BUCKET_NAME" --format='value(projectNumber)')"
  [[ "$OWNER_NUMBER" == "$PROJECT_NUMBER" ]] || die 'Bucket exists but does not belong to the selected lab project'
  ok 'Existing bucket belongs to this project'
else
  gcloud storage buckets create "gs://$BUCKET_NAME" --project="$PROJECT_ID" \
    --location="$REGION" --no-uniform-bucket-level-access \
    --no-public-access-prevention --quiet
fi
if [[ ! -s sign.jpg ]]; then
  curl -fLsS --retry 3 --output sign.jpg \
    'https://cdn.qwiklabs.com/cBoI5P4dZ6k%2FAr5Mv7eME%2F0fCb4G6nIGB0odCXzpEa4%3D'
fi
[[ -s sign.jpg ]] || die 'The lab image could not be downloaded'
if ! gcloud storage objects describe "gs://$BUCKET_NAME/sign.jpg" >/dev/null 2>&1; then
  gcloud storage cp sign.jpg "gs://$BUCKET_NAME/sign.jpg" --project="$PROJECT_ID" --quiet
fi
# The lab explicitly requires PUBLIC READ on sign.jpg only; never grant bucket-wide access.
gcloud storage objects update "gs://$BUCKET_NAME/sign.jpg" \
  --add-acl-grant=entity=allUsers,role=READER --project="$PROJECT_ID" --quiet
ok 'Uploaded sign.jpg; object-only public reader ACL applied. Check my progress: Upload image to a bucket.'

api_post() {
  local endpoint="$1" request="$2" response="$3" attempt status
  for attempt in 1 2 3 4 5; do
    status="$(curl -sS --connect-timeout 10 --max-time 60 \
      -o "$response" -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' -H "X-goog-api-key: $API_KEY" \
      --data-binary "@$request" "$endpoint")" || status=000
    if [[ "$status" == 200 ]] && jq -e 'type == "object" and (has("error") | not)' "$response" >/dev/null; then
      return 0
    fi
    if [[ "$attempt" == 5 || ( "$status" != 403 && "$status" != 429 && "$status" != 500 && "$status" != 503 ) ]]; then
      jq -r '.error.message // "Unknown API error"' "$response" 2>/dev/null >&2 || true
      die "API call failed: $endpoint (HTTP $status, attempt $attempt)"
    fi
    sleep "$((attempt * 5))"
  done
}

log 'Task 3/6' 'Create Cloud Vision OCR request'
jq -n --arg uri "gs://$BUCKET_NAME/sign.jpg" \
  '{requests:[{image:{source:{gcsImageUri:$uri}},features:[{type:"TEXT_DETECTION",maxResults:10}]}]}' \
  > ocr-request.json
jq -e '.requests[0].image.source.gcsImageUri' ocr-request.json >/dev/null
ok 'ocr-request.json generated'

log 'Task 4/6' 'Run Cloud Vision text detection'
api_post 'https://vision.googleapis.com/v1/images:annotate' ocr-request.json ocr-response.json
OCR_TEXT="$(jq -er '.responses[0].textAnnotations[0].description' ocr-response.json)" \
  || die 'Vision response did not contain detected text'
[[ -n "$OCR_TEXT" ]] || die 'OCR returned empty text'
ok 'OCR text extracted into ocr-response.json'

log 'Task 5/6' 'Translate detected text into English'
jq -n --arg q "$OCR_TEXT" '{q:$q,target:"en"}' > translation-request.json
api_post 'https://translation.googleapis.com/language/translate/v2' \
  translation-request.json translation-response.json
TRANSLATED_TEXT="$(jq -er '.data.translations[0].translatedText' translation-response.json)" \
  || die 'Translation response did not contain translated text'
[[ -n "$TRANSLATED_TEXT" ]] || die 'Translation returned empty text'
ok 'English translation saved in translation-response.json'

log 'Task 6/6' 'Analyze translated text with Cloud Natural Language'
jq -n --arg text "$TRANSLATED_TEXT" \
  '{document:{type:"PLAIN_TEXT",content:$text},encodingType:"UTF8"}' > nl-request.json
api_post 'https://language.googleapis.com/v1/documents:analyzeEntities' \
  nl-request.json nl-response.json
jq -e '.entities | type == "array"' nl-response.json >/dev/null \
  || die 'Natural Language API returned no entities array'
ok 'Entities saved in nl-response.json. Check my progress: Analyzing the image text.'
printf '\n%s\n' "${GREEN}GSP075 tasks complete. Verify all three Check my progress checkpoints manually.${RESET}" \
  "Artifacts: $WORKDIR"
