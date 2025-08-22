#!/usr/bin/env bash
# ============================================================================
#  ePlus.DEV Dataplex Setup Script
#  Copyright (c) 2025 ePlus.DEV. All rights reserved.
#  License: For educational/lab use only. No warranty of any kind.
# ============================================================================

set -euo pipefail

# ---- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---- Helpers ---------------------------------------------------------------
die() { echo -e "${RED}✖ $*${NC}" >&2; exit 1; }
info() { echo -e "${YELLOW}➜ $*${NC}"; }
ok()   { echo -e "${GREEN}✔ $*${NC}"; }
hl()   { echo -e "${CYAN}$*${NC}"; }

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

echo "${YELLOW}${BOLD}Starting${RESET}" "${GREEN}${BOLD}Execution${RESET}"

# ---- Ask for REGION --------------------------------------------------------
read -rp "$(echo -e "${CYAN}Enter REGION [us-central1]: ${NC}")" INPUT_REGION
REGION="${INPUT_REGION:-us-central1}"
[[ -n "$REGION" ]] || die "REGION must not be empty"

gcloud services enable appengine.googleapis.com

sleep 10

gcloud config set compute/region $REGION

git clone https://github.com/GoogleCloudPlatform/golang-samples.git

cd golang-samples/appengine/go11x/helloworld

sudo apt-get install google-cloud-sdk-app-engine-go
gcloud app deploy

echo "${RED}${BOLD}Congratulations${RESET}" "${WHITE}${BOLD}for${RESET}" "${GREEN}${BOLD}Completing the Lab !!!${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#