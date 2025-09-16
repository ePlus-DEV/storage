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

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Enable the Cloud Dataplex API
gcloud services enable dataplex.googleapis.com

sleep 10

# Create a lake
gcloud alpha dataplex lakes create sensors --location=$REGION

# Task 1 is completed
# Add a zone to your lake
gcloud alpha dataplex zones create temperature-raw-data --location=$REGION --lake=sensors --resource-location-type=SINGLE_REGION --type=RAW
gsutil mb -l $REGION gs://$DEVSHELL_PROJECT_ID

# Task 2 is completed
# Attach an asset to a zone
gcloud dataplex assets create measurements --location=$REGION --lake=sensors --zone=temperature-raw-data --resource-type=STORAGE_BUCKET --resource-name=projects/$DEVSHELL_PROJECT_ID/buckets/$DEVSHELL_PROJECT_ID

# Task 3 is completed
# Delete assets, zones, and lakes
gcloud dataplex assets delete measurements --zone=temperature-raw-data --location=$REGION --lake=sensors --quiet

gcloud dataplex zones delete temperature-raw-data --lake=sensors --location=$REGION --quiet

gcloud dataplex lakes delete sensors --location=$REGION --quiet

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#