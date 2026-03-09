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

echo "${YELLOW}${BOLD}Starting${RESET}" "${GREEN}${BOLD}Execution - ePlus.DEV${RESET}"



gcloud compute firewall-rules delete critical-fw-rule --quiet 2>/dev/null; gcloud compute firewall-rules create critical-fw-rule --network=client-vpc --direction=INGRESS --priority=1000 --action=DENY --rules=tcp:80,tcp:22 --target-tags=compromised-vm --enable-logging 
gcloud compute firewall-rules delete allow-ssh-from-bastion --quiet 2>/dev/null; gcloud compute firewall-rules create allow-ssh-from-bastion --network=client-vpc --action allow --direction=ingress --rules tcp:22 --source-ranges=$(gcloud compute instances describe bastion-host --zone=$(gcloud compute instances list --filter="name=bastion-host" --format="get(zone)") --format="get(networkInterfaces[0].accessConfigs[0].natIP)") --target-tags=compromised-vm
gcloud compute networks subnets update my-subnet --region=$(gcloud compute networks subnets list --filter="name=my-subnet" --format="get(region)") --enable-flow-logs



echo "${RED}${BOLD}Congratulations${RESET}" "${WHITE}${BOLD}for${RESET}" "${GREEN}${BOLD}Completing the Lab !!! - ePlus.DEV${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#