
#!/bin/bash

# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'

# Define text formatting variables
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear

# Welcome message with Dr. Abhishek reference
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...  ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

# Set text styles
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Setting up environment...${RESET_FORMAT}"
echo "${BLUE_TEXT}ZONE: $ZONE${RESET_FORMAT}"

# Check authentication
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Checking authentication...${RESET_FORMAT}"
gcloud auth list

# Set project and compute settings
export PROJECT_ID=$(gcloud config get-value project)
export REGION=${ZONE%-*}

echo "${BLUE_TEXT}PROJECT_ID: $PROJECT_ID${RESET_FORMAT}"
echo "${BLUE_TEXT}REGION: $REGION${RESET_FORMAT}"

gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Downloading GKE monitoring tutorial...${RESET_FORMAT}"
gsutil cp gs://spls/gsp497/gke-monitoring-tutorial.zip .
unzip gke-monitoring-tutorial.zip

cd gke-monitoring-tutorial

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Creating GKE cluster and resources...${RESET_FORMAT}"
make create

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Validating the setup...${RESET_FORMAT}"
make validate

echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Cleaning up resources...${RESET_FORMAT}"
make teardown

# Final message with Dr. Abhishek references
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}        GKE MONITORING LAB COMPLETED SUCCESSFULLY!     ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}${BOLD_TEXT}Subscribe to our channel for more cloud tutorials:${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}https://eplus.dev${RESET_FORMAT}"