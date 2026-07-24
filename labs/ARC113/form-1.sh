#!/bin/bash

# Define color variables
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
UNDERLINE_TEXT=$'\033[4m'

clear

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}==============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}     🚀 ePlus.DEV – GCP Lab      ${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}==============================================================${RESET_FORMAT}"
echo

echo "${CYAN_TEXT}${BOLD_TEXT}Step 1:${RESET_FORMAT} ${CYAN_TEXT}Creating a subscription to the topic...${RESET_FORMAT}"
echo
gcloud pubsub subscriptions create pubsub-subscription-message --topic gcloud-pubsub-topic

echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Step 2:${RESET_FORMAT} ${YELLOW_TEXT}Publishing a message to the topic...${RESET_FORMAT}"
echo "${YELLOW_TEXT}Sending message: '${BOLD_TEXT}Hello World${RESET_FORMAT}${YELLOW_TEXT}' to all subscriptions.${RESET_FORMAT}"
echo
gcloud pubsub topics publish gcloud-pubsub-topic --message="Hello World"

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}Waiting:${RESET_FORMAT} ${MAGENTA_TEXT}Allowing some time for processing...${RESET_FORMAT}"
sleep 10

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Step 3:${RESET_FORMAT} ${GREEN_TEXT}Pulling messages from the subscription...${RESET_FORMAT}"
echo "${GREEN_TEXT}Fetching up to ${BOLD_TEXT}5${RESET_FORMAT}${GREEN_TEXT} messages sent to the topic.${RESET_FORMAT}"
gcloud pubsub subscriptions pull pubsub-subscription-message --limit 5

echo
echo "${RED_TEXT}${BOLD_TEXT}Step 4:${RESET_FORMAT} ${RED_TEXT}Creating a snapshot of the subscription...${RESET_FORMAT}"
gcloud pubsub snapshots create pubsub-snapshot --subscription=gcloud-pubsub-subscription

echo
echo "${BLUE_TEXT}${BOLD_TEXT}==============================================================${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}           ✅ LAB COMPLETED SUCCESSFULLY – WELL DONE!         ${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}==============================================================${RESET_FORMAT}"
echo