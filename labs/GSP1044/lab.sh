#!/bin/bash

# ePlus.DEV console banner. Presentation only; see repository LICENSE (Unlicense).
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  _eplus_cyan=$'\033[1;36m'
  _eplus_yellow=$'\033[0;33m'
  _eplus_reset=$'\033[0m'
else
  _eplus_cyan='' _eplus_yellow='' _eplus_reset=''
fi
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | GSP1044 - Cloud Storage${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset


# Fetch zone and region
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud config get-value project)



gcloud services enable networkservices.googleapis.com
gcloud services enable certificatemanager.googleapis.com

# 1. Create the bucket
gsutil mb gs://$PROJECT_ID/

# 2. Remove Public Access Prevention
gsutil pap set unspecified gs://$PROJECT_ID/

# 3. Grant public read access to objects in the bucket
gsutil iam ch allUsers:objectViewer gs://$PROJECT_ID/