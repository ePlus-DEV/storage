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


export BUCKET="$(gcloud config get-value project)"		

gsutil mb "gs://$BUCKET"

gsutil retention set 10s "gs://$BUCKET"

gsutil retention get "gs://$BUCKET"

gsutil cp gs://cloud-samples-data/storage/bucket-lock/dummy_transactions "gs://$BUCKET/"

gsutil ls -L "gs://$BUCKET/dummy_transactions"

gsutil mv gs://$BUCKET/dummy_transactions gs://$BUCKET/example_transactions

echo 'y' | gsutil retention lock "gs://$BUCKET/"

gsutil cp gs://cloud-samples-data/storage/bucket-lock/example_transactions "gs://$BUCKET/"

gsutil retention temp set "gs://$BUCKET/example_transactions"

gsutil retention temp release "gs://$BUCKET/example_transactions"

gsutil retention event-default set "gs://$BUCKET/"

gsutil cp gs://cloud-samples-data/storage/bucket-lock/dummy_loan "gs://$BUCKET/"

gsutil mv gs://$BUCKET/dummy_loan gs://$BUCKET/example_loan

gsutil cp gs://cloud-samples-data/storage/bucket-lock/example_loan "gs://$BUCKET/"

gsutil retention event release "gs://$BUCKET/example_loan"

gsutil retention temp set "gs://$BUCKET/dummy_transactions"

gsutil rm "gs://$BUCKET/dummy_transactions"

gsutil retention temp release "gs://$BUCKET/dummy_transactions"

gsutil retention event-default set "gs://$BUCKET/"

gsutil cp gs://cloud-samples-data/storage/bucket-lock/dummy_loan "gs://$BUCKET/"

gsutil ls -L "gs://$BUCKET/dummy_loan"

gsutil retention event release "gs://$BUCKET/dummy_loan"

gsutil ls -L "gs://$BUCKET/dummy_loan"



echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#