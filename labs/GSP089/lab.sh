#!/bin/bash

# =========================================================
# Google Cloud Monitoring LAMP Qwik Start Automation
# Powered by ePlus.DEV
# =========================================================

set -e

# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'

# Define text formatting variables
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear

echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}     STARTING THE LAB - GET READY      ${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="europe-west4"
ZONE="europe-west4-c"
VM_NAME="lamp-1-vm"
UPTIME_NAME="lamp-uptime-check"
POLICY_FILE="alert-policy.json"
UPTIME_FILE="uptime-check.json"

if [[ -z "$PROJECT_ID" ]]; then
  echo "${RED_TEXT}${BOLD_TEXT}ERROR: Unable to detect PROJECT_ID.${RESET_FORMAT}"
  exit 1
fi

echo "${CYAN_TEXT}${BOLD_TEXT}Project ID: ${PROJECT_ID}${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}Region: ${REGION}${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}Zone: ${ZONE}${RESET_FORMAT}"

echo "${YELLOW_TEXT}${BOLD_TEXT}Setting default region and zone...${RESET_FORMAT}"
gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE" >/dev/null

echo "${CYAN_TEXT}${BOLD_TEXT}Creating VM instance... Please wait.${RESET_FORMAT}"

if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}${BOLD_TEXT}VM ${VM_NAME} already exists. Skipping creation.${RESET_FORMAT}"
else
  gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced
fi

echo "${YELLOW_TEXT}${BOLD_TEXT}Creating firewall rule to allow HTTP traffic...${RESET_FORMAT}"

if gcloud compute firewall-rules describe allow-http >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}${BOLD_TEXT}Firewall rule allow-http already exists. Skipping.${RESET_FORMAT}"
else
  gcloud compute firewall-rules create allow-http \
    --project="$PROJECT_ID" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server
fi

echo "${MAGENTA_TEXT}${BOLD_TEXT}Waiting for VM to become ready...${RESET_FORMAT}"
sleep 20

echo "${CYAN_TEXT}${BOLD_TEXT}Generating SSH configuration...${RESET_FORMAT}"
gcloud compute config-ssh --project "$PROJECT_ID" --quiet >/dev/null 2>&1 || true

echo "${CYAN_TEXT}${BOLD_TEXT}Installing Apache, PHP and Google Cloud Ops Agent...${RESET_FORMAT}"
gcloud compute ssh "$VM_NAME" --project "$PROJECT_ID" --zone "$ZONE" --command "
  sudo apt-get update &&
  sudo apt-get install -y apache2 php curl &&
  sudo systemctl enable apache2 &&
  sudo systemctl restart apache2 &&
  curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh &&
  sudo bash add-google-cloud-ops-agent-repo.sh --also-install
"

echo "${MAGENTA_TEXT}${BOLD_TEXT}Waiting for Ops Agent metrics to initialize...${RESET_FORMAT}"
sleep 30

echo "${GREEN_TEXT}${BOLD_TEXT}Fetching VM information...${RESET_FORMAT}"
INSTANCE_ID="$(gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --format='value(id)')"
VM_IP="$(gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"

echo "${GREEN_TEXT}${BOLD_TEXT}Instance ID: ${INSTANCE_ID}${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}External IP: ${VM_IP}${RESET_FORMAT}"

echo "${BLUE_TEXT}${BOLD_TEXT}Creating Uptime Check Config...${RESET_FORMAT}"

cat > "$UPTIME_FILE" <<EOF
{
  "displayName": "Lamp Uptime Check",
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "host": "$VM_IP"
    }
  },
  "httpCheck": {
    "path": "/",
    "port": 80
  },
  "timeout": "10s",
  "period": "60s"
}
EOF

ACCESS_TOKEN="$(gcloud auth print-access-token)"

if gcloud monitoring uptime list-configs --project="$PROJECT_ID" | grep -q "Lamp Uptime Check"; then
  echo "${YELLOW_TEXT}${BOLD_TEXT}Uptime check already exists. Skipping creation.${RESET_FORMAT}"
else
  curl -s -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/uptimeCheckConfigs" \
    -d @"$UPTIME_FILE" >/dev/null
  echo "${GREEN_TEXT}${BOLD_TEXT}Uptime check created successfully.${RESET_FORMAT}"
fi

echo "${MAGENTA_TEXT}${BOLD_TEXT}Creating alert policy for network traffic...${RESET_FORMAT}"

cat > "$POLICY_FILE" <<EOF
{
  "displayName": "Inbound Traffic Alert",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "High Network Traffic",
      "conditionThreshold": {
        "filter": "metric.type=\"agent.googleapis.com/interface/traffic\" resource.type=\"gce_instance\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 500,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "enabled": true
}
EOF

if gcloud monitoring policies list --format="value(displayName)" | grep -q "^Inbound Traffic Alert$"; then
  echo "${YELLOW_TEXT}${BOLD_TEXT}Alert policy already exists. Skipping creation.${RESET_FORMAT}"
else
  gcloud monitoring policies create --policy-from-file="$POLICY_FILE"
fi

echo
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}              LAB COMPLETED SUCCESSFULLY!              ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}Project ID : ${PROJECT_ID}${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}VM Name    : ${VM_NAME}${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}External IP: ${VM_IP}${RESET_FORMAT}"
echo
echo "${BLUE_TEXT}${UNDERLINE_TEXT}http://${VM_IP}${RESET_FORMAT}"
echo
echo
echo
echo
echo
echo
echo "${BLUE_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"