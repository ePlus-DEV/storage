#!/bin/bash

# Define color variables
PURPLE_COLOR=$'\033[0;35m'
GOLD_COLOR=$'\033[0;33m'
TEAL_COLOR=$'\033[0;36m'
LIME_COLOR=$'\033[0;92m'
MAROON_COLOR=$'\033[0;91m'
NAVY_COLOR=$'\033[0;94m'
NO_COLOR=$'\033[0m'
BOLD_TEXT=`tput bold`
RESET_FORMAT=`tput sgr0`


echo "${PURPLE_COLOR}${BOLD_TEXT}=============================================${RESET_FORMAT}"
echo "${PURPLE_COLOR}${BOLD_TEXT}  ePlus.DEV  ${RESET_FORMAT}"
echo "${PURPLE_COLOR}${BOLD_TEXT}=============================================${RESET_FORMAT}"
echo

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Prompt the user for the message in gold bold color
echo -e "${GOLD_COLOR}${BOLD_TEXT}Enter the message: ${NO_COLOR}${RESET_FORMAT}"
read MESSAGE

# Set the ZONE variable
ZONE="$(gcloud compute instances list --project=$DEVSHELL_PROJECT_ID --format='value(ZONE)')"

# Enable the App Engine API
echo "${TEAL_COLOR}${BOLD_TEXT}Enabling App Engine API...${RESET_FORMAT}"
gcloud services enable appengine.googleapis.com

sleep 10

# SSH into the lab-setup instance and enable the App Engine API
echo "${LIME_COLOR}${BOLD_TEXT}Configuring lab setup instance...${RESET_FORMAT}"
gcloud compute ssh --zone "$ZONE" "lab-setup" --project "$DEVSHELL_PROJECT_ID" --quiet --command "gcloud services enable appengine.googleapis.com && git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git"

# Clone the sample repository
echo "${TEAL_COLOR}${BOLD_TEXT}Cloning sample repository...${RESET_FORMAT}"
git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git

# Navigate to the hello_world directory
cd python-docs-samples/appengine/standard_python3/hello_world

# Update the main.py file with the message
echo "${LIME_COLOR}${BOLD_TEXT}Updating application message...${RESET_FORMAT}"
sed -i "32c\    return \"$MESSAGE\"" main.py

# Check and update the REGION variable
if [ "$REGION" == "us-west" ]; then
  REGION="us-west1"
fi

# Create the App Engine app with the specified service account and region
echo "${NAVY_COLOR}${BOLD_TEXT}Creating App Engine application...${RESET_FORMAT}"
gcloud app create --service-account=$DEVSHELL_PROJECT_ID@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com --region=$REGION

# Deploy the App Engine app
echo "${TEAL_COLOR}${BOLD_TEXT}Deploying application...${RESET_FORMAT}"
gcloud app deploy --quiet

# SSH into the lab-setup instance again
echo "${LIME_COLOR}${BOLD_TEXT}Finalizing lab setup...${RESET_FORMAT}"
gcloud compute ssh --zone "$ZONE" "lab-setup" --project "$DEVSHELL_PROJECT_ID" --quiet --command "gcloud services enable appengine.googleapis.com && git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git"

# Completion message
echo
echo "${MAROON_COLOR}${BOLD_TEXT}=================================================${RESET_FORMAT}"
echo "${MAROON_COLOR}${BOLD_TEXT}        LAB COMPLETED SUCCESSFULLY!        ${RESET_FORMAT}"
echo "${MAROON_COLOR}${BOLD_TEXT}=================================================${RESET_FORMAT}"