#!/bin/bash
set -euo pipefail

# ========================= COLOR + BRAND =========================
ROYAL_BLUE=$'\033[38;5;27m'
NEON_GREEN=$'\033[38;5;46m'
ORANGE=$'\033[38;5;208m'
YELLOW=$'\033[38;5;226m'
RED=$'\033[38;5;196m'
WHITE=$'\033[1;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear
echo "${ROYAL_BLUE}${BOLD}============================================================${RESET}"
echo "${NEON_GREEN}${BOLD}   Apache Beam (Python) + Dataflow Lab Automation${RESET}"
echo "${WHITE}${BOLD}   Copyright (c) ePlus.DEV${RESET}"
echo "${ROYAL_BLUE}${BOLD}============================================================${RESET}"
echo

die() { echo "${RED}${BOLD}✖ $*${RESET}" >&2; exit 1; }
info() { echo "${YELLOW}${BOLD}➜ $*${RESET}"; }
ok()   { echo "${NEON_GREEN}${BOLD}✔ $*${RESET}"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
need_cmd gcloud
need_cmd gsutil
need_cmd python3
need_cmd pip

# ========================= VARS =========================
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "${PROJECT_ID}" ]] || die "Cannot detect Project ID (gcloud config)."

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
BUCKET_NAME="${PROJECT_ID}-bucket"
BUCKET_URI="gs://${BUCKET_NAME}"
REMOTE_OUT_PREFIX="${BUCKET_URI}/results/output"

echo "${WHITE}${BOLD}Project:${RESET} ${PROJECT_ID}"
echo "${WHITE}${BOLD}Region :${RESET} ${REGION}"
echo "${WHITE}${BOLD}Bucket :${RESET} ${BUCKET_URI}"
echo

# ========================= TASK: SET REGION =========================
info "Setting compute region to ${REGION}"
gcloud config set compute/region "${REGION}" >/dev/null
ok "Region set"

# ========================= TASK: RESTART DATAFLOW API =========================
info "Restarting Dataflow API (disable -> enable)"
gcloud services disable dataflow.googleapis.com --quiet >/dev/null 2>&1 || true
gcloud services enable  dataflow.googleapis.com --quiet >/dev/null
ok "Dataflow API enabled"

# ========================= TASK 1: CREATE BUCKET =========================
info "Task 1: Creating Cloud Storage bucket (Multi-region: US): ${BUCKET_NAME}"
if gsutil ls -b "${BUCKET_URI}" >/dev/null 2>&1; then
  ok "Bucket already exists: ${BUCKET_URI}"
else
  gsutil mb -l US -c STANDARD "${BUCKET_URI}" >/dev/null
  ok "Bucket created: ${BUCKET_URI}"
fi

# ========================= TASK 2: INSTALL APACHE BEAM =========================
info "Task 2: Installing Apache Beam SDK for Python (apache-beam[gcp]==2.67.0)"
python3 -m pip install --user -q "apache-beam[gcp]==2.67.0" || die "pip install failed"
ok "Apache Beam installed"
export PATH="$HOME/.local/bin:$PATH"

# ========================= TASK 2: RUN WORDCOUNT LOCALLY =========================
info "Task 2: Running wordcount example locally (DirectRunner)"
LOCAL_OUT="local_output_$(date +%s)"
python3 -m apache_beam.examples.wordcount --output "${LOCAL_OUT}" >/dev/null 2>&1 || die "Local wordcount failed"
ok "Local wordcount done: ${LOCAL_OUT}*"

echo
echo "${ORANGE}${BOLD}--- Local result preview (first 20 lines) ---${RESET}"
for f in ${LOCAL_OUT}*; do
  [[ -f "$f" ]] || continue
  echo "${WHITE}${BOLD}FILE:${RESET} $f"
  head -n 20 "$f" || true
done
echo "${ORANGE}${BOLD}--------------------------------------------${RESET}"
echo

