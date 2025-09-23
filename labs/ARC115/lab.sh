#!/bin/bash

# Enhanced Color Definitions
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

# Special Formatting
NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'
BLINK_TEXT=$'\033[5m'
REVERSE_TEXT=$'\033[7m'

clear
# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}╔════════════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         CLOUD MONITORING CHALLENGE LAB TUTORIAL                 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}╚════════════════════════════════════════════════════════╝${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}   Learn more at: ${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${BLUE_TEXT}${BLINK_TEXT}⚡ Initializing Cloud Monitoring Configuration...${RESET_FORMAT}"
echo

# Section 1: Instance Configuration
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬ INSTANCE SETUP ▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}🖥️  Retrieving compute instance zone...${RESET_FORMAT}"
export ZONE=$(gcloud compute instances list --project=$DEVSHELL_PROJECT_ID --format='value(ZONE)' | head -n 1)
echo "${CYAN_TEXT}${REVERSE_TEXT} Zone: $ZONE ${RESET_FORMAT}"

echo "${WHITE_TEXT}${BOLD_TEXT}🆔 Fetching instance ID of apache-vm...${RESET_FORMAT}"
INSTANCE_ID=$(gcloud compute instances describe apache-vm --zone=$ZONE --format='value(id)')
echo "${CYAN_TEXT}${REVERSE_TEXT} Instance ID: $INSTANCE_ID ${RESET_FORMAT}"
echo

# Section 2: Monitoring Agent Setup
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬ MONITORING AGENT SETUP ▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}📦 Preparing monitoring agent installation script...${RESET_FORMAT}"
cat > cp_disk.sh <<'EOF_CP'
curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
sudo bash add-logging-agent-repo.sh --also-install

curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
sudo bash add-monitoring-agent-repo.sh --also-install

(cd /etc/stackdriver/collectd.d/ && sudo curl -O https://raw.githubusercontent.com/Stackdriver/stackdriver-agent-service-configs/master/etc/collectd.d/apache.conf)

sudo service stackdriver-agent restart
EOF_CP

echo "${MAGENTA_TEXT}${BOLD_TEXT}📤 Transferring script to apache-vm...${RESET_FORMAT}"
gcloud compute scp cp_disk.sh apache-vm:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Script transferred successfully!${RESET_FORMAT}"

echo "${MAGENTA_TEXT}${BOLD_TEXT}🚀 Executing script on apache-vm...${RESET_FORMAT}"
gcloud compute ssh apache-vm --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet --command="bash /tmp/cp_disk.sh"
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Monitoring agent setup completed!${RESET_FORMAT}"
echo

# Section 3: Uptime Check
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬ UPTIME CHECK ▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}⏱️  Creating uptime check for the instance...${RESET_FORMAT}"
gcloud monitoring uptime create arcadecrew \
  --resource-type="gce-instance" \
  --resource-labels=project_id=$DEVSHELL_PROJECT_ID,instance_id=$INSTANCE_ID,zone=$ZONE
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Uptime check created successfully!${RESET_FORMAT}"
echo

# Section 4: Notification Channel
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬ NOTIFICATION CHANNEL ▬▬▬▬▬${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}📧 Creating email notification channel...${RESET_FORMAT}"
cat > email-channel.json <<EOF_CP
{
  "type": "email",
  "displayName": "arcadecrew",
  "description": "Arcade Crew",
  "labels": {
    "email_address": "$USER_EMAIL"
  }
}
EOF_CP

gcloud beta monitoring channels create --channel-content-from-file="email-channel.json"
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Notification channel created!${RESET_FORMAT}"
echo

# Section 5: Alert Policy
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬ ALERT POLICY ▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}🚨 Creating alert policy...${RESET_FORMAT}"
channel_info=$(gcloud beta monitoring channels list)
channel_id=$(echo "$channel_info" | grep -oP 'name: \K[^ ]+' | head -n 1)

cat > app-engine-error-percent-policy.json <<EOF_CP
{
  "displayName": "alert",
  "userLabels": {},
  "conditions": [
    {
      "displayName": "VM Instance - Traffic",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"agent.googleapis.com/apache/traffic\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "crossSeriesReducer": "REDUCE_NONE",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ],
        "comparison": "COMPARISON_GT",
        "duration": "300s",
        "trigger": {
          "count": 1
        },
        "thresholdValue": 3072
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
    "$channel_id"
  ],
  "severity": "SEVERITY_UNSPECIFIED"
}
EOF_CP

gcloud alpha monitoring policies create --policy-from-file="app-engine-error-percent-policy.json"
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Alert policy created successfully!${RESET_FORMAT}"
echo

# Section 6: Quick Links
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬ QUICK LINKS ▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}📊 Dashboard: ${YELLOW_TEXT}${UNDERLINE_TEXT}https://console.cloud.google.com/monitoring/dashboards?&project=$DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}📈 Metrics: ${YELLOW_TEXT}${UNDERLINE_TEXT}https://console.cloud.google.com/logs/metrics/edit?project=$DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo

# Completion Banner
echo "${GREEN_TEXT}${BOLD_TEXT}╔════════════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}          LAB  COMPLETE!                    ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}╚════════════════════════════════════════════════════════╝${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}👁️  Happy monitoring with Google Cloud!${RESET_FORMAT}"