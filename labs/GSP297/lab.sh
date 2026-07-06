#!/bin/bash

set -u

GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
BG_MAGENTA=$(tput setab 5 2>/dev/null || true)
BG_RED=$(tput setab 1 2>/dev/null || true)
BOLD=$(tput bold 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV ${RESET}"

export BUCKET="$(gcloud config get-value project)"

echo "${CYAN}${BOLD}Bucket: gs://$BUCKET ${RESET}"

echo
echo "${YELLOW}${BOLD}Task 1: Create a bucket ${RESET}"
gsutil mb "gs://$BUCKET" 2>/dev/null || echo "${GREEN}Bucket already exists, continuing...${RESET}"

echo
echo "${YELLOW}${BOLD}Task 2: Define a Retention Policy ${RESET}"
gsutil retention set 10s "gs://$BUCKET"
gsutil retention get "gs://$BUCKET"

echo
echo "${CYAN}${BOLD}Upload dummy_transactions ${RESET}"
gsutil cp gs://spls/gsp297/dummy_transactions "gs://$BUCKET/"
gsutil ls -L "gs://$BUCKET/dummy_transactions"

echo
echo "${YELLOW}${BOLD}Task 3: Lock the Retention Policy ${RESET}"
echo "y" | gsutil retention lock "gs://$BUCKET/" || true
gsutil retention get "gs://$BUCKET"

echo
echo "${YELLOW}${BOLD}Task 4: Temporary Hold ${RESET}"
gsutil retention temp set "gs://$BUCKET/dummy_transactions"

echo
echo "${CYAN}Trying to delete dummy_transactions while temporary hold is active. This failure is expected.${RESET}"
gsutil rm "gs://$BUCKET/dummy_transactions" || true

echo
echo "${CYAN}Release temporary hold on dummy_transactions.${RESET}"
gsutil retention temp release "gs://$BUCKET/dummy_transactions"

echo
echo "${CYAN}Wait for the 10-second retention period to expire.${RESET}"
sleep 15

echo
echo "${CYAN}Remove dummy_transactions file.${RESET}"
gsutil rm "gs://$BUCKET/dummy_transactions"

echo
echo "${YELLOW}${BOLD}Task 5: Event-based Holds ${RESET}"
gsutil retention event-default set "gs://$BUCKET/"

echo
echo "${CYAN}${BOLD}Upload dummy_loan ${RESET}"
gsutil cp gs://spls/gsp297/dummy_loan "gs://$BUCKET/"

echo
echo "${CYAN}Verify event-based hold on dummy_loan.${RESET}"
gsutil ls -L "gs://$BUCKET/dummy_loan"

echo
echo "${CYAN}Release event-based hold on dummy_loan.${RESET}"
gsutil retention event release "gs://$BUCKET/dummy_loan"

echo
echo "${CYAN}Verify retention expiration after releasing event-based hold.${RESET}"
gsutil ls -L "gs://$BUCKET/dummy_loan"

echo
echo "${CYAN}Try to delete dummy_loan. If retention has not expired yet, this may fail once.${RESET}"
gsutil rm "gs://$BUCKET/dummy_loan" || true

echo
echo "${CYAN}Wait for the 10-second retention period to expire.${RESET}"
sleep 15

echo
echo "${CYAN}Remove dummy_loan file.${RESET}"
gsutil rm "gs://$BUCKET/dummy_loan" 2>/dev/null || true

echo
echo "${YELLOW}${BOLD}Task 6: Delete the empty bucket ${RESET}"
gsutil rb "gs://$BUCKET/" || true

echo
echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"