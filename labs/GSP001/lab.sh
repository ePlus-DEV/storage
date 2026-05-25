#!/bin/bash

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
BOLD_TEXT=$'\033[1m'
RESET_FORMAT=$'\033[0m'

clear

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}        ePlus.DEV - Compute Engine Lab Full Script          ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

#------------------------------------------------------------
# Required variables
#------------------------------------------------------------
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export VM_1="gcelab"
export VM_2="gcelab2"
export MACHINE_TYPE="e2-medium"

echo "${YELLOW_TEXT}${BOLD_TEXT}[1/7] Setting default region and zone...${RESET_FORMAT}"
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${ZONE}"

echo
echo "${GREEN_TEXT}Region: ${REGION}${RESET_FORMAT}"
echo "${GREEN_TEXT}Zone  : ${ZONE}${RESET_FORMAT}"
echo

#------------------------------------------------------------
# Skip enable API because Qwiklabs student account may not have permission
#------------------------------------------------------------
echo "${YELLOW_TEXT}${BOLD_TEXT}[2/7] Checking Compute Engine access...${RESET_FORMAT}"
if gcloud compute zones list --filter="name=${ZONE}" --format="value(name)" | grep -q "${ZONE}"; then
  echo "${GREEN_TEXT}Compute Engine is accessible.${RESET_FORMAT}"
else
  echo "${RED_TEXT}Compute Engine is not accessible. Please wait a moment and try again.${RESET_FORMAT}"
  exit 1
fi

#------------------------------------------------------------
# Create firewall rule for HTTP
#------------------------------------------------------------
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}[3/7] Creating firewall rule for HTTP traffic...${RESET_FORMAT}"

if gcloud compute firewall-rules describe allow-http --quiet >/dev/null 2>&1; then
  echo "${GREEN_TEXT}Firewall rule allow-http already exists.${RESET_FORMAT}"
else
  gcloud compute firewall-rules create allow-http \
    --allow=tcp:80 \
    --target-tags=http-server \
    --description="Allow HTTP traffic on port 80"
fi

#------------------------------------------------------------
# Create first VM: gcelab
#------------------------------------------------------------
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}[4/7] Creating VM instance: ${VM_1}...${RESET_FORMAT}"

if gcloud compute instances describe "${VM_1}" --zone="${ZONE}" --quiet >/dev/null 2>&1; then
  echo "${GREEN_TEXT}VM ${VM_1} already exists.${RESET_FORMAT}"
else
  gcloud compute instances create "${VM_1}" \
    --zone="${ZONE}" \
    --machine-type="${MACHINE_TYPE}" \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --tags=http-server
fi

# Make sure HTTP tag exists
echo "${YELLOW_TEXT}Adding http-server tag to ${VM_1}...${RESET_FORMAT}"
gcloud compute instances add-tags "${VM_1}" \
  --zone="${ZONE}" \
  --tags=http-server \
  --quiet

#------------------------------------------------------------
# Install NGINX on gcelab
#------------------------------------------------------------
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}[5/7] Installing and starting NGINX on ${VM_1}...${RESET_FORMAT}"

gcloud compute ssh "${VM_1}" \
  --zone="${ZONE}" \
  --quiet \
  --command='
    set -e

    echo "Fixing possible Debian bullseye-backports 404 issue..."

    sudo sed -i "/bullseye-backports/d" /etc/apt/sources.list || true

    if ls /etc/apt/sources.list.d/*.list >/dev/null 2>&1; then
      sudo sed -i "/bullseye-backports/d" /etc/apt/sources.list.d/*.list || true
    fi

    if ls /etc/apt/sources.list.d/*.sources >/dev/null 2>&1; then
      sudo sed -i "/bullseye-backports/d" /etc/apt/sources.list.d/*.sources || true
    fi

    sudo apt-get clean
    sudo apt-get update

    sudo apt-get install -y nginx
    sudo systemctl enable nginx
    sudo systemctl restart nginx

    echo "NGINX process:"
    ps auwx | grep nginx | grep -v grep

    echo "HTTP local test:"
    curl -I http://localhost
  '

#------------------------------------------------------------
# Create second VM: gcelab2
#------------------------------------------------------------
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}[6/7] Creating VM instance: ${VM_2}...${RESET_FORMAT}"

if gcloud compute instances describe "${VM_2}" --zone="${ZONE}" --quiet >/dev/null 2>&1; then
  echo "${GREEN_TEXT}VM ${VM_2} already exists.${RESET_FORMAT}"
else
  gcloud compute instances create "${VM_2}" \
    --machine-type="${MACHINE_TYPE}" \
    --zone="${ZONE}"
fi

#------------------------------------------------------------
# Final check
#------------------------------------------------------------
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}[7/7] Getting VM information...${RESET_FORMAT}"

GCELAB_IP=$(gcloud compute instances describe "${VM_1}" \
  --zone="${ZONE}" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

GCELAB2_IP=$(gcloud compute instances describe "${VM_2}" \
  --zone="${ZONE}" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}Lab setup completed!${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

echo "${YELLOW_TEXT}${VM_1} External IP : ${GREEN_TEXT}${GCELAB_IP}${RESET_FORMAT}"
echo "${YELLOW_TEXT}${VM_2} External IP : ${GREEN_TEXT}${GCELAB2_IP}${RESET_FORMAT}"
echo

echo "${CYAN_TEXT}${BOLD_TEXT}Open this URL to verify NGINX:${RESET_FORMAT}"
echo "${GREEN_TEXT}http://${GCELAB_IP}/${RESET_FORMAT}"
echo

echo "${MAGENTA_TEXT}${BOLD_TEXT}Now click Check my progress.${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}Powered by ePlus.DEV${RESET_FORMAT}"