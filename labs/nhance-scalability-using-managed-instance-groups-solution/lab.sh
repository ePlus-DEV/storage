#!/bin/bash

# =======================
#  ePlus.DEV - Qwiklabs
# =======================

# Define color variables
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
ORANGE_TEXT=$'\033[38;5;214m'

echo "${MAGENTA_TEXT}${BOLD_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}Enhance Scalability Using Managed Instance Groups
${RESET_FORMAT}"
echo "${YELLOW_TEXT}© Copyright ePlus.DEV${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_FORMAT}"


# Require REGION input if empty
if [[ -z "${REGION}" ]]; then
  echo "${RED_TEXT}${BOLD_TEXT}⚠️  REGION is not set!${RESET_FORMAT}"
  read -p "${ORANGE_TEXT}${BOLD_TEXT}Enter REGION (example: us-east4): ${RESET_FORMAT}" REGION
fi

gcloud compute instance-templates describe dev-instance-template \
  --format="value(properties.machineType)"

gcloud compute instance-groups managed create dev-instance-group \
  --base-instance-name=dev-instance \
  --template=dev-instance-template \
  --size=1 \
  --zone="$ZONE"

gcloud compute instance-groups managed set-autoscaling dev-instance-group \
  --zone="$ZONE" \
  --min-num-replicas=1 \
  --max-num-replicas=3 \
  --target-cpu-utilization=0.60 \
  --cool-down-period=60

gcloud compute instance-groups managed describe dev-instance-group \
  --zone="$ZONE" \
  --format="yaml(name,instanceTemplate,targetSize,autoscaler)"

echo "${GREEN_TEXT}${BOLD_TEXT}🎉 DONE!${RESET_FORMAT}"
echo "${YELLOW_TEXT}© ePlus.DEV${RESET_FORMAT}"