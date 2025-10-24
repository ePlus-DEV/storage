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

export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")

export ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")


gcloud services enable cloudscheduler.googleapis.com run.googleapis.com

sleep 20

gcloud storage cp -r gs://spls/gsp649/* . && cd gcf-automated-resource-cleanup/

export PROJECT_ID=$(gcloud config list --format 'value(core.project)' 2>/dev/null)
WORKDIR=$(pwd)

sudo apt-get update
sudo apt-get install apache2-utils -y

cd $WORKDIR/migrate-storage

export PROJECT_ID=$(gcloud config list --format 'value(core.project)' 2>/dev/null)
gcloud storage buckets create  gs://${PROJECT_ID}-serving-bucket -l $REGION

gsutil acl ch -u allUsers:R gs://${PROJECT_ID}-serving-bucket

gcloud storage cp $WORKDIR/migrate-storage/testfile.txt  gs://${PROJECT_ID}-serving-bucket

gsutil acl ch -u allUsers:R gs://${PROJECT_ID}-serving-bucket/testfile.txt

curl http://storage.googleapis.com/${PROJECT_ID}-serving-bucket/testfile.txt

gcloud storage buckets create gs://${PROJECT_ID}-idle-bucket -l $REGION
export IDLE_BUCKET_NAME=$PROJECT_ID-idle-bucket


#TASK 3 manually

#TASK 4


cat $WORKDIR/migrate-storage/main.py | grep "migrate_storage(" -A 15

sed -i "s/<project-id>/$PROJECT_ID/" $WORKDIR/migrate-storage/main.py

gcloud services disable cloudfunctions.googleapis.com

gcloud services enable cloudfunctions.googleapis.com

export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
--role="roles/artifactregistry.reader"

gcloud functions deploy migrate_storage --gen2 --trigger-http --runtime=python39 --region $REGION --quiet

export FUNCTION_URL=$(gcloud functions describe migrate_storage --format=json --region $REGION | jq -r '.url')

export IDLE_BUCKET_NAME=$PROJECT_ID-idle-bucket
sed -i "s/\\\$IDLE_BUCKET_NAME/$IDLE_BUCKET_NAME/" $WORKDIR/migrate-storage/incident.json

envsubst < $WORKDIR/migrate-storage/incident.json | curl -X POST -H "Content-Type: application/json" $FUNCTION_URL -d @-

gsutil defstorageclass set nearline gs://$PROJECT_ID-idle-bucket

gsutil defstorageclass get gs://$PROJECT_ID-idle-bucket

gcloud services enable cloudscheduler.googleapis.com


echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#