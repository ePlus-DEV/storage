#!/bin/bash
# ===================================================================================== #
#  Script: Create VM for "Speaking with a Webpage - Streaming Speech Transcripts" Lab   #
#  Author: ePlus.dev                                                                    #
#  License: © 2025 ePlus.dev. All rights reserved.                                      #
# ===================================================================================== #

# Màu sắc
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)
BOLD=$(tput bold)

# Config
VM_NAME="speaking-with-a-webpage"
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
MACHINE_TYPE="e2-medium"
IMAGE_FAMILY="debian-11"
IMAGE_PROJECT="debian-cloud"

echo "${CYAN}${BOLD}>>> [Step 1] Creating VM: $VM_NAME ...${RESET}"
gcloud compute instances create $VM_NAME \
  --zone=$ZONE \
  --machine-type=$MACHINE_TYPE \
  --image-family=$IMAGE_FAMILY \
  --image-project=$IMAGE_PROJECT \
  --scopes=cloud-platform \
  --tags=http-server,https-server

if [ $? -eq 0 ]; then
  echo "${GREEN}${BOLD}✔ VM created successfully!${RESET}"
else
  echo "${RED}${BOLD}✘ Failed to create VM!${RESET}"
  exit 1
fi

echo "${CYAN}${BOLD}>>> [Step 2] Getting External IP ...${RESET}"
EXTERNAL_IP=$(gcloud compute instances describe $VM_NAME \
  --zone=$ZONE \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "${YELLOW}${BOLD}Your VM External IP: ${RESET}${GREEN}$EXTERNAL_IP${RESET}"
echo "${CYAN}Access it later at: https://$EXTERNAL_IP:8443 ${RESET}"