#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`
#----------------------------------------------------start--------------------------------------------------#

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV ${RESET}"


gcloud auth list

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

export PROJECT_ID=$(gcloud config get-value project)

export PROJECT_ID=$DEVSHELL_PROJECT_ID

gcloud logging metrics create 200responses --description="subscribe to techcps" --log-filter='resource.type="gae_app" AND resource.labels.module_id="default" AND (protoPayload.status=200 OR httpRequest.status=200)'

cat > latency_metric.json <<EOF
{
  "name": "latency_metric",
  "description": "latency distribution",
  "filter": "resource.type=\"gae_app\" AND resource.labels.module_id=\"default\" AND logName=(\"projects/${DEVSHELL_PROJECT_ID}/logs/cloudbuild\" OR \"projects/${DEVSHELL_PROJECT_ID}/logs/stderr\" OR \"projects/${DEVSHELL_PROJECT_ID}/logs/%2Fvar%2Flog%2Fgoogle_init.log\" OR \"projects/${DEVSHELL_PROJECT_ID}/logs/appengine.googleapis.com%2Frequest_log\" OR \"projects/${DEVSHELL_PROJECT_ID}/logs/cloudaudit.googleapis.com%2Factivity\") AND severity>=DEFAULT",
  "valueExtractor": "EXTRACT(protoPayload.latency)",
  "metricDescriptor": {
    "metricKind": "DELTA",
    "valueType": "DISTRIBUTION",
    "unit": "s",
    "labels": []
  },
  "bucketOptions": {
    "explicitBuckets": {
      "bounds": [0.01, 0.1, 0.5, 1, 2, 5]
    }
  }
}
EOF

sleep 5

curl -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json" \
  -d @latency_metric.json \
  "https://logging.googleapis.com/v2/projects/${DEVSHELL_PROJECT_ID}/metrics"


gcloud compute instances create techcps --zone=$ZONE --project=$DEVSHELL_PROJECT_ID --machine-type=e2-micro --image-family=debian-11 --image-project=debian-cloud --tags=http-server --metadata=startup-script='#!/bin/bash sudo apt update && sudo apt install -y apache2 && sudo systemctl start apache2' --scopes=https://www.googleapis.com/auth/cloud-platform --labels=env=lab --quiet

gcloud logging sinks create AuditLogs --project=$DEVSHELL_PROJECT_ID bigquery.googleapis.com/projects/$PROJECT_ID/datasets/AuditLogs --log-filter='resource.type="gce_instance"'

bq --location=US mk --dataset ${DEVSHELL_PROJECT_ID}:AuditLogs

echo
echo "Click this link: {RED}${BOLD}https://console.cloud.google.com/appengine?serviceId=default&inv=1&invt=AbxmyA&project=$DEVSHELL_PROJECT_ID ${RESET}"
echo

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#