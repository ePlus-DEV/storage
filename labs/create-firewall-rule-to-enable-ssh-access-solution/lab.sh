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
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | SSH Firewall Rule${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset


VPC=$(gcloud compute instances describe $(gcloud compute instances list --format="value(name)") --zone=$(gcloud compute instances list --format="value(zone)") --format="value(networkInterfaces[0].network.basename())"); gcloud compute firewall-rules create allow-ssh --network=$VPC --allow=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=http-server # drabhishek ji ka code copy karta hu mai
