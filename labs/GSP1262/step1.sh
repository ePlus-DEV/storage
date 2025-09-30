#!/bin/bash
set -e

# Define color variables
BLACK=`tput setaf 0`; RED=`tput setaf 1`; GREEN=`tput setaf 2`; YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`; MAGENTA=`tput setaf 5`; CYAN=`tput setaf 6`; WHITE=`tput setaf 7`
BG_RED=`tput setab 1`; BG_GREEN=`tput setab 2`; BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`; BG_MAGENTA=`tput setab 5`; BG_CYAN=`tput setab 6`
BOLD=`tput bold`; RESET=`tput sgr0`

TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

banner () {
  local color=$1
  local msg=$2
  echo ""
  echo "${color}${BOLD}============================================================${RESET}"
  echo "${color}${BOLD}$msg${RESET}"
  echo "${color}${BOLD}============================================================${RESET}"
  echo ""
}

# 🚀 Start
banner "$RANDOM_BG_COLOR$RANDOM_TEXT_COLOR" "🚀 Starting Execution - ePlus.DEV"

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION="${ZONE%-*}"

gcloud services enable websecurityscanner.googleapis.com

gcloud compute addresses create xss-test-ip-address --region=$REGION

gcloud compute addresses describe xss-test-ip-address \
--region=$REGION --format="value(address)"

gcloud compute instances create xss-test-vm-instance \
--address=xss-test-ip-address --no-service-account \
--no-scopes --machine-type=e2-micro --zone=$ZONE \
--metadata=startup-script='apt-get update; apt-get install -y python3-flask'

gcloud compute firewall-rules create enable-wss-scan \
--direction=INGRESS --priority=1000 \
--network=default --action=ALLOW \
--rules=tcp:8080 --source-ranges=0.0.0.0/0

sleep 10

IP=$(gcloud compute instances describe xss-test-vm-instance --zone=$ZONE --project=$DEVSHELL_PROJECT_ID --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

gcloud alpha web-security-scanner scan-configs create --display-name=QwikLab-Explorers --starting-urls=http://$IP:8080

SCAN_CONFIG=$(gcloud alpha web-security-scanner scan-configs list --project=$DEVSHELL_PROJECT_ID --format="value(name)")

gcloud alpha web-security-scanner scan-runs start $SCAN_CONFIG

sleep 10

gcloud compute ssh xss-test-vm-instance --zone $ZONE --project=$DEVSHELL_PROJECT_ID --quiet --command "gsutil cp gs://cloud-training/GCPSEC-ScannerAppEngine/flask_code.tar  . && tar xvf flask_code.tar && python3 app.py"

banner "$BG_GREEN$WHITE" "🎉 Done! Check Cloud Run service URL above. - ePlus.DEV"