#!/usr/bin/env bash

# ePlus.DEV console banner. Presentation only; see repository LICENSE (Unlicense).
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  _eplus_cyan=$'\033[1;36m'
  _eplus_yellow=$'\033[0;33m'
  _eplus_reset=$'\033[0m'
else
  _eplus_cyan='' _eplus_yellow='' _eplus_reset=''
fi
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | Cloud Storage Mini Lab 1${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset

export PROJECT=$(gcloud projects list --format="value(PROJECT_ID)")

gcloud storage buckets update gs://$PROJECT-bucket --no-uniform-bucket-level-access

gcloud storage buckets update gs://$PROJECT-bucket --web-main-page-suffix=index.html --web-error-page=error.html

gcloud storage objects update gs://$PROJECT-bucket/index.html --add-acl-grant=entity=AllUsers,role=READER

gcloud storage objects update gs://$PROJECT-bucket/error.html --add-acl-grant=entity=AllUsers,role=READER