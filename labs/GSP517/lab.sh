#!/usr/bin/env bash

# ==============================================================================
# ePlus.DEV - Gemini Streamlit Chef Challenge Lab
# Tasks 2-5: prepare chef.py, test locally, build Artifact Registry image,
# and deploy to Cloud Run.
#
# Copyright (c) ePlus.DEV. All rights reserved.
# https://eplus.dev
# ==============================================================================

set -Eeuo pipefail

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { printf '\n%b[INFO]%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
success() { printf '\n%b[DONE]%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn()    { printf '\n%b[WARN]%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*"; }
error()   { printf '\n%b[ERROR]%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; }

banner() {
  local year
  year="$(date +%Y)"
  printf '\n%b╔══════════════════════════════════════════════════════════╗%b\n' "${CYAN}${BOLD}" "$RESET"
  printf '%b║          ePlus.DEV - Gemini Streamlit Chef Lab           ║%b\n' "${CYAN}${BOLD}" "$RESET"
  printf '%b║              Safe • Resumable • Cloud Run                ║%b\n' "${BLUE}${BOLD}" "$RESET"
  printf '%b╚══════════════════════════════════════════════════════════╝%b\n' "${CYAN}${BOLD}" "$RESET"
  printf '%b© %s ePlus.DEV. All rights reserved.%b\n' "${YELLOW}${BOLD}" "$year" "$RESET"
  printf '%bhttps://eplus.dev%b\n\n' "${DIM}${WHITE}" "$RESET"
}

# Keep the Cloud Shell pane open after success or failure. This is especially
# useful when the script is launched from the Cloud Shell Editor Run button.
KEEP_TERMINAL_OPEN="${KEEP_TERMINAL_OPEN:-1}"
SCRIPT_STATUS=0
CURRENT_STEP='initialization'

keep_terminal_open() {
  local status="$1"
  trap - EXIT ERR INT TERM

  printf '\n'
  if (( status == 0 )); then
    printf '%b[ePlus.DEV]%b Script finished.\n' "${GREEN}${BOLD}" "$RESET"
  else
    printf '%b[ePlus.DEV]%b Script stopped during: %s\n' \
      "${RED}${BOLD}" "$RESET" "$CURRENT_STEP"
    printf 'Run %bbash ~/lab.sh%b again to continue from the saved state.\n' \
      "${YELLOW}${BOLD}" "$RESET"
  fi

  if [[ "$KEEP_TERMINAL_OPEN" == '1' && -t 0 ]]; then
    printf 'The terminal will remain open. Type %bexit%b only when needed.\n\n' \
      "${YELLOW}${BOLD}" "$RESET"
    cd "${APP_DIR:-$HOME}" 2>/dev/null || cd "$HOME"
    exec bash -i
  fi

  exit "$status"
}

on_error() {
  local status=$?
  local line="${BASH_LINENO[0]:-${LINENO}}"
  SCRIPT_STATUS="$status"
  error "Command failed at line ${line} while running: ${CURRENT_STEP}"
}

on_interrupt() {
  SCRIPT_STATUS=130
  warn 'Interrupted. Cloud Build and Cloud Run operations already submitted will continue on Google Cloud.'
}

trap on_error ERR
trap on_interrupt INT TERM
trap 'keep_terminal_open "$SCRIPT_STATUS"' EXIT

metadata_value() {
  local key="$1"
  gcloud compute project-info describe \
    --project="$PROJECT" \
    --format="value(commonInstanceMetadata.items[${key}])" \
    2>/dev/null | head -n1
}

save_state() {
  cat > "$STATE_FILE" <<EOF
PROJECT=$(printf '%q' "$PROJECT")
REGION=$(printf '%q' "$REGION")
ZONE=$(printf '%q' "$ZONE")
TASK2_DONE=$(printf '%q' "$TASK2_DONE")
TASK3_DONE=$(printf '%q' "$TASK3_DONE")
BUILD_ID=$(printf '%q' "$BUILD_ID")
BUILD_DONE=$(printf '%q' "$BUILD_DONE")
DEPLOY_SUBMITTED=$(printf '%q' "$DEPLOY_SUBMITTED")
DEPLOY_DONE=$(printf '%q' "$DEPLOY_DONE")
TASK5_DONE=$(printf '%q' "$TASK5_DONE")
SERVICE_URL=$(printf '%q' "$SERVICE_URL")
EOF
}

wait_for_url() {
  local url="$1"
  local attempts="${2:-90}"
  local delay="${3:-2}"
  local i

  for ((i=1; i<=attempts; i++)); do
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

stop_local_app() {
  local pid=''

  if [[ -f "$LOCAL_PID_FILE" ]]; then
    pid="$(cat "$LOCAL_PID_FILE" 2>/dev/null || true)"
  fi

  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in {1..15}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$LOCAL_PID_FILE"
}

start_local_app() {
  local pid=''

  if [[ -f "$LOCAL_PID_FILE" ]]; then
    pid="$(cat "$LOCAL_PID_FILE" 2>/dev/null || true)"
  fi

  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    info "Reusing the existing Streamlit process: PID ${pid}"
    return 0
  fi

  rm -f "$LOCAL_PID_FILE"
  : > "$LOCAL_LOG"

  # nohup keeps Streamlit alive if the Cloud Shell browser reconnects.
  nohup "$VENV_DIR/bin/streamlit" run chef.py \
    --server.port=8080 \
    --server.address=0.0.0.0 \
    --server.headless=true \
    --server.enableCORS=false \
    --server.enableXsrfProtection=false \
    > "$LOCAL_LOG" 2>&1 < /dev/null &

  pid=$!
  printf '%s\n' "$pid" > "$LOCAL_PID_FILE"
  disown "$pid" 2>/dev/null || true
}

build_status() {
  gcloud builds describe "$BUILD_ID" \
    --project="$PROJECT" \
    --region="$REGION" \
    --format='value(status)' 2>/dev/null || true
}

cloud_run_ready() {
  local values=''
  local url=''
  local ready_revision=''
  local created_revision=''

  values="$(gcloud run services describe "$SERVICE_NAME" \
    --project="$PROJECT" \
    --region="$REGION" \
    --platform=managed \
    --format='value(status.url,status.latestReadyRevisionName,status.latestCreatedRevisionName)' \
    2>/dev/null || true)"

  read -r url ready_revision created_revision <<< "$values"

  if [[ -n "$url" && -n "$ready_revision" && "$ready_revision" == "$created_revision" ]]; then
    SERVICE_URL="$url"
    return 0
  fi

  return 1
}

patch_chef_file() {
  PROJECT="$PROJECT" MODEL_ID="$MODEL_ID" python3 - <<'PY'
from pathlib import Path
import os
import re

path = Path("chef.py")
text = path.read_text(encoding="utf-8")
project = os.environ["PROJECT"]
model_id = os.environ["MODEL_ID"]

# Required challenge-lab placeholders.
text = text.replace("GCP_PROJECT_ID", project)
text = text.replace("GEMINI_FLASH_MODEL_ID", model_id)

# Handle common constant variants without touching unrelated strings.
text = re.sub(
    r'(?m)^(\s*(?:PROJECT_ID|GCP_PROJECT)\s*=\s*)["\'][^"\']*["\']',
    rf'\1"{project}"',
    text,
)
text = re.sub(
    r'(?m)^(\s*(?:MODEL_ID|GEMINI_MODEL_ID)\s*=\s*)["\'][^"\']*["\']',
    rf'\1"{model_id}"',
    text,
)

prompt_pattern = re.compile(
    r'(?ms)^(?P<indent>[ \t]*)prompt\s*=\s*f?(?P<quote>"""|\'\'\').*?(?P=quote)'
)
match = prompt_pattern.search(text)
if not match:
    raise SystemExit("Unable to find the prompt block in chef.py")

indent = match.group("indent")

# Remove any previously inserted wine radio assignment so rerunning is idempotent.
text = re.sub(
    r'(?ms)^[ \t]*wine\s*=\s*st\.radio\(.*?\)\s*\n',
    '',
    text,
    count=1,
)

# Find the prompt again after the optional removal.
match = prompt_pattern.search(text)
if not match:
    raise SystemExit("Unable to relocate the prompt block in chef.py")
indent = match.group("indent")

wine_block = (
    f'{indent}wine = st.radio(\n'
    f'{indent}    "What is your customer\'s wine preference?",\n'
    f'{indent}    ["Red", "White", "None"],\n'
    f'{indent})\n\n'
)
text = text[:match.start()] + wine_block + text[match.start():]

match = prompt_pattern.search(text)
if not match:
    raise SystemExit("Unable to locate the prompt after adding wine")
indent = match.group("indent")

required_prompt = '''prompt = f"""I am a Chef.  I need to create {cuisine} \\n
recipes for customers who want {dietary_preference} meals. \\n
However, don't include recipes that use ingredients with the customer's {allergy} allergy. \\n
I have {ingredient_1}, \\n
{ingredient_2}, \\n
and {ingredient_3} \\n
in my kitchen and other ingredients. \\n
The customer's wine preference is {wine} \\n
Please provide some for meal recommendations.
For each recommendation include preparation instructions,
time to prepare
and the recipe title at the beginning of the response.
Then include the wine paring for each recommendation.
At the end of the recommendation provide the calories associated with the meal
and the nutritional facts.
"""'''
required_prompt = "\n".join(indent + line for line in required_prompt.splitlines())
text = text[:match.start()] + required_prompt + text[match.end():]

path.write_text(text, encoding="utf-8")
PY
}

write_dockerfile() {
  cat > Dockerfile <<'DOCKERFILE'
FROM python:3.12-slim

EXPOSE 8080
WORKDIR /app

COPY . ./

RUN pip install --no-cache-dir -r requirements.txt

ENTRYPOINT ["streamlit", "run", "chef.py", "--server.port=8080", "--server.address=0.0.0.0"]
DOCKERFILE

  # Keep the Cloud Build upload small. Older script versions created the
  # virtual environment inside this directory, which caused reconnects while
  # gcloud attempted to archive and upload thousands of unnecessary files.
  cat > .gcloudignore <<'GCLOUDIGNORE'
.gcloudignore
.git
.gitignore
__pycache__/
*.py[cod]
*.log
gemini-streamlit/
.venv/
venv/
Dockerfile.original
GCLOUDIGNORE
}

# ==============================================================================
# Initialization
# ==============================================================================

banner

CURRENT_STEP='detecting the active project and assigned region'
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$PROJECT" && "$PROJECT" != '(unset)' ]] || {
  error 'No active Google Cloud project was found.'
  SCRIPT_STATUS=1
  exit 1
}

ZONE="${ZONE:-$(metadata_value google-compute-default-zone || true)}"
REGION="${REGION:-$(metadata_value google-compute-default-region || true)}"

if [[ -z "$REGION" || "$REGION" == 'global' ]]; then
  if [[ -n "$ZONE" ]]; then
    REGION="${ZONE%-*}"
  else
    ZONE="$(gcloud workbench instances list \
      --project="$PROJECT" \
      --filter='name:generative-ai-jupyterlab' \
      --limit=1 \
      --format='value(location)' 2>/dev/null | head -n1 || true)"
    ZONE="${ZONE##*/}"
    [[ -n "$ZONE" ]] && REGION="${ZONE%-*}"
  fi
fi

[[ -n "$REGION" && "$REGION" != 'global' ]] || {
  error 'Could not detect the region assigned by the lab.'
  SCRIPT_STATUS=1
  exit 1
}

MODEL_ID='gemini-2.5-flash'
AR_REPO='chef-repo'
SERVICE_NAME='chef-streamlit-app'
SOURCE_BUCKET="gs://${PROJECT}-gemini"
TARGET_BUCKET="gs://${PROJECT}-generative-ai"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${AR_REPO}/${SERVICE_NAME}"
REPO_DIR="${HOME}/generative-ai"
APP_DIR="${REPO_DIR}/gemini/sample-apps/gemini-streamlit-cloudrun"
VENV_DIR="${HOME}/gemini-streamlit-chef-env"
LOCAL_LOG="${HOME}/chef-streamlit-local.log"
LOCAL_PID_FILE="${HOME}/chef-streamlit-local.pid"
STATE_FILE="${HOME}/.eplus-chef-v3-${PROJECT}.env"

TASK2_DONE=0
TASK3_DONE=0
BUILD_ID=''
BUILD_DONE=0
DEPLOY_SUBMITTED=0
DEPLOY_DONE=0
TASK5_DONE=0
SERVICE_URL=''

if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"
fi

# The current Cloud Shell project is always authoritative.
PROJECT="$(gcloud config get-value project 2>/dev/null)"
SOURCE_BUCKET="gs://${PROJECT}-gemini"
TARGET_BUCKET="gs://${PROJECT}-generative-ai"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${AR_REPO}/${SERVICE_NAME}"
STATE_FILE="${HOME}/.eplus-chef-v3-${PROJECT}.env"

printf '%bProject:%b %s\n' "${BLUE}${BOLD}" "$RESET" "$PROJECT"
printf '%bRegion :%b %s\n' "${BLUE}${BOLD}" "$RESET" "$REGION"
printf '%bZone   :%b %s\n' "${BLUE}${BOLD}" "$RESET" "${ZONE:-not set}"
printf '%bModel  :%b %s\n' "${BLUE}${BOLD}" "$RESET" "$MODEL_ID"
printf '%bSource :%b %s/chef.py\n' "${BLUE}${BOLD}" "$RESET" "$SOURCE_BUCKET"
printf '%bTarget :%b %s/chef.py\n' "${BLUE}${BOLD}" "$RESET" "$TARGET_BUCKET"
printf '%bImage  :%b %s\n' "${BLUE}${BOLD}" "$RESET" "$IMAGE"

# ==============================================================================
# Task 2 - Prepare chef.py
# ==============================================================================

if [[ "$TASK2_DONE" != '1' ]]; then
  CURRENT_STEP='Task 2 - enabling APIs'
  info 'Configuring the project and enabling required APIs.'
  gcloud config set project "$PROJECT" >/dev/null
  gcloud services enable \
    aiplatform.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    logging.googleapis.com \
    --project="$PROJECT" >/dev/null

  CURRENT_STEP='Task 2 - preparing the sample repository'
  info 'Preparing the Google Cloud sample application.'
  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    rm -rf "$REPO_DIR"
    git clone --depth=1 --filter=blob:none --sparse \
      https://github.com/GoogleCloudPlatform/generative-ai.git "$REPO_DIR"
    git -C "$REPO_DIR" sparse-checkout set \
      gemini/sample-apps/gemini-streamlit-cloudrun
  fi

  [[ -d "$APP_DIR" ]] || {
    error "Application directory not found: $APP_DIR"
    SCRIPT_STATUS=1
    exit 1
  }
  cd "$APP_DIR"

  CURRENT_STEP='Task 2 - downloading chef.py'
  info 'Downloading chef.py from the current lab bucket.'
  if ! gcloud storage ls "${SOURCE_BUCKET}/chef.py" >/dev/null 2>&1; then
    error "Cannot read ${SOURCE_BUCKET}/chef.py"
    error 'Confirm that Cloud Shell is using the current lab account and project.'
    SCRIPT_STATUS=1
    exit 1
  fi
  gcloud storage cp "${SOURCE_BUCKET}/chef.py" ./chef.py

  CURRENT_STEP='Task 2 - updating requirements and chef.py'
  touch requirements.txt
  grep -Fqx 'google-cloud-logging' requirements.txt || echo 'google-cloud-logging' >> requirements.txt

  # Add a compatible SDK only when the downloaded template imports it.
  if grep -Eq '(^|[[:space:]])(from|import)[[:space:]]+vertexai' chef.py; then
    grep -Fqx 'google-cloud-aiplatform' requirements.txt || echo 'google-cloud-aiplatform' >> requirements.txt
  fi
  if grep -Eq 'from[[:space:]]+google[[:space:]]+import[[:space:]]+genai|from[[:space:]]+google\.genai|import[[:space:]]+google\.genai' chef.py; then
    grep -Fqx 'google-genai' requirements.txt || echo 'google-genai' >> requirements.txt
  fi

  patch_chef_file

  python3 -m py_compile chef.py
  grep -Fq "$PROJECT" chef.py
  grep -Fq "$MODEL_ID" chef.py
  grep -Fq '["Red", "White", "None"]' chef.py
  grep -Fq "The customer's wine preference is {wine}" chef.py

  CURRENT_STEP='Task 2 - uploading chef.py for validation'
  info 'Uploading the completed chef.py for Task 2 validation.'
  gcloud storage cp chef.py "${TARGET_BUCKET}/chef.py"

  TASK2_DONE=1
  save_state
  success 'Task 2 completed.'
else
  success 'Task 2 was already completed. Continuing.'
fi

cd "$APP_DIR"

# ==============================================================================
# Task 3 - Run and test the Streamlit app
# ==============================================================================

if [[ "$TASK3_DONE" != '1' ]]; then
  CURRENT_STEP='Task 3 - creating the virtual environment'
  info 'Creating the Python virtual environment and installing dependencies.'
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
  fi
  "$VENV_DIR/bin/python" -m pip install --quiet --upgrade pip
  "$VENV_DIR/bin/python" -m pip install --quiet -r requirements.txt

  export PROJECT REGION
  export GCP_PROJECT="$PROJECT"
  export GCP_REGION="$REGION"
  export GOOGLE_CLOUD_PROJECT="$PROJECT"
  export GOOGLE_CLOUD_REGION="$REGION"

  CURRENT_STEP='Task 3 - starting Streamlit'
  info 'Starting chef.py on port 8080.'
  start_local_app

  if ! wait_for_url 'http://127.0.0.1:8080/_stcore/health' 90 2; then
    tail -n 120 "$LOCAL_LOG" || true
    error 'Streamlit did not become healthy on port 8080.'
    SCRIPT_STATUS=1
    exit 1
  fi

  success 'The local Streamlit application is ready.'
  printf '\n%bTASK 3 — REQUIRED MANUAL TEST%b\n' "${YELLOW}${BOLD}" "$RESET"
  printf '1. Open %bWeb Preview → Preview on port 8080%b.\n' "${CYAN}${BOLD}" "$RESET"
  printf '2. Select cuisine, dietary preference, allergy, ingredients and wine.\n'
  printf '3. Click %bGenerate my recipe%b.\n' "${CYAN}${BOLD}" "$RESET"
  printf '4. Wait until a real Gemini recipe is displayed.\n\n'

  if [[ -t 0 ]]; then
    read -r -p 'Press ENTER only after the recipe appears successfully... ' _
  else
    error 'An interactive terminal is required for the Task 3 confirmation.'
    SCRIPT_STATUS=1
    exit 1
  fi

  stop_local_app
  TASK3_DONE=1
  save_state
  success 'Task 3 completed.'
else
  stop_local_app
  success 'Task 3 was already completed. Continuing.'
fi

# ==============================================================================
# Task 4 - Dockerfile, Artifact Registry, and Cloud Build
# ==============================================================================

CURRENT_STEP='Task 4 - writing Dockerfile'
info 'Writing the Dockerfile to run chef.py.'

# Remove the large in-project virtual environment left by older script versions.
# The active environment used by this script is stored in $HOME instead.
if [[ -d "${APP_DIR}/gemini-streamlit" ]]; then
  info 'Removing the old in-project virtual environment before Cloud Build.'
  rm -rf "${APP_DIR}/gemini-streamlit"
fi

write_dockerfile

printf '\n'
cat Dockerfile
printf '\n'

grep -Fqx 'ENTRYPOINT ["streamlit", "run", "chef.py", "--server.port=8080", "--server.address=0.0.0.0"]' Dockerfile

CURRENT_STEP='Task 4 - preparing Artifact Registry'
info 'Ensuring the chef-repo Artifact Registry repository exists.'
if ! gcloud artifacts repositories describe "$AR_REPO" \
  --location="$REGION" \
  --project="$PROJECT" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$AR_REPO" \
    --location="$REGION" \
    --repository-format=docker \
    --project="$PROJECT" \
    --quiet
fi

if [[ "$BUILD_DONE" != '1' ]]; then
  if [[ -z "$BUILD_ID" ]]; then
    CURRENT_STEP='Task 4 - submitting Cloud Build'
    info 'Submitting Cloud Build asynchronously.'
    BUILD_ID="$(gcloud builds submit . \
      --project="$PROJECT" \
      --region="$REGION" \
      --tag="$IMAGE" \
      --async \
      --format='value(id)')"

    [[ -n "$BUILD_ID" ]] || {
      error 'Cloud Build did not return a Build ID.'
      SCRIPT_STATUS=1
      exit 1
    }

    save_state
    success "Cloud Build submitted: ${BUILD_ID}"
  else
    info "Resuming Cloud Build monitoring: ${BUILD_ID}"
  fi

  CURRENT_STEP='Task 4 - waiting for Cloud Build'
  while true; do
    STATUS="$(build_status)"
    case "$STATUS" in
      SUCCESS)
        BUILD_DONE=1
        save_state
        break
        ;;
      FAILURE|INTERNAL_ERROR|TIMEOUT|CANCELLED|EXPIRED)
        error "Cloud Build ended with status: ${STATUS}"
        printf 'Inspect it with:\n'
        printf 'gcloud builds describe %q --region=%q --project=%q\n' "$BUILD_ID" "$REGION" "$PROJECT"
        SCRIPT_STATUS=1
        exit 1
        ;;
      QUEUED|WORKING|PENDING|'')
        printf '%b[BUILD]%b %-10s Build ID: %s\n' "${MAGENTA}${BOLD}" "$RESET" "${STATUS:-STARTING}" "$BUILD_ID"
        sleep 20
        ;;
      *)
        printf '%b[BUILD]%b %-10s Build ID: %s\n' "${MAGENTA}${BOLD}" "$RESET" "$STATUS" "$BUILD_ID"
        sleep 20
        ;;
    esac
  done
