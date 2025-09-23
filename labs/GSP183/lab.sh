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

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV${RESET}"


#!/bin/bash
# ============================
# Google Cloud Lab Setup Script
# Project: qwiklabs-gcp-bcdd9ef8f952
# Zone: europe-west4-a
# ============================

ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)

echo "=== Step 1: Update packages ==="
sudo apt-get update -y

echo "=== Step 2: Install Git ==="
sudo apt-get install git -y

echo "=== Step 3: Install Python and build tools ==="
sudo apt-get install python3-setuptools python3-dev build-essential -y

echo "=== Step 4: Install pip ==="
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
sudo python3 get-pip.py --break-system-packages

echo "=== Step 5: Verify Python and pip ==="
python3 --version
pip3 --version

echo "=== Step 6: Clone Google training repo ==="
git clone https://github.com/GoogleCloudPlatform/training-data-analyst

echo "=== Step 7: Move into sample app directory ==="
cd ~/training-data-analyst/courses/developingapps/python/devenv/ || exit 1

echo "=== Step 8: Run sample web server (Ctrl+C to stop manually) ==="
sudo python3 server.py &
sleep 10
echo "Server started in background. Test it using External IP of your VM."

echo "=== Step 9: Install Python requirements ==="
sudo pip3 install -r requirements.txt --break-system-packages

echo "=== Step 9b: Fix dependency conflicts (upgrade google-auth) ==="
sudo pip3 install --upgrade "google-auth>=2.14.1,<3.0.0" google-api-python-client --break-system-packages

echo "=== Step 10: List Compute Engine instances ==="
python3 list-gce-instances.py "$PROJECT_ID" --zone="$ZONE"

echo "=== All tasks completed successfully! ==="


echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#