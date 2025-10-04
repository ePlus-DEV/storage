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

export PROJECT_ID=$(gcloud config get-value project)

gcloud services enable videointelligence.googleapis.com

gcloud iam service-accounts create quickstart

gcloud iam service-accounts keys create key.json --iam-account quickstart@$PROJECT_ID.iam.gserviceaccount.com

gcloud auth activate-service-account --key-file key.json

gcloud auth print-access-token

cat > request.json <<EOF
{
   "inputUri":"gs://spls/gsp154/video/train.mp4",
   "features": [
       "LABEL_DETECTION"
   ]
}
EOF

# Make annotate request
RESPONSE=$(curl -s -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://videointelligence.googleapis.com/v1/videos:annotate" \
  -d @request.json)

sleep 10

# Print the full operation name
OPERATION_NAME=$(echo "$RESPONSE" | grep -oP '"name":\s*"\K[^"]+')

export OPERATION_NAME

curl -s -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://videointelligence.googleapis.com/v1/$OPERATION_NAME"


echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#