fi

success 'Task 4 completed: the chef.py image was pushed to Artifact Registry.'

# ==============================================================================
# Task 5 - Deploy to Cloud Run and test
# ==============================================================================

if [[ "$DEPLOY_DONE" != '1' ]]; then
  if cloud_run_ready; then
    DEPLOY_DONE=1
    DEPLOY_SUBMITTED=1
    save_state
  else
    if [[ "$DEPLOY_SUBMITTED" != '1' ]]; then
      CURRENT_STEP='Task 5 - submitting Cloud Run deployment'
      info 'Submitting the Cloud Run deployment asynchronously.'
      gcloud run deploy "$SERVICE_NAME" \
        --port=8080 \
        --image="$IMAGE" \
        --allow-unauthenticated \
        --region="$REGION" \
        --platform=managed \
        --project="$PROJECT" \
        --set-env-vars="PROJECT=$PROJECT,REGION=$REGION" \
        --async \
        --quiet

      DEPLOY_SUBMITTED=1
      save_state
    else
      info 'Resuming Cloud Run deployment monitoring.'
    fi

    CURRENT_STEP='Task 5 - waiting for Cloud Run'
    for _ in {1..90}; do
      if cloud_run_ready; then
        DEPLOY_DONE=1
        save_state
        break
      fi
      printf '%b[RUN]%b Waiting for the Cloud Run revision to become ready...\n' "${MAGENTA}${BOLD}" "$RESET"
      sleep 10
    done
  fi

  [[ "$DEPLOY_DONE" == '1' ]] || {
    error 'Cloud Run did not become ready within the expected time.'
    SCRIPT_STATUS=1
    exit 1
  }
