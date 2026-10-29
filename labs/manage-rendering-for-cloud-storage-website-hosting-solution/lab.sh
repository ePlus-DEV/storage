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
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | Storage Website Hosting (Solution)${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset

PROJECT=$(gcloud config get-value project) && BUCKET="$(gsutil ls -b | head -n 1 | sed 's#gs://##; s#/*$##')" && gsutil setmeta -h "Content-Type:text/html" gs://${BUCKET}/index.html && gsutil setmeta -h "Content-Type:text/css" gs://${BUCKET}/style.css && gsutil setmeta -h "Content-Type:image/jpeg" gs://${BUCKET}/logo.jpg && gsutil web set -m index.html -e 404.html gs://${BUCKET} && gsutil iam ch allUsers:objectViewer gs://${BUCKET}