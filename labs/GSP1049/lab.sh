#!/bin/bash
# ============================================================
#  Qwiklabs: Cloud Spanner + Dataflow Lab Automation Script
#  Author: David Nguyen (ePlus.DEV)
#  Copyright (c) 2025 David Nguyen. All rights reserved.
# ============================================================

# Enhanced Colors
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
RESET=$'\033[0m'
BOLD=$(tput bold)

# Header
echo "${MAGENTA}${BOLD}╔═══════════════════════╗${RESET}"
echo "${MAGENTA}${BOLD}        ePlus.DEV       ${RESET}"
echo "${MAGENTA}${BOLD}╚═══════════════════════╝${RESET}"
echo
echo "${CYAN}${BOLD}          Expert Tutorial by David Nguyen              ${RESET}"
echo "${YELLOW}For more GCP monitoring tutorials, visit: https://eplus.dev${RESET}"
echo

# Setup project, region
PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud config get-value compute/region)
INSTANCE_ID="banking-instance"
DATABASE_ID="banking-db"

echo "${YELLOW}>>> Project:${RESET} $PROJECT_ID"
echo "${YELLOW}>>> Region:${RESET} $REGION"
echo "${YELLOW}>>> Instance:${RESET} $INSTANCE_ID"
echo "${YELLOW}>>> Database:${RESET} $DATABASE_ID"

# ------------------------------------------------------------
# Task 2: Insert data with DML
# ------------------------------------------------------------
echo "${CYAN}>>> [Task 2] Insert single record via DML...${RESET}"
gcloud spanner databases execute-sql $DATABASE_ID --instance=$INSTANCE_ID \
 --sql="INSERT INTO Customer (CustomerId, Name, Location) VALUES ('bdaaaa97-1b4b-4e58-b4ad-84030de92235', 'Richard Nelson', 'Ada Ohio')"

# ------------------------------------------------------------
# Task 3: Insert via client library (Python)
# ------------------------------------------------------------
echo "${CYAN}>>> [Task 3] Creating insert.py...${RESET}"
cat > insert.py <<'EOF'
from google.cloud import spanner

INSTANCE_ID = "banking-instance"
DATABASE_ID = "banking-db"

spanner_client = spanner.Client()
instance = spanner_client.instance(INSTANCE_ID)
database = instance.database(DATABASE_ID)

def insert_customer(transaction):
    row_ct = transaction.execute_update(
        "INSERT INTO Customer (CustomerId, Name, Location) "
        "VALUES ('b2b4002d-7813-4551-b83b-366ef95f9273', 'Shana Underwood', 'Ely Iowa')"
    )
    print("{} record(s) inserted.".format(row_ct))

database.run_in_transaction(insert_customer)
EOF

python3 insert.py

# ------------------------------------------------------------
# Task 4: Batch insert via client library
# ------------------------------------------------------------
echo "${CYAN}>>> [Task 4] Creating batch_insert.py...${RESET}"
cat > batch_insert.py <<'EOF'
from google.cloud import spanner

INSTANCE_ID = "banking-instance"
DATABASE_ID = "banking-db"

spanner_client = spanner.Client()
instance = spanner_client.instance(INSTANCE_ID)
database = instance.database(DATABASE_ID)

with database.batch() as batch:
    batch.insert(
        table="Customer",
        columns=("CustomerId", "Name", "Location"),
        values=[
            ('edfc683f-bd87-4bab-9423-01d1b2307c0d', 'John Elkins', 'Roy Utah'),
            ('1f3842ca-4529-40ff-acdd-88e8a87eb404', 'Martin Madrid', 'Ames Iowa'),
            ('3320d98e-6437-4515-9e83-137f105f7fbc', 'Theresa Henderson', 'Anna Texas'),
            ('6b2b2774-add9-4881-8702-d179af0518d8', 'Norma Carter', 'Bend Oregon'),
        ],
    )

print("Rows inserted")
EOF

python3 batch_insert.py

# ------------------------------------------------------------
# Task 5: Load data with Dataflow
# ------------------------------------------------------------
echo "${CYAN}>>> [Task 5] Preparing GCS bucket for Dataflow...${RESET}"
gsutil mb gs://$PROJECT_ID || echo "${YELLOW}Bucket already exists${RESET}"
touch emptyfile
gsutil cp emptyfile gs://$PROJECT_ID/tmp/emptyfile

echo "${CYAN}>>> Enabling Dataflow API...${RESET}"
gcloud services disable dataflow.googleapis.com --force
gcloud services enable dataflow.googleapis.com

echo "${CYAN}>>> Running Dataflow job (this may take 12–16 min)...${RESET}"
JOB_OUTPUT=$(gcloud dataflow jobs run spanner-load \
  --gcs-location gs://dataflow-templates/latest/GCS_Text_to_Cloud_Spanner \
  --region=$REGION \
  --parameters instanceId=$INSTANCE_ID,databaseId=$DATABASE_ID,importManifest=gs://cloud-training/OCBL372/manifest.json,tempLocation=gs://$PROJECT_ID/tmp)

echo "${GREEN}>>> Dataflow job submitted.${RESET}"

# Extract link
JOB_LINK=$(echo "$JOB_OUTPUT" | grep "https://console.cloud.google.com/dataflow/jobs" | tail -1)

echo "${MAGENTA}╔════════════════════════════════════════════╗${RESET}"
echo "${MAGENTA}${BOLD} View your Dataflow job here:${RESET}"
echo "${CYAN}$JOB_LINK${RESET}"
echo "${MAGENTA}╚════════════════════════════════════════════╝${RESET}"

# ------------------------------------------------------------
# Verify record count (after Dataflow finishes)
# ------------------------------------------------------------
echo "${CYAN}>>> Verifying row count in Customer table...${RESET}"
gcloud spanner databases execute-sql $DATABASE_ID --instance=$INSTANCE_ID \
 --sql="SELECT COUNT(*) AS total_rows FROM Customer;"

# Completion message
echo
echo "${GREEN}${BOLD}╔════════════════════════════════╗${RESET}"
echo "${GREEN}${BOLD}          LAB COMPLETE!           ${RESET}"
echo "${GREEN}${BOLD}╚════════════════════════════════╝${RESET}"
echo
echo "${BLUE}https://eplus.dev${RESET}"
echo "${MAGENTA}${BOLD}📊 Happy monitoring with Google Managed Prometheus!${RESET}"
