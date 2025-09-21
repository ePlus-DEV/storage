#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLACK=`tput setaf 0`
GREEN=`tput setaf 2`
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
NC='\033[0m' # No Color

echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Copyright (c) 2025 ePlus.DEV${NC}"
echo -e "${CYAN}=====================================${NC}\n"


gsutil cp -R gs://spls/gsp1201/chat-flask-cloudrun .

cd chat-flask-cloudrun

export PROJECT_ID=$DEVSHELL_PROJECT_ID
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")


export AR_REPO='chat-app-repo'
export SERVICE_NAME='chat-flask-app'

gcloud artifacts repositories create "$AR_REPO" --location="$REGION" --repository-format=Docker

gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/$SERVICE_NAME"

gcloud run deploy "$SERVICE_NAME" --port=8080 --image="$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/$SERVICE_NAME:latest" --allow-unauthenticated --region=$REGION --platform=managed --project=$PROJECT_ID --set-env-vars=GCP_PROJECT=$PROJECT_ID,GCP_REGION=$REGION

echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Congratulations For Completing!!! - ePlus.DEV{NC}"
echo -e "${CYAN}=====================================${NC}\n"