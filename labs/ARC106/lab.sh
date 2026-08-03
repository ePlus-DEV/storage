#!/bin/bash
# ================================================================
# Copyright (c) 2026 ePlus.DEV. All Rights Reserved.
# Google Cloud Pub/Sub to BigQuery Dataflow Lab Automation
# ================================================================

set -Eeuo pipefail

# ----------------------------- Colors -----------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  MAGENTA='\033[0;35m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; BOLD=''; NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

trap 'echo -e "\n${RED}[ERROR]${NC} Script stopped at line ${LINENO}." >&2' ERR

clear 2>/dev/null || true
cat <<EOF
${CYAN}${BOLD}
╔══════════════════════════════════════════════════════════════╗
║                 ePlus.DEV · DATAFLOW LAB                    ║
║          Pub/Sub → Dataflow → BigQuery Automation           ║
╠══════════════════════════════════════════════════════════════╣
║  Copyright © 2026 ePlus.DEV. All Rights Reserved.           ║
╚══════════════════════════════════════════════════════════════╝
${NC}
EOF

# -------------------------- Input helpers -------------------------
read_required() {
  local variable_name="$1"
  local prompt_text="$2"
  local value=""

  while [[ -z "$value" ]]; do
    read -r -p "$(echo -e "${MAGENTA}${prompt_text}${NC}: ")" value
    value="${value//[[:space:]]/}"
    [[ -z "$value" ]] && warn "This field is required. Please enter a value."
  done

  printf -v "$variable_name" '%s' "$value"
  export "$variable_name"
}