fi

if [[ -z "$SERVICE_URL" ]]; then
  SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT" \
    --format='value(status.url)')"
fi

[[ -n "$SERVICE_URL" ]] || {
  error 'Cloud Run service URL was not returned.'
  SCRIPT_STATUS=1
  exit 1
}

CURRENT_STEP='Task 5 - checking the deployed application'
if ! wait_for_url "${SERVICE_URL}/_stcore/health" 60 5; then
  error "Cloud Run health check failed: ${SERVICE_URL}"
  SCRIPT_STATUS=1
  exit 1
fi

success 'The Cloud Run service is healthy.'
printf '\n%bCloud Run URL:%b %s\n' "${GREEN}${BOLD}" "$RESET" "$SERVICE_URL"

if [[ "$TASK5_DONE" != '1' ]]; then
  printf '\n%bTASK 5 — REQUIRED MANUAL TEST%b\n' "${YELLOW}${BOLD}" "$RESET"
  printf '1. Open the Cloud Run URL shown above.\n'
  printf '2. Select values and click %bGenerate my recipe%b.\n' "${CYAN}${BOLD}" "$RESET"
  printf '3. Wait until a real recipe is displayed.\n\n'

  if [[ -t 0 ]]; then
    read -r -p 'Press ENTER only after the Cloud Run recipe appears successfully... ' _
  else
    error 'An interactive terminal is required for the Task 5 confirmation.'
    SCRIPT_STATUS=1
    exit 1
  fi

  TASK5_DONE=1
  save_state
fi

success 'Tasks 2, 3, 4 and 5 are complete.'
printf '\n%bClick “Check my progress” for each task.%b\n' "${GREEN}${BOLD}" "$RESET"
printf '%bCompleted by ePlus.DEV%b\n' "${MAGENTA}${BOLD}" "$RESET"

SCRIPT_STATUS=0
exit 0