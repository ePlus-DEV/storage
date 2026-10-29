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
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | Custom VPC and Subnets${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset


gcloud compute firewall-rules list --filter="network=default" --format="value(name)" | xargs -r -I {} gcloud compute firewall-rules delete {} --quiet && \
gcloud compute networks delete default --quiet && \
gcloud compute networks create custom-vpc --subnet-mode=custom && \
gcloud compute networks subnets create custom-subnet-us --network=custom-vpc --region=us-central1 --range=10.0.1.0/24 && \
gcloud compute networks subnets create custom-subnet-asia --network=custom-vpc --region=asia-southeast1 --range=10.0.2.0/24