validate_inputs() {
  [[ "$DATASET_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]{0,1023}$ ]] || \
    error "Invalid dataset name: $DATASET_NAME"

  [[ "$TABLE_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]{0,1023}$ ]] || \
    error "Invalid table name: $TABLE_NAME"

  [[ ${#TOPIC_NAME} -ge 3 && ${#TOPIC_NAME} -le 255 ]] || \
    error "Topic name must contain 3-255 characters."
  [[ "$TOPIC_NAME" =~ ^[A-Za-z][A-Za-z0-9._~+%-]+$ ]] || \
    error "Invalid Pub/Sub topic name: $TOPIC_NAME"

  # Maximum 32 characters because '-techcps' is appended to the classic job.
  [[ ${#JOB_NAME} -le 32 ]] || \
    error "Job name must not exceed 32 characters."
  [[ "$JOB_NAME" =~ ^[a-z]([-a-z0-9]*[a-z0-9])?$ ]] || \
    error "Dataflow job name must use lowercase letters, numbers, and hyphens."
}

# The four lab values are intentionally mandatory.
echo -e "${BOLD}Enter the required lab values:${NC}"
read_required DATASET_NAME "Dataset name (example: sensors_494)"
read_required TABLE_NAME   "Table name (example: temperature_104)"
read_required TOPIC_NAME   "Pub/Sub topic name (example: sensors-temp-21555)"
read_required JOB_NAME     "Dataflow job name (example: dfjob-89099)"
validate_inputs

# --------------------- Detect project and region ------------------
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || \
  error "No active Google Cloud project was found."

REGION="$(gcloud compute project-info describe \
  --project="$PROJECT_ID" \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
  2>/dev/null || true)"

if [[ -z "$REGION" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  read_required REGION "Google Cloud region (example: us-east1)"
fi

export PROJECT_ID REGION
export DEVSHELL_PROJECT_ID="$PROJECT_ID"

SUBSCRIPTION_NAME="${TOPIC_NAME}-sub"
CLASSIC_JOB_NAME="${JOB_NAME}-techcps"

cat <<EOF

${BOLD}Configuration${NC}
  Project ID       : ${CYAN}${PROJECT_ID}${NC}
  Region           : ${CYAN}${REGION}${NC}
  Dataset          : ${CYAN}${DATASET_NAME}${NC}
  Table            : ${CYAN}${TABLE_NAME}${NC}
  Topic            : ${CYAN}${TOPIC_NAME}${NC}
  Subscription     : ${CYAN}${SUBSCRIPTION_NAME}${NC}
  Flex job         : ${CYAN}${JOB_NAME}${NC}
  Classic job      : ${CYAN}${CLASSIC_JOB_NAME}${NC}

EOF

# -------------------------- Prerequisites -------------------------
info "Enabling required Google Cloud APIs..."
gcloud services enable \
  compute.googleapis.com \
  dataflow.googleapis.com \
  pubsub.googleapis.com \
  bigquery.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet
success "Required APIs are enabled."

# ---------------------- Storage and BigQuery ----------------------
if gsutil ls -b "gs://${PROJECT_ID}" >/dev/null 2>&1; then
  success "Cloud Storage bucket already exists: gs://${PROJECT_ID}"
else
  info "Creating Cloud Storage bucket: gs://${PROJECT_ID}"
  gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${PROJECT_ID}"
  success "Cloud Storage bucket created."
fi

if bq show --project_id="$PROJECT_ID" "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
  success "BigQuery dataset already exists: ${DATASET_NAME}"
else
  info "Creating BigQuery dataset: ${DATASET_NAME}"
  bq --project_id="$PROJECT_ID" --location="$REGION" mk \
    --dataset "${PROJECT_ID}:${DATASET_NAME}"
  success "BigQuery dataset created."
fi

if bq show --project_id="$PROJECT_ID" \
  "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" >/dev/null 2>&1; then
  success "BigQuery table already exists: ${DATASET_NAME}.${TABLE_NAME}"
else
  info "Creating BigQuery table: ${DATASET_NAME}.${TABLE_NAME}"
  bq --project_id="$PROJECT_ID" mk --table \
    "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" \
    data:STRING
  success "BigQuery table created."
fi

# ----------------------------- Pub/Sub ----------------------------
if gcloud pubsub topics describe "$TOPIC_NAME" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  success "Pub/Sub topic already exists: ${TOPIC_NAME}"
else
  info "Creating Pub/Sub topic: ${TOPIC_NAME}"
  gcloud pubsub topics create "$TOPIC_NAME" \
    --project="$PROJECT_ID" --quiet
  success "Pub/Sub topic created."
fi

if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  success "Pub/Sub subscription already exists: ${SUBSCRIPTION_NAME}"
else
  info "Creating Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
  gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
    --topic="$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --quiet
  success "Pub/Sub subscription created."
fi

# ------------------------- Dataflow helpers -----------------------
get_job_state() {
  local job_name="$1"
  gcloud dataflow jobs list \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --filter="name=${job_name}" \
    --format="value(state)" 2>/dev/null | head -n 1 || true
}

is_job_running() {
  local state
  state="$(get_job_state "$1")"
  [[ "${state,,}" == *"running"* ]]
}

wait_for_job() {
  local job_name="$1"
  local max_attempts=40
  local sleep_seconds=15
  local attempt state state_lower

  info "Waiting for Dataflow job '${job_name}' to enter Running state..."

  for ((attempt=1; attempt<=max_attempts; attempt++)); do
    state="$(get_job_state "$job_name")"
    state_lower="${state,,}"

    if [[ "$state_lower" == *"running"* ]]; then
      success "Dataflow job '${job_name}' is running."
      return 0
    fi

    if [[ "$state_lower" == *"failed"* ||
          "$state_lower" == *"cancelled"* ||
          "$state_lower" == *"drained"* ]]; then
      error "Dataflow job '${job_name}' entered terminal state: ${state}"
    fi

    echo -e "${YELLOW}[WAIT ${attempt}/${max_attempts}]${NC} Current state: ${state:-Not available yet}"
    sleep "$sleep_seconds"
  done

  error "Timed out while waiting for Dataflow job '${job_name}'."
}

get_row_count() {
  bq query \
    --project_id="$PROJECT_ID" \
    --quiet \
    --nouse_legacy_sql \
    --format=csv \
    "SELECT COUNT(*) AS row_count FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}\`" \
    2>/dev/null | tail -n 1 | tr -d '\r' || echo 0
}

publish_and_verify() {
  local source_job="$1"
  local before_count after_count attempt

  before_count="$(get_row_count)"
  [[ "$before_count" =~ ^[0-9]+$ ]] || before_count=0

  info "Publishing a test message for '${source_job}'..."
  gcloud pubsub topics publish "$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --message='{"data":"73.4 F"}' \
    --quiet

  for ((attempt=1; attempt<=24; attempt++)); do
    after_count="$(get_row_count)"
    [[ "$after_count" =~ ^[0-9]+$ ]] || after_count=0

    if (( after_count > before_count )); then
      success "BigQuery received the test message."
      bq query \
        --project_id="$PROJECT_ID" \
        --nouse_legacy_sql \
        "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}\` ORDER BY data DESC LIMIT 20"
      return 0
    fi

    echo -e "${YELLOW}[VERIFY ${attempt}/24]${NC} Waiting for a new BigQuery row..."
    sleep 10
  done

  warn "No new row was detected before the verification timeout."
  bq query \
    --project_id="$PROJECT_ID" \
    --nouse_legacy_sql \
    "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}\` LIMIT 20" || true
}

# ------------------------ Flex Template job -----------------------
if is_job_running "$JOB_NAME"; then
  warn "Flex job '${JOB_NAME}' is already running. Launch skipped."
else
  info "Launching the Pub/Sub to BigQuery Flex Template job..."
  gcloud dataflow flex-template run "$JOB_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --template-file-gcs-location="gs://dataflow-templates-${REGION}/latest/flex/PubSub_to_BigQuery_Flex" \
    --temp-location="gs://${PROJECT_ID}/temp/" \
    --staging-location="gs://${PROJECT_ID}/staging/" \
    --parameters="outputTableSpec=${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME},inputTopic=projects/${PROJECT_ID}/topics/${TOPIC_NAME},javascriptTextTransformReloadIntervalMinutes=0,useStorageWriteApi=false,useStorageWriteApiAtLeastOnce=false,numStorageWriteApiStreams=0"
fi

wait_for_job "$JOB_NAME"
publish_and_verify "$JOB_NAME"

# ----------------------- Classic Template job ---------------------
if is_job_running "$CLASSIC_JOB_NAME"; then
  warn "Classic job '${CLASSIC_JOB_NAME}' is already running. Launch skipped."
else
  info "Launching the classic Pub/Sub to BigQuery template job..."
  gcloud dataflow jobs run "$CLASSIC_JOB_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --gcs-location="gs://dataflow-templates-${REGION}/latest/PubSub_to_BigQuery" \
    --staging-location="gs://${PROJECT_ID}/temp/" \
    --parameters="inputTopic=projects/${PROJECT_ID}/topics/${TOPIC_NAME},outputTableSpec=${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}"
fi

wait_for_job "$CLASSIC_JOB_NAME"
publish_and_verify "$CLASSIC_JOB_NAME"

cat <<EOF

${GREEN}${BOLD}
╔══════════════════════════════════════════════════════════════╗
║                    LAB SCRIPT COMPLETED                     ║
╚══════════════════════════════════════════════════════════════╝
${NC}
Project       : ${PROJECT_ID}
Region        : ${REGION}
BigQuery      : ${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}
Pub/Sub topic : ${TOPIC_NAME}
Flex job      : ${JOB_NAME}
Classic job   : ${CLASSIC_JOB_NAME}

You can now click "Check my progress" in the lab.
EOF