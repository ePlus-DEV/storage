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

git clone https://github.com/GoogleCloudPlatform/training-data-analyst

cd ~/training-data-analyst/courses/developingapps/nodejs/cloudstorage/start

. prepare_environment.sh

gsutil mb gs://$DEVSHELL_PROJECT_ID-media

export GCLOUD_BUCKET=$DEVSHELL_PROJECT_ID-media

cd ~/training-data-analyst/courses/developingapps/nodejs/cloudstorage/start/server/gcp

rm cloudstorage.js

##uploading files here

wget https://raw.githubusercontent.com/quiccklabs/Labs_solutions/refs/heads/master/App%20DevStoring%20Image%20and%20Video%20Files%20in%20Cloud%20Storage%20v11/cloudstorage.js

npm start

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#