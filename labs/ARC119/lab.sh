#!/bin/bash

# ==============================================================
# Google Cloud Dataplex Lab Automation
# Copyright © ePlus.DEV. All rights reserved.
#
# Resource execution commands are preserved from the source code.
# ==============================================================

# Define color variables
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

clear

echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}             GOOGLE CLOUD DATAPLEX LAB AUTOMATION                 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}                         © ePlus.DEV                               ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
echo

echo "${WHITE_TEXT}${BOLD_TEXT}Select the lab form to execute:${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}${BOLD_TEXT}  [1] Form 1 - Lake, Zone, Environment and Tag Template${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}  [2] Form 2 - Lake, Zone, Environment, Assets and Tag Template${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}  [3] Form 3 - BigQuery, Dataplex Zone, Asset and Protected Tag${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}  [4] Form 4 - Lake, Zone and Dataplex Assets${RESET_FORMAT}"
echo

read -p "${YELLOW_TEXT}${BOLD_TEXT}Enter the Form number (1, 2, 3 or 4): ${RESET_FORMAT}" FORM_NUMBER

case "$FORM_NUMBER" in
    1|2|3|4)
        ;;
    *)
        echo
        echo "${RED_TEXT}${BOLD_TEXT}Invalid Form number.${RESET_FORMAT}"
        echo "${YELLOW_TEXT}Please run the script again and enter 1, 2, 3 or 4.${RESET_FORMAT}"
        exit 1
        ;;
esac

echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Detecting Google Cloud project, zone and region...${RESET_FORMAT}"

export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    export PROJECT_ID="$DEVSHELL_PROJECT_ID"
fi

export ZONE=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)

export REGION=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

# Use the zone to determine the region when default region is unavailable
if [[ -z "$REGION" && -n "$ZONE" ]]; then
    export REGION="${ZONE%-*}"
fi

if [[ -z "$PROJECT_ID" ]]; then
    echo
    echo "${RED_TEXT}${BOLD_TEXT}Unable to detect the Google Cloud Project ID.${RESET_FORMAT}"
    exit 1
fi

if [[ -z "$ZONE" ]]; then
    echo
    echo "${RED_TEXT}${BOLD_TEXT}Unable to detect the default compute zone.${RESET_FORMAT}"
    echo "${YELLOW_TEXT}Please make sure the lab provides google-compute-default-zone metadata.${RESET_FORMAT}"
    exit 1
fi

if [[ -z "$REGION" ]]; then
    echo
    echo "${RED_TEXT}${BOLD_TEXT}Unable to detect the default compute region.${RESET_FORMAT}"
    exit 1
fi

export DEVSHELL_PROJECT_ID="$PROJECT_ID"
export KEY_1=domain_type
export VALUE_1=source_data

gcloud config set project "$PROJECT_ID" >/dev/null
gcloud config set compute/zone "$ZONE" >/dev/null
gcloud config set compute/region "$REGION" >/dev/null

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ Configuration detected successfully.${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}Form:${RESET_FORMAT} ${CYAN_TEXT}$FORM_NUMBER${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}Project ID:${RESET_FORMAT} ${CYAN_TEXT}$PROJECT_ID${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}Zone:${RESET_FORMAT} ${CYAN_TEXT}$ZONE${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}Region:${RESET_FORMAT} ${CYAN_TEXT}$REGION${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}Labels:${RESET_FORMAT} ${CYAN_TEXT}$KEY_1=$VALUE_1${RESET_FORMAT}"
echo

# ==============================================================
# FORM 1
# ==============================================================

run_form_1() {
    echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}          EXECUTING FORM 1             ${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
    echo

    echo "${MAGENTA_TEXT}${BOLD_TEXT}Creating a storage bucket to store your data securely...${RESET_FORMAT}"
    echo "${GREEN_TEXT}${BOLD_TEXT}✓ Proceeding with bucket creation...${RESET_FORMAT}"

    gsutil mb -p $DEVSHELL_PROJECT_ID -l $REGION -b on gs://$DEVSHELL_PROJECT_ID-bucket/

    echo
    echo "${BLUE_TEXT}${BOLD_TEXT}Creating a Dataplex Lake to manage your data assets...${RESET_FORMAT}"
    echo "${GREEN_TEXT}${BOLD_TEXT}✓ Proceeding with Dataplex Lake creation...${RESET_FORMAT}"

    gcloud alpha dataplex lakes create customer-lake \
        --display-name="Customer-Lake" \
        --location=$REGION \
        --labels="key_1=$KEY_1,value_1=$VALUE_1"

    echo
    echo "${CYAN_TEXT}${BOLD_TEXT}Creating a Public Zone within the Dataplex Lake...${RESET_FORMAT}"
    echo "${GREEN_TEXT}${BOLD_TEXT}✓ Proceeding with zone creation...${RESET_FORMAT}"

    gcloud dataplex zones create public-zone \
        --lake=customer-lake \
        --location=$REGION \
        --type=RAW \
        --resource-location-type=SINGLE_REGION \
        --display-name="Public-Zone"

    echo
    echo "${YELLOW_TEXT}${BOLD_TEXT}Setting up an analytics environment for data processing...${RESET_FORMAT}"
    echo "${GREEN_TEXT}${BOLD_TEXT}✓ Proceeding with environment creation...${RESET_FORMAT}"

    gcloud dataplex environments create dataplex-lake-env \
        --project=$DEVSHELL_PROJECT_ID \
        --location=$REGION \
        --lake=customer-lake \
        --os-image-version=1.0 \
        --compute-node-count 3 \
        --compute-max-node-count 3

    echo
    echo "${MAGENTA_TEXT}${BOLD_TEXT}Setting up data governance policies for your data lake...${RESET_FORMAT}"
    echo "${GREEN_TEXT}${BOLD_TEXT}✓ Proceeding with tag template creation...${RESET_FORMAT}"

    gcloud data-catalog tag-templates create customer_data_tag_template \
        --location=$REGION \
        --display-name="Customer Data Tag Template" \
        --field=id=data_owner,display-name="Data Owner",type=string,required=TRUE \
        --field=id=pii_data,display-name="PII Data",type="enum(Yes|No)",required=TRUE

    echo
    echo "${YELLOW_TEXT}${BOLD_TEXT}OPEN THIS LINK:${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://console.cloud.google.com/projectselector2/dataplex/groups${RESET_FORMAT}"
}

