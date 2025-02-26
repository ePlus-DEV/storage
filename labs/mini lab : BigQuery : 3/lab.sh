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

export PROJECT_ID=$(gcloud config get-value project)
bq query --use_legacy_sql=false "SELECT DISTINCT p.product_name, p.price FROM \`$PROJECT_ID.Inventory.products\` AS p INNER JOIN \`$PROJECT_ID.Inventory.category\` AS c ON p.category_id = c.category_id WHERE p.category_id = 1;"

bq query --use_legacy_sql=false " CREATE VIEW \`$PROJECT_ID.Inventory.Product_View\` AS SELECT DISTINCT p.product_name, p.price FROM \`$PROJECT_ID.Inventory.products\` AS p INNER JOIN \`$PROJECT_ID.Inventory.category\` AS c ON p.category_id = c.category_id WHERE p.category_id = 1; "

bq show --format=prettyjson $PROJECT_ID:Inventory.Product_View

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#
