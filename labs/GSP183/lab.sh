#!/bin/bash
# =====================================================================================
#  Google Cloud Qwiklabs Auto Setup Script
#  Author : ePlus.DEV
#  License: MIT (Educational / Lab purposes)
#  Lab    : Create VM + Install software + Run sample app
# =====================================================================================

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# ---------------- Colors ---------------- #
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)

BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---------------- Banner ---------------- #
clear
echo ""
echo "${BG_MAGENTA}${BOLD} 🚀 Starting Google Cloud Lab Setup - ePlus.DEV ${RESET}"
echo ""

# ---------------- Variables ---------------- #
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
INSTANCE_NAME="dev-instance"
MACHINE_TYPE="e2-medium"
IMAGE_FAMILY="debian-12"
IMAGE_PROJECT="debian-cloud"
FIREWALL_RULE="default-allow-http"

# ---------------- Validation ---------------- #
if [[ -z "${PROJECT_ID}" ]]; then
  echo "${BG_RED}${BOLD} ERROR: Could not detect PROJECT_ID from gcloud config. ${RESET}"
  exit 1
fi

echo "${CYAN}${BOLD}Project ID :${RESET} ${YELLOW}${PROJECT_ID}${RESET}"
echo "${CYAN}${BOLD}Region     :${RESET} ${YELLOW}${REGION}${RESET}"
echo "${CYAN}${BOLD}Zone       :${RESET} ${YELLOW}${ZONE}${RESET}"
echo "${CYAN}${BOLD}VM Name    :${RESET} ${YELLOW}${INSTANCE_NAME}${RESET}"
echo ""

# ---------------- Step 1: Ensure firewall allows HTTP ---------------- #
echo "${CYAN}${BOLD}==> Checking firewall rule for HTTP traffic on port 80...${RESET}"

if gcloud compute firewall-rules describe "${FIREWALL_RULE}" >/dev/null 2>&1; then
  echo "${GREEN}✅ Firewall rule '${FIREWALL_RULE}' already exists.${RESET}"
else
  echo "${YELLOW}⚠ Firewall rule '${FIREWALL_RULE}' not found. Creating it now...${RESET}"
  gcloud compute firewall-rules create "${FIREWALL_RULE}" \
    --network=default \
    --allow=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server
  echo "${GREEN}✅ Firewall rule '${FIREWALL_RULE}' created.${RESET}"
fi
echo ""

# ---------------- Step 2: Create VM ---------------- #
echo "${CYAN}${BOLD}==> Checking VM instance '${INSTANCE_NAME}'...${RESET}"

if gcloud compute instances describe "${INSTANCE_NAME}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "${GREEN}✅ VM '${INSTANCE_NAME}' already exists in zone ${ZONE}.${RESET}"
else
  echo "${CYAN}${BOLD}==> Creating VM instance '${INSTANCE_NAME}'...${RESET}"
  gcloud compute instances create "${INSTANCE_NAME}" \
    --zone="${ZONE}" \
    --machine-type="${MACHINE_TYPE}" \
    --image-family="${IMAGE_FAMILY}" \
    --image-project="${IMAGE_PROJECT}" \
    --scopes=cloud-platform \
    --tags=http-server
  echo "${GREEN}✅ VM '${INSTANCE_NAME}' created successfully.${RESET}"
fi
echo ""

# ---------------- Step 3: Wait for SSH ---------------- #
echo "${CYAN}${BOLD}==> Waiting for SSH service to become ready...${RESET}"
for i in {1..12}; do
  if gcloud compute ssh "${INSTANCE_NAME}" --zone="${ZONE}" --command="echo SSH_READY" >/dev/null 2>&1; then
    echo "${GREEN}✅ SSH is ready.${RESET}"
    break
  fi
  echo "${YELLOW}...retry ${i}/12${RESET}"
  sleep 5
done
echo ""

# ---------------- Step 4: Install software and run sample app ---------------- #
echo "${CYAN}${BOLD}==> Connecting to VM and configuring software...${RESET}"

gcloud compute ssh "${INSTANCE_NAME}" --zone="${ZONE}" --command "
set -e

echo '=== [1] Update package list ==='
sudo apt-get update -y

echo '=== [2] Install Git ==='
sudo apt-get install -y git

echo '=== [3] Install Python build dependencies ==='
sudo apt-get install -y python3-setuptools python3-dev build-essential

echo '=== [4] Install pip ==='
curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
sudo python3 /tmp/get-pip.py --break-system-packages

echo '=== [5] Verify Python & pip ==='
python3 --version
pip3 --version

echo '=== [6] Clone training repository ==='
rm -rf ~/training-data-analyst
git clone https://github.com/GoogleCloudPlatform/training-data-analyst ~/training-data-analyst

echo '=== [7] Go to app directory ==='
cd ~/training-data-analyst/courses/developingapps/python/devenv/

echo '=== [8] Start sample web server in background ==='
nohup sudo python3 server.py > /tmp/python-server.log 2>&1 &
sleep 10

echo '=== [9] Install Python requirements ==='
sudo pip3 install -r requirements.txt --break-system-packages

echo '=== [10] List Compute Engine instances ==='
python3 list-gce-instances.py ${PROJECT_ID} --zone=${ZONE}

echo '=== [11] Show server process ==='
ps -ef | grep server.py | grep -v grep || true
"
echo ""

# ---------------- Step 5: Show external IP ---------------- #
EXTERNAL_IP="$(gcloud compute instances describe "${INSTANCE_NAME}" --zone="${ZONE}" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"

echo "${CYAN}${BOLD}==> VM Summary${RESET}"
echo "${WHITE}Instance   : ${INSTANCE_NAME}${RESET}"
echo "${WHITE}Project ID : ${PROJECT_ID}${RESET}"
echo "${WHITE}Zone       : ${ZONE}${RESET}"
echo "${WHITE}External IP: ${EXTERNAL_IP}${RESET}"
echo ""

echo "${BG_GREEN}${BOLD} 🎉 Lab Setup Completed Successfully - ePlus.DEV ${RESET}"
echo ""
echo "${YELLOW}Open this in browser to verify app:${RESET} http://${EXTERNAL_IP}"
echo ""