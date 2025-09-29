#!/bin/bash

# Enhanced Color Definitions
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bold Colors
BOLD_BLACK='\033[1;30m'
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'
BOLD_MAGENTA='\033[1;35m'
BOLD_CYAN='\033[1;36m'
BOLD_WHITE='\033[1;37m'

# Background Colors
BG_BLACK='\033[40m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'

# Special Formats
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'
HIDDEN='\033[8m'

RESET='\033[0m'

#----------------------------------------------------start--------------------------------------------------#


# User Input Section
echo -e "${BOLD_BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD_BLUE}║               ${BOLD_WHITE}Configuration Parameters ${BOLD_BLUE}              ║${RESET}"
echo -e "${BOLD_BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "${BOLD_MAGENTA}Please enter the following configuration details:${RESET}"
read -p "$(echo -e "${BOLD_YELLOW}ENTER LANGUAGE (e.g., English, Japanese): ${RESET}")" LANGUAGE
read -p "$(echo -e "${BOLD_YELLOW}ENTER LOCAL (e.g., en_US, fr_FR): ${RESET}")" LOCAL
read -p "$(echo -e "${BOLD_YELLOW}ENTER BIGQUERY_ROLE (e.g., roles/bigquery.admin): ${RESET}")" BIGQUERY_ROLE
read -p "$(echo -e "${BOLD_YELLOW}ENTER CLOUD_STORAGE_ROLE (e.g., roles/storage.admin): ${RESET}")" CLOUD_STORAGE_ROLE
echo ""

# Service Account Setup
echo -e "${BOLD_GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD_GREEN}║             ${BOLD_WHITE}Service Account Configuration ${BOLD_GREEN}          ║${RESET}"
echo -e "${BOLD_GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "${BOLD_BLUE}→ Creating service account 'sample-sa'...${RESET}"
gcloud iam service-accounts create sample-sa
echo ""

echo -e "${BOLD_BLUE}→ Assigning IAM roles to service account...${RESET}"
echo -e "${CYAN}  - BigQuery Role: ${BOLD_WHITE}$BIGQUERY_ROLE${RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:sample-sa@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com --role=$BIGQUERY_ROLE

echo -e "${CYAN}  - Cloud Storage Role: ${BOLD_WHITE}$CLOUD_STORAGE_ROLE${RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:sample-sa@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com --role=$CLOUD_STORAGE_ROLE

echo -e "${CYAN}  - Service Usage Consumer Role${RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member=serviceAccount:sample-sa@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com --role=roles/serviceusage.serviceUsageConsumer
echo ""

echo -e "${BOLD_BLUE}→ Waiting 2 minutes for IAM changes to propagate...${RESET}"
for i in {1..120}; do
    echo -ne "${YELLOW}${i}/120 seconds elapsed...\r${RESET}"
    sleep 1
done
echo -e "\n"

echo -e "${BOLD_BLUE}→ Creating service account key...${RESET}"
gcloud iam service-accounts keys create sample-sa-key.json --iam-account sample-sa@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com
export GOOGLE_APPLICATION_CREDENTIALS=${PWD}/sample-sa-key.json
echo -e "${GREEN}✓ Key created and exported to environment${RESET}"
echo ""

# Image Analysis Section
echo -e "${BOLD_MAGENTA}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD_MAGENTA}║               ${BOLD_WHITE}Image Analysis Setup ${BOLD_MAGENTA}             ║${RESET}"
echo -e "${BOLD_MAGENTA}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "${BOLD_BLUE}→ Downloading image analysis script...${RESET}"
wget https://raw.githubusercontent.com/guys-in-the-cloud/cloud-skill-boosts/main/Challenge-labs/Integrate%20with%20Machine%20Learning%20APIs%3A%20Challenge%20Lab/analyze-images-v2.py
echo -e "${GREEN}✓ Script downloaded successfully${RESET}"
echo ""

echo -e "${BOLD_BLUE}→ Updating script locale to ${BOLD_WHITE}${LOCAL}${BOLD_BLUE}...${RESET}"
sed -i "s/'en'/'${LOCAL}'/g" analyze-images-v2.py
echo -e "${GREEN}✓ Locale updated successfully${RESET}"
echo ""

echo -e "${BOLD_BLUE}→ Running image analysis...${RESET}"
python3 analyze-images-v2.py
python3 analyze-images-v2.py $DEVSHELL_PROJECT_ID $DEVSHELL_PROJECT_ID
echo -e "${GREEN}✓ Image analysis completed${RESET}"
echo ""

# Results Section
echo -e "${BOLD_GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD_GREEN}║                 ${BOLD_WHITE}Analysis Results ${BOLD_GREEN}                  ║${RESET}"
echo -e "${BOLD_GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "${BOLD_CYAN}→ Querying locale distribution from BigQuery...${RESET}"
bq query --use_legacy_sql=false "SELECT locale,COUNT(locale) as lcount FROM image_classification_dataset.image_text_detail GROUP BY locale ORDER BY lcount DESC"
echo ""

# Completion Message
echo -e "${BOLD_WHITE}${BG_GREEN}══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD_WHITE}${BG_GREEN}                                                    ${RESET}"
echo -e "${BOLD_WHITE}${BG_GREEN}   ${BOLD_YELLOW}Lab Completed Successfully! ${BOLD_WHITE}${BG_GREEN}           ${RESET}"
echo -e "${BOLD_WHITE}${BG_GREEN}                                                    ${RESET}"
echo -e "${BOLD_WHITE}${BG_GREEN}══════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${BOLD_CYAN}For more tutorials, visit: ${UNDERLINE}https://eplus.dev${RESET}"
echo ""

#-----------------------------------------------------end----------------------------------------------------------#