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

gcloud auth list

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

export DATASET_SERVICE=netflix-dataset-service

export FRONTEND_STAGING_SERVICE=frontend-staging-service

export FRONTEND_PRODUCTION_SERVICE=frontend-production-service

gcloud config set project $(gcloud projects list --format='value(PROJECT_ID)' --filter='qwiklabs-gcp')

gcloud firestore databases create --location=$REGION --project=$DEVSHELL_PROJECT_ID

sleep 10

gcloud services enable run.googleapis.com

git clone https://github.com/rosera/pet-theory.git

cd pet-theory/lab06/firebase-import-csv/solution

npm install
node index.js netflix_titles_original.csv

cd ~/pet-theory/lab06/firebase-rest-api/solution-01
npm install
cd ~/pet-theory/lab06/firebase-rest-api/solution-01

gcloud builds submit --tag gcr.io/$DEVSHELL_PROJECT_ID/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE --image gcr.io/$DEVSHELL_PROJECT_ID/rest-api:0.1 --allow-unauthenticated --max-instances=1 --region=$REGION 

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE --region=$REGION --format 'value(status.url)')

curl -X GET $SERVICE_URL

cd ~/pet-theory/lab06/firebase-rest-api/solution-02
npm install
cd ~/pet-theory/lab06/firebase-rest-api/solution-02

gcloud builds submit --tag gcr.io/$DEVSHELL_PROJECT_ID/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE --image gcr.io/$DEVSHELL_PROJECT_ID/rest-api:0.2 --region=$REGION --allow-unauthenticated --max-instances=1

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE --region=$REGION --format 'value(status.url)')

curl -X GET $SERVICE_URL/2019

npm install && npm run build

cd ~/pet-theory/lab06/firebase-frontend

gcloud builds submit --tag gcr.io/$DEVSHELL_PROJECT_ID/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE --image gcr.io/$DEVSHELL_PROJECT_ID/frontend-staging:0.1 --platform managed --region=$REGION --max-instances 1 --allow-unauthenticated --quiet

gcloud run services describe $FRONTEND_STAGING_SERVICE --region=$REGION --format="value(status.url)"

gcloud builds submit --tag gcr.io/$DEVSHELL_PROJECT_ID/frontend-production:0.1
gcloud run deploy $FRONTEND_PRODUCTION_SERVICE --image gcr.io/$DEVSHELL_PROJECT_ID/frontend-production:0.1 --platform managed --region=$REGION --max-instances=1 --quiet


echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#