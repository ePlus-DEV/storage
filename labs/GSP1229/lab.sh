#!/usr/bin/env bash
# ePlus.DEV - GSP1229 (Unlicense)
# Copyright (c) 2026 ePlus.DEV | Unlicense
# Official lab: https://www.skills.google/focuses/85991
set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RESET=$'\033[0m'
else
  CYAN=''; GREEN=''; YELLOW=''; RESET=''
fi
step() { printf '%s== %s ==%s\n' "$CYAN" "$*" "$RESET"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
step 'ePlus.DEV – Starting Execution'

command -v gcloud >/dev/null 2>&1 || die 'gcloud is required.'
command -v python3 >/dev/null 2>&1 || die 'python3 is required.'
PROJECT_ID="${PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}}"
REGION="${REGION:-${GOOGLE_CLOUD_REGION:-$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null || true)}}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || die 'Set PROJECT_ID to the lab project.'
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || die 'Set REGION to the lab region.'
  read -r -p 'Lab region: ' REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || die "Invalid region: $REGION"
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID" GOOGLE_CLOUD_REGION="$REGION"
AR_REPO='gemini-repo'
SERVICE_NAME='gemini-streamlit-app'
WORK_DIR="${GSP1229_WORK_DIR:-$HOME/gsp1229-work}"
mkdir -p "$WORK_DIR"

step 'Task 1: Download official lab source'
APP_DIR="$WORK_DIR/gemini-streamlit-cloudrun"
if [[ -e "$APP_DIR" ]]; then
  [[ -d "$APP_DIR" && -f "$APP_DIR/app.py" && -f "$APP_DIR/requirements.txt" ]] || die "Existing $APP_DIR is not the expected lab source; will not overwrite it."
  printf '%sReusing existing lab source.%s\n' "$YELLOW" "$RESET"
else
  gcloud storage cp -R gs://spls/gsp1229/gemini-streamlit-cloudrun "$WORK_DIR/"
fi
cd "$APP_DIR"
[[ -f app.py && -f requirements.txt ]] || die 'Official lab source is incomplete.'

step 'Task 1: Configure Gemini model placeholders'
# The six model IDs/names are supplied per lab session. Never guess them.
model_keys=(GEMINI_PRO_MODEL_ID GEMINI_FLASH_MODEL_ID GEMINI_FLASH_LITE_MODEL_ID GEMINI_PRO_MODEL_NAME GEMINI_FLASH_MODEL_NAME GEMINI_FLASH_LITE_MODEL_NAME)
for key in "${model_keys[@]}"; do
  if grep -Fq "__${key}__" app.py; then
    value="${!key:-}"
    if [[ -z "$value" ]]; then
      [[ -t 0 ]] || die "Set $key from the lab instructions before running."
      read -r -p "Enter lab-provided $key: " value
    fi
    [[ -n "$value" ]] || die "Missing $key"
    export "$key=$value"
  fi
done
python3 - <<'PY'
import os
from pathlib import Path
path = Path('app.py')
text = path.read_text()
keys = (
    'GEMINI_PRO_MODEL_ID', 'GEMINI_FLASH_MODEL_ID',
    'GEMINI_FLASH_LITE_MODEL_ID', 'GEMINI_PRO_MODEL_NAME',
    'GEMINI_FLASH_MODEL_NAME', 'GEMINI_FLASH_LITE_MODEL_NAME',
)
for key in keys:
    placeholder = '__' + key + '__'
    if placeholder in text:
        value = os.environ.get(key, '')
        if not value:
            raise SystemExit('Missing model setting: ' + key)
        text = text.replace(placeholder, value)
path.write_text(text)
PY

step 'Task 1: Install Python dependencies'
if [[ ! -x gemini-streamlit/bin/python ]]; then
  python3 -m venv gemini-streamlit
fi
# shellcheck disable=SC1091
source gemini-streamlit/bin/activate
python3 -m pip install -r requirements.txt

step 'Task 1: Ensure Artifact Registry repository'
if ! gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$AR_REPO" --location="$REGION" --repository-format=docker --project="$PROJECT_ID"
fi

step 'Task 1: Build and push container'
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/$SERVICE_NAME"
gcloud builds submit --project="$PROJECT_ID" --tag="$IMAGE" .

step 'Task 1: Deploy Cloud Run service'
gcloud run deploy "$SERVICE_NAME" \
  --port=8080 --image="$IMAGE" --allow-unauthenticated \
  --region="$REGION" --platform=managed --project="$PROJECT_ID" \
  --set-env-vars="GOOGLE_CLOUD_PROJECT=$PROJECT_ID,GOOGLE_CLOUD_REGION=$REGION"

printf '%sDeployment submitted. Verify the service and click Check my progress; grader/runtime PASS is unverified.%s\n' "$GREEN" "$RESET"
