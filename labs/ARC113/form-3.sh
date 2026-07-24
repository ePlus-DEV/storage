#!/bin/bash

# Color Definitions
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

# Clear screen and display banner
clear

echo "${CYAN_TEXT}${BOLD_TEXT}╔════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║    🚀 ePlus.DEV - CLOUD LAB 🚀  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}╚════════════════════════════════════════════╝${RESET_FORMAT}"
echo
echo "${WHITE_TEXT}📺 YouTube: ${BLUE_TEXT}https://www.youtube.com/@drabhishek.5460${RESET_FORMAT}"
echo "${WHITE_TEXT}⭐ Subscribe for more Cloud & DevOps Tutorials! ⭐${RESET_FORMAT}"
echo

# Step 1: Create Pub/Sub Topic
echo
echo "${BLUE_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}  🎯 STEP 1: Creating Pub/Sub Topic ${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
gcloud pubsub topics create gcloud-pubsub-topic

# Step 2: Create Subscription
echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}  📩 STEP 2: Creating Subscription ${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
gcloud pubsub subscriptions create pubsub-subscription-message --topic=gcloud-pubsub-topic

# Step 3: Publish Message
echo
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}  ✉️  STEP 3: Publishing Message ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
gcloud pubsub topics publish gcloud-pubsub-topic --message="Hello World"

# Step 4: Verify Messages
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}  ✅ STEP 4: Verifying Message Delivery ${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${WHITE_TEXT}Waiting 10 seconds for message to arrive...${RESET_FORMAT}"
sleep 10
gcloud pubsub subscriptions pull pubsub-subscription-message --limit 5

# Step 5: Create Snapshot
echo
echo "${CYAN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}  📸 STEP 5: Creating Snapshot ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
gcloud pubsub snapshots create pubsub-snapshot --subscription=pubsub-subscription-message

# Completion Message
echo
echo "${GREEN_TEXT}${BOLD_TEXT}╔════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}║          🎉 LAB COMPLETED SUCCESSFULLY! 🎉  ║${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}╚════════════════════════════════════════════╝${RESET_FORMAT}"