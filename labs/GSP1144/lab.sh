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

gcloud services enable \
  dataplex.googleapis.com --project=$DEVSHELL_PROJECT_ID

gcloud dataplex lakes create ecommerce --location=$REGION --display-name="Ecommerce" --description="subscribe to techcps"

gcloud dataplex zones create orders-curated-zone --location=$REGION --lake=ecommerce --display-name="Orders Curated Zone" --resource-location-type=SINGLE_REGION --type=CURATED --discovery-enabled --discovery-schedule="0 * * * *"

bq mk --location=$REGION --dataset orders 

gcloud dataplex assets create orders-curated-dataset --location=$REGION --lake=ecommerce --zone=orders-curated-zone --display-name="Orders Curated Dataset" --resource-type=BIGQUERY_DATASET --resource-name=projects/$DEVSHELL_PROJECT_ID/datasets/orders --discovery-enabled 

gcloud dataplex assets delete orders-curated-dataset --location=$REGION --zone=orders-curated-zone --lake=ecommerce --quiet

gcloud dataplex zones delete orders-curated-zone --location=$REGION --lake=ecommerce --quiet

gcloud dataplex lakes delete ecommerce --location=$REGION --quiet

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#