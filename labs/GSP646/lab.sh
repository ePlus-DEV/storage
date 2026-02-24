
#!/bin/bash
# ================= PAPA KO NAMSTEY BOLO BETA COPY KARNE TO AGYE =================

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

# ================= START =================

clear

echo "${BG_BLUE}${WHITE}${BOLD}=====================================================${RESET}"
echo "${BG_BLUE}${WHITE}${BOLD}        🚀 Welcome to ePlus.DEV 🚀        ${RESET}"
echo "${BG_BLUE}${WHITE}${BOLD}   Google Cloud Automated Resource Cleanup Lab       ${RESET}"
echo "${BG_BLUE}${WHITE}${BOLD}=====================================================${RESET}"
echo ""

echo "${BG_MAGENTA}${WHITE}${BOLD}Starting Execution... Please wait...${RESET}"
echo ""

# ================= FETCH PROJECT INFO =================

export ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")

export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")

export PROJECT_ID=$(gcloud config list --format 'value(core.project)' 2>/dev/null)

# ================= ENABLE REQUIRED SERVICES =================

gcloud services enable cloudscheduler.googleapis.com
gcloud services enable run.googleapis.com

# ================= CLONE REPOSITORY =================

git clone https://github.com/GoogleCloudPlatform/gcf-automated-resource-cleanup.git
cd gcf-automated-resource-cleanup/

WORKDIR=$(pwd)
cd $WORKDIR/unused-ip

# ================= CREATE STATIC IPs =================

export USED_IP=used-ip-address
export UNUSED_IP=unused-ip-address

gcloud compute addresses create $USED_IP --project=$PROJECT_ID --region=$REGION
gcloud compute addresses create $UNUSED_IP --project=$PROJECT_ID --region=$REGION

gcloud compute addresses list --filter="region:($REGION)"

# ================= CREATE VM WITH USED IP =================

export USED_IP_ADDRESS=$(gcloud compute addresses describe $USED_IP \
--region=$REGION --format=json | jq -r '.address')

gcloud compute instances create static-ip-instance \
--zone=$ZONE \
--machine-type=e2-medium \
--subnet=default \
--address=$USED_IP_ADDRESS

gcloud compute addresses list --filter="region:($REGION)"

# ================= RESET & ENABLE CLOUD FUNCTIONS =================

gcloud services disable cloudfunctions.googleapis.com
sleep 5
gcloud services enable cloudfunctions.googleapis.com

# ================= IAM ROLE =================

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$PROJECT_ID@appspot.gserviceaccount.com" \
--role="roles/artifactregistry.reader"

sleep 60

# ================= DEPLOY FUNCTION =================

gcloud functions deploy unused_ip_function \
    --runtime nodejs20 \
    --region $REGION \
    --trigger-http \
    --allow-unauthenticated

export FUNCTION_URL=$(gcloud functions describe unused_ip_function \
--region=$REGION --format=json | jq -r '.url')

# ================= CREATE APP ENGINE =================

gcloud app create --region $REGION

# ================= CREATE SCHEDULER JOB =================

gcloud scheduler jobs create http unused-ip-job \
--schedule="* 2 * * *" \
--uri=$FUNCTION_URL \
--location=$REGION

sleep 30

# ================= RUN JOB (1st Time) =================

gcloud scheduler jobs run unused-ip-job \
--location=$REGION

gcloud compute addresses list --filter="region:($REGION)"

sleep 30

# ================= RUN JOB (2nd Time) =================

gcloud scheduler jobs run unused-ip-job \
--location=$REGION

# ================= END MESSAGE =================

echo ""
echo "${BG_GREEN}${WHITE}${BOLD}Congratulations For Completing The Lab !!!${RESET}"
echo ""

echo "${BG_RED}${WHITE}${BOLD}=====================================================${RESET}"
echo "${BG_RED}${WHITE}${BOLD}  https://eplus.dev     ${RESET}"
echo "${BG_RED}${WHITE}${BOLD}=====================================================${RESET}"
echo ""

# ================= END =================