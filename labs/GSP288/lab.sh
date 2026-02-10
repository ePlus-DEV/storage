# !/bin/bash

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
# ----------------------------------------------------start-------------------------------------------------- #

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV ${RESET}"

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

echo -e "${BLUE}✅ Project:${NC} $(gcloud config get-value project)"
echo -e "${BLUE}📍 Region:${NC} $REGION"
echo -e "${BLUE}🧪 Zone:${NC} $ZONE"

gcloud services enable dataproc.googleapis.com
gcloud dataproc clusters create my-cluster \
    --region=$REGION \
    --zone=$ZONE \
    --image-version=2.0-debian10 \
    --optional-components=JUPYTER \
    --project=$DEVSHELL_PROJECT_ID
gcloud dataproc jobs submit spark \
    --cluster=my-cluster \
    --region=$REGION \
    --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
    --class=org.apache.spark.examples.SparkPi \
    --project=$DEVSHELL_PROJECT_ID \
    -- \
    1000
gcloud dataproc clusters update my-cluster \
    --region=$REGION \
    --num-workers=3 \
    --project=$DEVSHELL_PROJECT_ID

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

# -----------------------------------------------------end---------------------------------------------------------- #