# ==============================================================
# FORM 2
# ==============================================================

run_form_2() {
    echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}          EXECUTING FORM 2             ${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
    echo

    gcloud alpha dataplex lakes create customer-lake \
        --display-name="Customer-Lake" \
        --location=$REGION \
        --labels="key_1=$KEY_1,value_1=$VALUE_1"

    gcloud dataplex zones create public-zone \
        --lake=customer-lake \
        --location=$REGION \
        --type=RAW \
        --resource-location-type=SINGLE_REGION \
        --display-name="Public-Zone"

    gcloud dataplex environments create dataplex-lake-env \
        --project=$DEVSHELL_PROJECT_ID \
        --location=$REGION \
        --lake=customer-lake \
        --os-image-version=1.0 \
        --compute-node-count 3 \
        --compute-max-node-count 3

    gcloud dataplex assets create customer-raw-data \
        --location=$REGION \
        --lake=customer-lake \
        --zone=public-zone \
        --resource-type=STORAGE_BUCKET \
        --resource-name=projects/$DEVSHELL_PROJECT_ID/buckets/$DEVSHELL_PROJECT_ID-customer-bucket \
        --discovery-enabled \
        --display-name="Customer Raw Data"

    gcloud dataplex assets create customer-reference-data \
        --location=$REGION \
        --lake=customer-lake \
        --zone=public-zone \
        --resource-type=BIGQUERY_DATASET \
        --resource-name=projects/$DEVSHELL_PROJECT_ID/datasets/customer_reference_data \
        --display-name="Customer Reference Data"

    gcloud data-catalog tag-templates create customer_data_tag_template \
        --location=$REGION \
        --display-name="Customer Data Tag Template" \
        --field=id=data_owner,display-name="Data Owner",type=string,required=TRUE \
        --field=id=pii_data,display-name="PII Data",type='enum(Yes|No)',required=TRUE
}

# ==============================================================
# FORM 3
# ==============================================================

run_form_3() {
    echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}          EXECUTING FORM 3             ${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
    echo

    bq mk --location=US Raw_data

    bq load --source_format=AVRO Raw_data.public-data gs://spls/gsp1145/users.avro

    gcloud dataplex zones create temperature-raw-data \
        --lake=public-lake \
        --location=$REGION \
        --type=RAW \
        --resource-location-type=SINGLE_REGION \
        --display-name="temperature-raw-data"

    gcloud dataplex assets create customer-details-dataset \
        --location=$REGION \
        --lake=public-lake \
        --zone=temperature-raw-data \
        --resource-type=BIGQUERY_DATASET \
        --resource-name=projects/$DEVSHELL_PROJECT_ID/datasets/customer_reference_data \
        --display-name="Customer Details Dataset" \
        --discovery-enabled

    gcloud data-catalog tag-templates create protected_data_template \
        --location=$REGION \
        --display-name="Protected Data Template" \
        --field=id=protected_data_flag,display-name="Protected Data Flag",type='enum(Yes|No)',required=TRUE
}

# ==============================================================
# FORM 4
# ==============================================================

run_form_4() {
    echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}          EXECUTING FORM 4             ${RESET_FORMAT}"
    echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
    echo

    gcloud alpha dataplex lakes create customer-lake \
        --display-name="Customer-Lake" \
        --location=$REGION \
        --labels="key_1=$KEY_1,value_1=$VALUE_1"

    gcloud dataplex zones create public-zone \
        --lake=customer-lake \
        --location=$REGION \
        --type=RAW \
        --resource-location-type=SINGLE_REGION \
        --display-name="Public-Zone"

    gcloud dataplex assets create customer-raw-data \
        --location=$REGION \
        --lake=customer-lake \
        --zone=public-zone \
        --resource-type=STORAGE_BUCKET \
        --resource-name=projects/$DEVSHELL_PROJECT_ID/buckets/$DEVSHELL_PROJECT_ID-customer-bucket \
        --discovery-enabled \
        --display-name="Customer Raw Data"

    gcloud dataplex assets create customer-reference-data \
        --location=$REGION \
        --lake=customer-lake \
        --zone=public-zone \
        --resource-type=BIGQUERY_DATASET \
        --resource-name=projects/$DEVSHELL_PROJECT_ID/datasets/customer_reference_data \
        --display-name="Customer Reference Data"
}

case "$FORM_NUMBER" in
    1)
        run_form_1
        ;;
    2)
        run_form_2
        ;;
    3)
        run_form_3
        ;;
    4)
        run_form_4
        ;;
esac

echo
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}              LAB EXECUTION COMPLETED                  ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}                    © ePlus.DEV                        ${RESET_FORMAT}"
echo "${CYAN_TEXT}                  All rights reserved.${RESET_FORMAT}"
echo