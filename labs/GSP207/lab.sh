#!/bin/bash
set -euo pipefail

# ========================= COLORS =========================
BLUE=$'\033[1;34m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
WHITE=$'\033[1;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear
echo "${BLUE}${BOLD}============================================================${RESET}"
echo "${GREEN}${BOLD}   Apache Beam (Python) + Dataflow Lab Script${RESET}"
echo "${WHITE}${BOLD}   Copyright (c) ePlus.DEV${RESET}"
echo "${BLUE}${BOLD}============================================================${RESET}"
echo

# ========================= VARIABLES =========================
PROJECT_ID="$(gcloud config get-value project)"
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
BUCKET_NAME="${PROJECT_ID}-bucket"
BUCKET_URI="gs://${BUCKET_NAME}"

DATAFLOW_JOBS_URL="https://console.cloud.google.com/dataflow/jobs?project=${PROJECT_ID}&region=${REGION}"
STORAGE_RESULTS_URL="https://console.cloud.google.com/storage/browser/${BUCKET_NAME}/results?project=${PROJECT_ID}"

echo "${WHITE}${BOLD}Project:${RESET} ${PROJECT_ID}"
echo "${WHITE}${BOLD}Region :${RESET} ${REGION}"
echo "${WHITE}${BOLD}Bucket :${RESET} ${BUCKET_URI}"
echo

# ========================= SET REGION =========================
gcloud config set compute/region "${REGION}" >/dev/null

# ========================= ENABLE DATAFLOW API =========================
gcloud services disable dataflow.googleapis.com --quiet >/dev/null 2>&1 || true
gcloud services enable  dataflow.googleapis.com --quiet >/dev/null

# ========================= TASK 1: CREATE BUCKET =========================
if ! gsutil ls -b "${BUCKET_URI}" >/dev/null 2>&1; then
  gsutil mb -l US -c STANDARD "${BUCKET_URI}"
fi

# ========================= TASK 2: INSTALL APACHE BEAM =========================
python3 -m pip install --user -q "apache-beam[gcp]==2.67.0"
export PATH="$HOME/.local/bin:$PATH"

# ========================= TASK 2: RUN WORDCOUNT LOCALLY =========================
LOCAL_OUT="local_output_$(date +%s)"
python3 -m apache_beam.examples.wordcount --output "${LOCAL_OUT}" >/dev/null 2>&1

# ========================= TASK 3: RUN WORDCOUNT ON DATAFLOW =========================
python3 -m apache_beam.examples.wordcount \
  --project "${PROJECT_ID}" \
  --runner DataflowRunner \
  --staging_location "${BUCKET_URI}/staging" \
  --temp_location "${BUCKET_URI}/temp" \
  --output "${BUCKET_URI}/results/output" \
  --region "${REGION}"

# ========================= TASK 4: DIRECT CONSOLE LINKS =========================
echo
echo "${BLUE}${BOLD}====================== TASK 4 ======================${RESET}"
echo "${WHITE}${BOLD}Open Dataflow Jobs:${RESET}"
echo "${GREEN}${DATAFLOW_JOBS_URL}${RESET}"
echo
echo "${WHITE}${BOLD}Open Cloud Storage Results:${RESET}"
echo "${GREEN}${STORAGE_RESULTS_URL}${RESET}"
echo "${BLUE}${BOLD}====================================================${RESET}"
echo

echo "${YELLOW}${BOLD}→ Open Dataflow and wait until the job status is SUCCEEDED${RESET}"
echo "${YELLOW}${BOLD}→ Then click Check my progress${RESET}"