#!/bin/bash
# ============================================================
#  Qwiklabs: Cloud Spanner + Dataflow Lab Automation Script
#  Author: David Nguyen (ePlus.DEV)
#  Copyright (c) 2025 David Nguyen. All rights reserved.
# ============================================================

# Colors
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
CYAN=$'\033[0;96m'
RESET=$'\033[0m'
BOLD=$(tput bold)

# Setup
PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud config get-value compute/region)
INSTANCE_ID="banking-instance"
DATABASE_ID="banking-db"

echo "${CYAN}${BOLD}>>> Project:${RESET} $PROJECT_ID"
echo "${CYAN}${BOLD}>>> Region:${RESET} $REGION"
echo "${CYAN}${BOLD}>>> Instance:${RESET} $INSTANCE_ID"
echo "${CYAN}${BOLD}>>> Database:${RESET} $DATABASE_ID"

# ------------------------------------------------------------
# Task 2: Insert data with DML
# ------------------------------------------------------------
echo "${CYAN}>>> [Task 2] Insert single record via DML...${RESET}"
gcloud spanner databases execute-sql $DATABASE_ID --instance=$INSTANCE_ID \
 --sql="INSERT INTO Customer (CustomerId, Name, Location) VALUES ('bdaaaa97-1b4b-4e58-b4ad-84030de92235', 'Richard Nelson', 'Ada Ohio')"

# ------------------------------------------------------------
# Task 3: Insert via client library (Python)
# ------------------------------------------------------------
echo "${CYAN}>>> [Task 3] Insert record via Python client...${RESET}"
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
echo "${CYAN}>>> [Task 4] Cleaning old Task 4 rows (if any)...${RESET}"
gcloud spanner databases execute-sql $DATABASE_ID --instance=$INSTANCE_ID \
 --sql="DELETE FROM Customer WHERE CustomerId IN (
 'edfc683f-bd87-4bab-9423-01d1b2307c0d',
 '1f3842ca-4529-40ff-acdd-88e8a87eb404',
 '3320d98e-6437-4515-9e83-137f105f7fbc',
 '6b2b2774-add9-4881-8702-d179af0518d8');"

echo "${CYAN}>>> [Task 4] Batch insert records...${RESET}"
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

print("✅ Task 4 Batch insert done")
EOF
python3 batch_insert.py

echo "${YELLOW}>>> Verify Task 4 rows...${RESET}"
gcloud spanner databases execute-sql $DATABASE_ID --instance=$INSTANCE_ID \
 --sql="SELECT COUNT(*) AS cnt FROM Customer WHERE CustomerId IN (
 'edfc683f-bd87-4bab-9423-01d1b2307c0d',
 '1f3842ca-4529-40ff-acdd-88e8a87eb404',
 '3320d98e-6437-4515-9e83-137f105f7fbc',
 '6b2b2774-add9-4881-8702-d179af0518d8');"

echo
read -p ">>> Did you click 'Check my progress' for Task 4 in Qwiklabs? (Y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "⏸ Script stopped. Please check Task 4 in Qwiklabs, then re-run to continue."
  exit 0
fi

# ------------------------------------------------------------
# Task 5: Load data with Dataflow
# ------------------------------------------------------------
echo "${CYAN}>>> [Task 5] Preparing GCS bucket for Dataflow...${RESET}"
gsutil mb gs://$PROJECT_ID || echo "Bucket already exists"
touch emptyfile
gsutil cp emptyfile gs://$PROJECT_ID/tmp/emptyfile

echo "${CYAN}>>> Enable Dataflow API...${RESET}"
gcloud services disable dataflow.googleapis.com --force
gcloud services enable dataflow.googleapis.com

echo "${CYAN}>>> Running Dataflow job (this will take 12–16 min)...${RESET}"
JOB_OUTPUT=$(gcloud dataflow jobs run spanner-load \
  --gcs-location gs://dataflow-templates/latest/GCS_Text_to_Cloud_Spanner \
  --region=$REGION \
  --staging-location gs://$PROJECT_ID/tmp \
  --parameters instanceId=$INSTANCE_ID,databaseId=$DATABASE_ID,importManifest=gs://cloud-training/OCBL372/manifest.json)

JOB_LINK=$(echo "$JOB_OUTPUT" | grep "https://console.cloud.google.com/dataflow/jobs" | tail -1)

echo "${GREEN}>>> Dataflow job submitted.${RESET}"
echo "${CYAN}View job: $JOB_LINK${RESET}"

echo "${YELLOW}>>> After Dataflow finishes, verify row count with:${RESET}"
echo "gcloud spanner databases execute-sql $DATABASE_ID --instance=$INSTANCE_ID --sql=\"SELECT COUNT(*) FROM Customer;\""

echo
echo "${GREEN}${BOLD}>>> LAB COMPLETE! 🎉${RESET}"