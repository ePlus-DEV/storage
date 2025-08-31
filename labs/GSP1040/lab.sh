#!/bin/bash

# Enhanced Color Definitions
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

# Special Formatting
NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'
BLINK_TEXT=$'\033[5m'
REVERSE_TEXT=$'\033[7m'

clear
# Welcome Banner
echo "${BLUE_TEXT}${BOLD_TEXT}╔═══════════════════════╗${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}          ePlus.DEV        ${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}╚═══════════════════════╝${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BLINK_TEXT}⚡ Initializing BigQuery BigLake Configuration...${RESET_FORMAT}"
echo

# Section 1: Project Setup
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬▬ PROJECT SETUP ▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}🛠️  Getting your Project ID...${RESET_FORMAT}"
export PROJECT_ID=$(gcloud config get-value project)
echo "${CYAN_TEXT}${REVERSE_TEXT} Your Project ID: $PROJECT_ID ${RESET_FORMAT}"
echo

# Section 2: Connection Creation
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬ CONNECTION SETUP ▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}🔗 Creating BigQuery connection 'my-connection' in US region${RESET_FORMAT}"
bq mk --connection --location=US --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE my-connection
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Connection created successfully!${RESET_FORMAT}"
echo

# Section 3: Service Account Configuration
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬ SERVICE ACCOUNT SETUP ▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}👤 Retrieving connection service account${RESET_FORMAT}"
SERVICE_ACCOUNT=$(bq show --format=json --connection $PROJECT_ID.US.my-connection | jq -r '.cloudResource.serviceAccountId')
echo "${CYAN_TEXT}${BOLD_TEXT}Service Account: ${WHITE_TEXT}$SERVICE_ACCOUNT${RESET_FORMAT}"

echo "${YELLOW_TEXT}${BOLD_TEXT}🔑 Granting Storage Object Viewer role${RESET_FORMAT}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:$SERVICE_ACCOUNT \
  --role=roles/storage.objectViewer
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Permissions granted successfully!${RESET_FORMAT}"
echo

# Section 4: Dataset Creation
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬ DATASET SETUP ▬▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}📊 Creating 'demo_dataset' in BigQuery${RESET_FORMAT}"
bq mk demo_dataset
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Dataset created successfully!${RESET_FORMAT}"
echo

# Section 5: Table Definitions
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬ TABLE DEFINITIONS ▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}📝 Creating external table definition for invoice.csv${RESET_FORMAT}"
bq mkdef \
--autodetect \
--connection_id=$PROJECT_ID.US.my-connection \
--source_format=CSV \
"gs://$PROJECT_ID/invoice.csv" > /tmp/tabledef.json
echo "${CYAN_TEXT}${BOLD_TEXT}Definition saved to /tmp/tabledef.json${RESET_FORMAT}"
echo

# Section 6: Table Creation
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬▬ TABLE CREATION ▬▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}🆕 Creating BigLake table 'biglake_table'${RESET_FORMAT}"
bq mk --external_table_definition=/tmp/tabledef.json --project_id=$PROJECT_ID demo_dataset.biglake_table
echo "${GREEN_TEXT}${BOLD_TEXT}✅ BigLake table created successfully!${RESET_FORMAT}"

echo "${MAGENTA_TEXT}${BOLD_TEXT}🆕 Creating external table 'external_table'${RESET_FORMAT}"
bq mk --external_table_definition=/tmp/tabledef.json --project_id=$PROJECT_ID demo_dataset.external_table
echo "${GREEN_TEXT}${BOLD_TEXT}✅ External table created successfully!${RESET_FORMAT}"
echo

# Section 7: Schema Management
echo "${GREEN_TEXT}${BOLD_TEXT}▬▬▬▬▬▬▬▬▬▬ SCHEMA MANAGEMENT ▬▬▬▬▬▬▬▬▬▬${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}📋 Extracting schema from external table${RESET_FORMAT}"
bq show --schema --format=prettyjson demo_dataset.external_table > /tmp/schema
echo "${CYAN_TEXT}${BOLD_TEXT}Schema saved to /tmp/schema${RESET_FORMAT}"

echo "${YELLOW_TEXT}${BOLD_TEXT}🔄 Updating external table with schema${RESET_FORMAT}"
bq update --external_table_definition=/tmp/tabledef.json --schema=/tmp/schema demo_dataset.external_table
echo "${GREEN_TEXT}${BOLD_TEXT}✅ Table updated successfully!${RESET_FORMAT}"
echo

# Completion Banner
echo "${GREEN_TEXT}${BOLD_TEXT}╔════════════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}          LAB  COMPLETED SUCCESSFULLY!                  ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}╚════════════════════════════════════════════════════════╝${RESET_FORMAT}"
echo
echo "${RED_TEXT}${BOLD_TEXT}🙏 Special thanks to Dr. Abhishek for this tutorial!${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}📺 Subscribe for more GCP content:${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}💡 Happy querying with BigQuery BigLake!${RESET_FORMAT}"