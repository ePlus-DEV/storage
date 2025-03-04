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

echo "${BG_MAGENTA}${BOLD}Starting Execution - Task 1 - ePlus.DEV ${RESET}"

gcloud compute addresses create psa-range \
  --global \
  --purpose=VPC_PEERING \
  --prefix-length=24 \
  --network=cloud-vpc \
  --addresses=10.8.12.0 \
  --description="Private Service Access range for AlloyDB"

gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --network=cloud-vpc \
  --ranges=psa-range

gcloud compute networks peerings update servicenetworking-googleapis-com \
  --network=cloud-vpc \
  --import-custom-routes \
  --export-custom-routes

gcloud compute networks peerings list --network=cloud-vpc

echo "${BG_RED}${BOLD}Congratulations For Completing - Task 1 !!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#
