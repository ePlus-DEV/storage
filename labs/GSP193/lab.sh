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

read -p "${YELLOW}${BOLD}Enter the ZONE_1: ${RESET}" ZONE_1
read -p "${YELLOW}${BOLD}Enter the PROJECT_ID1: ${RESET}" PROJECT_ID1
read -p "${YELLOW}${BOLD}Enter the ZONE_2: ${RESET}" ZONE_2
read -p "${YELLOW}${BOLD}Enter the PROJECT_ID2: ${RESET}" PROJECT_ID2


export REGION_1="${ZONE_1%-*}"

export REGION_2="${ZONE_2%-*}"



gcloud config set project $PROJECT_ID1


gcloud compute networks create network-a --subnet-mode custom

gcloud compute networks subnets create network-a-subnet --network network-a \
    --range 10.0.0.0/16 --region $REGION_1

sleep 5

gcloud compute instances create vm-a --zone $ZONE_1 --network network-a --subnet network-a-subnet --machine-type e2-small

gcloud compute firewall-rules create network-a-fw --network network-a --allow tcp:22,icmp



# Second terminal 
gcloud config set project $PROJECT_ID2


# Create the custom network
gcloud compute networks create network-b --subnet-mode custom


gcloud compute networks subnets create network-b-subnet --network network-b \
    --range 10.8.0.0/16 --region $REGION_2

sleep 5

gcloud compute instances create vm-b --zone $ZONE_2 --network network-b --subnet network-b-subnet --machine-type e2-small


gcloud compute firewall-rules create network-b-fw --network network-b --allow tcp:22,icmp


# First terminal 
gcloud config set project $PROJECT_ID1


gcloud compute networks peerings create peer-ab \
    --network=network-a \
    --peer-project=$PROJECT_ID2 \
    --peer-network=network-b 


# Second terminal 
gcloud config set project $PROJECT_ID2


gcloud compute networks peerings create peer-ba \
    --network=network-b \
    --peer-project=$PROJECT_ID1 \
    --peer-network=network-a



echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#