# ========================= TASK 3: RUN WORDCOUNT ON DATAFLOW =========================
info "Task 3: Submitting wordcount job to Dataflow (DataflowRunner)"
SUBMIT_LOG="/tmp/dataflow_submit_$$.log"

python3 -m apache_beam.examples.wordcount \
  --project "${PROJECT_ID}" \
  --runner DataflowRunner \
  --staging_location "${BUCKET_URI}/staging" \
  --temp_location "${BUCKET_URI}/temp" \
  --output "${REMOTE_OUT_PREFIX}" \
  --region "${REGION}" \
  2>&1 | tee "${SUBMIT_LOG}"

# Parse job id from logs (Beam usually prints something like: job: <id> or jobId: <id>)
JOB_ID="$(grep -Eo '[a-f0-9]{20,}' "${SUBMIT_LOG}" | head -n1 || true)"

# Fallback: query latest job in region
if [[ -z "${JOB_ID}" ]]; then
  info "Could not parse JOB_ID from output, trying to discover latest job in region..."
  JOB_ID="$(gcloud dataflow jobs list --region "${REGION}" --format="value(JOB_ID)" --limit=1 2>/dev/null || true)"
fi

[[ -n "${JOB_ID}" ]] || die "Cannot determine Dataflow JOB_ID. Open Dataflow UI to check."
ok "Dataflow job id: ${JOB_ID}"

# ========================= TASK 4: WAIT FOR SUCCEEDED + CHECK OUTPUT =========================
info "Task 4: Waiting for job to finish (polling status)..."
while true; do
  STATE="$(gcloud dataflow jobs describe "${JOB_ID}" --region "${REGION}" --format="value(currentState)" 2>/dev/null || true)"
  [[ -n "${STATE}" ]] || STATE="(unknown)"
  echo -e "${WHITE}${BOLD}Current state:${RESET} ${STATE}"

  case "${STATE}" in
    JOB_STATE_DONE|JOB_STATE_SUCCEEDED|JOB_STATE_SUCCESS)
      ok "Job finished successfully: ${STATE}"
      break
      ;;
    JOB_STATE_FAILED|JOB_STATE_CANCELLED|JOB_STATE_UPDATED|JOB_STATE_DRAINED|JOB_STATE_STOPPED)
      die "Job ended but not successful: ${STATE} (check Dataflow logs/UI)"
      ;;
    *)
      sleep 15
      ;;
  esac
done

info "Task 4: Verifying output files in Cloud Storage: ${REMOTE_OUT_PREFIX}*"
gsutil ls "${REMOTE_OUT_PREFIX}"* >/dev/null 2>&1 || die "No output found in ${REMOTE_OUT_PREFIX}*"

ok "Output files found:"
gsutil ls "${REMOTE_OUT_PREFIX}"* | sed 's/^/ - /'

echo
echo "${ORANGE}${BOLD}--- Remote output preview (first 30 lines of first shard) ---${RESET}"
FIRST_SHARD="$(gsutil ls "${REMOTE_OUT_PREFIX}"* | head -n1)"
gsutil cat "${FIRST_SHARD}" | head -n 30 || true
echo "${ORANGE}${BOLD}-----------------------------------------------------------${RESET}"
echo

echo "${NEON_GREEN}${BOLD}============================================================${RESET}"
echo "${NEON_GREEN}${BOLD}ALL TASKS DONE (1→4).${RESET} Now click ${WHITE}${BOLD}Check my progress${RESET}."
echo "${WHITE}${BOLD}Bucket:${RESET} ${BUCKET_URI}"
echo "${WHITE}${BOLD}Results prefix:${RESET} ${REMOTE_OUT_PREFIX}*"
echo "${WHITE}${BOLD}Copyright:${RESET} ePlus.DEV"
echo "${NEON_GREEN}${BOLD}============================================================${RESET}"
echo

echo "${YELLOW}${BOLD}Lab quiz (Task 5):${RESET} Dataflow temp_location must be a valid Cloud Storage URL => ${NEON_GREEN}${BOLD}True${RESET}"