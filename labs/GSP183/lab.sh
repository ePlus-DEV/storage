#!/bin/bash
# =====================================================================================
#  Google Cloud Qwiklabs Auto Setup Script
#  Author : ePlus.DEV
#  License: MIT (Educational / Lab purposes)
# =====================================================================================

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
echo ""
echo "${BG_MAGENTA}${BOLD} 🚀 Starting Google Cloud Lab Setup - ePlus.DEV ${RESET}"
echo ""

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)

# ---------------- Step 1: Create VM ---------------- #
echo "${CYAN}${BOLD}==> Creating VM instance 'dev-instance'...${RESET}"
gcloud compute instances create dev-instance \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --scopes=cloud-platform \
  --tags=http-server

echo "${GREEN}✅ VM created successfully.${RESET}"

# ---------------- Step 2: SSH + Setup ---------------- #
echo "${CYAN}${BOLD}==> Connecting to VM and running setup...${RESET}"

gcloud compute ssh dev-instance --zone=$ZONE --command '

  echo "=== [1] Update packages ==="
  sudo apt-get update -y

  echo "=== [2] Install Git ==="
  sudo apt-get install git -y

  echo "=== [3] Install Python & Build Tools ==="
  sudo apt-get install python3-setuptools python3-dev build-essential -y

  echo "=== [4] Install pip ==="
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  sudo python3 get-pip.py --break-system-packages

  echo "=== [5] Verify Python & pip ==="
  python3 --version
  pip3 --version

  echo "=== [6] Clone Google training repo ==="
  rm -rf training-data-analyst
  git clone https://github.com/GoogleCloudPlatform/training-data-analyst

  echo "=== [7] Run sample server (background) ==="
  cd training-data-analyst/courses/developingapps/python/devenv/
  sudo python3 server.py &
  sleep 10
  echo "🌐 Test in browser via VM External IP"

  echo "=== [8] Install Python requirements (ignore warnings) ==="
  sudo pip3 install -r requirements.txt --break-system-packages

  echo "=== [9] List Compute Engine Instances ==="
  PROJECT_ID=$(gcloud config get-value project)
  python3 list-gce-instances.py $PROJECT_ID --zone=$ZONE
'

# ---------------- Final Message ---------------- #
echo ""
echo "${BG_GREEN}${BOLD} 🎉 Lab Setup Completed Successfully - ePlus.DEV ${RESET}"
echo ""
