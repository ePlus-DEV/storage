#!/bin/bash

# ============================================================
# GSP070 - App Engine: Qwik Start - Go
# ePlus.DEV
# ============================================================

# -------------------------- COLORS ---------------------------
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'

# -------------------------- HEADER ---------------------------
clear

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}        GSP070 - APP ENGINE: QWIK START - GO${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}                     © ePlus.DEV${RESET_FORMAT}"
echo

# ----------------------- PROJECT INFO ------------------------
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

echo "${BLUE_TEXT}${BOLD_TEXT}Project:${RESET_FORMAT} ${WHITE_TEXT}${PROJECT_ID}${RESET_FORMAT}"

# ------------------------------------------------------------
# Detect region
# ------------------------------------------------------------

REGION=$(gcloud config get-value compute/region 2>/dev/null)

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
    REGION=$(gcloud compute project-info describe \
        --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
        2>/dev/null)
fi

# GSP070 currently specifies us-east4.
# Only used if the lab environment does not expose a default region.
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
    REGION="us-east4"
fi

gcloud config set compute/region "$REGION" >/dev/null 2>&1

echo "${BLUE_TEXT}${BOLD_TEXT}Region :${RESET_FORMAT} ${WHITE_TEXT}${REGION}${RESET_FORMAT}"
echo

# ============================================================
# TASK 1 - ENABLE APIS
# ============================================================

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT} TASK 1 - ENABLE REQUIRED APIS${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

echo "${YELLOW_TEXT}Enabling App Engine Admin API...${RESET_FORMAT}"

gcloud services enable \
    appengine.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    --project="$PROJECT_ID"

if [[ $? -eq 0 ]]; then
    echo
    echo "${GREEN_TEXT}${BOLD_TEXT}✓ Required APIs enabled.${RESET_FORMAT}"
else
    echo
    echo "${RED_TEXT}${BOLD_TEXT}⚠ API enable command returned an error.${RESET_FORMAT}"
    echo "${YELLOW_TEXT}Continuing because some APIs may already be enabled.${RESET_FORMAT}"
fi

echo

# ============================================================
# TASK 2 - DOWNLOAD HELLO WORLD APPLICATION
# ============================================================

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT} TASK 2 - DOWNLOAD HELLO WORLD APP${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

WORK_DIR="$HOME/gsp070"
REPO_DIR="$WORK_DIR/golang