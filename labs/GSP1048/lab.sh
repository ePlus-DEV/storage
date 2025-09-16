#!/bin/bash

# Enhanced Color Definitions
BLACK=$'\033[0;90m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'

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

# Header Section
echo "${BG_MAGENTA}${BOLD}╔═══════════════════════╗${RESET}"
echo "${BG_MAGENTA}${BOLD}        ePlus.DEV       ${RESET}"
echo "${BG_MAGENTA}${BOLD}╚═══════════════════════╝${RESET}"
echo
echo "${CYAN}${BOLD}          Expert Tutorial by David Nguyen              ${RESET}"
echo "${YELLOW}For more GCP monitoring tutorials, visit: https://eplus.dev${RESET}"
echo

gcloud spanner instances create banking-instance \
--config=regional-$REGION  \
--description="awesome" \
--nodes=1

gcloud spanner databases create banking-db --instance=banking-instance

gcloud spanner instances create banking-instance-2 \
--config=regional-$REGION  \
--description="awesome" \
--nodes=2

gcloud spanner databases create banking-db-2 --instance=banking-instance-2

gcloud spanner databases ddl update banking-db --instance=banking-instance --ddl="CREATE TABLE Customer (
  CustomerId STRING(36) NOT NULL,
  Name STRING(MAX) NOT NULL,
  Location STRING(MAX) NOT NULL,
) PRIMARY KEY (CustomerId);"

echo

# Completion Message
echo "${BG_GREEN}${BOLD}╔════════════════════════════════╗${RESET}"
echo "${BG_GREEN}${BOLD}          LAB COMPLETE!           ${RESET}"
echo "${BG_GREEN}${BOLD}╚════════════════════════════════╝${RESET}"
echo

echo "${BLUE}https://eplus.dev${RESET}"
echo
echo "${MAGENTA}${BOLD}📊 Happy monitoring with Google Managed Prometheus!${RESET}"