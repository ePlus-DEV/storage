#!/bin/bash
# ============================================================
#  Qwiklabs: Cloud Spanner + Dataflow Lab Automation Script
#  Author: David's Assistant
#  Copyright (c) 2025 David Nguyen. All rights reserved.
# ============================================================

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}   🚀 Starting Cloud Spanner + Dataflow Automation Script   ${NC}"
echo -e "${CYAN}============================================================${NC}"

# Project and instance setup
PROJECT_ID=$(gcloud config get-value project)
INSTANCE_ID="banking-instance"
DATABASE_ID="banking-db"
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo -e "${YELLOW}>>> Current Project:${NC} $PROJECT_ID"
echo -e "${YELLOW}>>> Using Spanner Instance:${NC} $INSTANCE_ID"
echo -e "${YELLOW}>>> Using Database:${NC} $DATABASE_ID"
echo -e "${YELLOW}>>> Using Region:${NC} $REGION"

# ------------------------------------------------------------
# Task 2: Insert data with DML (gcloud)
# ------------------------------------------------------------
echo -e "${CYAN}>>> [Task 2] Inserting single record via DML...${NC}"
gcloud spanner databases execute-sql $DATABASE_ID --instance=$INSTANCE_ID \
 --sql="INSERT INTO Customer (CustomerId, Name, Location) VALUES ('bdaaaa97-1b4b-4e58-b4ad-84030de92235', 'Richard Nelson', 'Ada Ohio')"

# ------------------------------------------------------------
# Task 3: Insert data through Python client library
# ------------------------------------------------------------
echo -e "${CYAN}>>> [Task 3] Creating insert.py...${NC}"
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

echo -e "${GREEN}>>> Running insert.py...${NC}"
python3 insert.py

# ------------------------------------------------------------
# Task 4: Insert batch data via Python client library
# ------------------------------------------------------------
echo -e "${CYAN}>>> [Task 4] Creating batch_insert.py...${NC}"
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

echo -e "${GREEN}>>> Running batch_insert.py...${NC}"
python3 batch_insert.py

# ------------------------------------------------------------
# Task 5: Load data with Dataflow (gcloud)
# ------------------------------------------------------------
echo -e "${CYAN}>>> [Task 5] Preparing GCS bucket for Dataflow...${NC}"
gsutil mb -p $PROJECT_ID gs://$PROJECT_ID || echo -e "${YELLOW}Bucket already exists${NC}"
touch emptyfile
gsutil cp emptyfile gs://$PROJECT_ID/tmp/emptyfile

echo -e "${CYAN}>>> Resetting Dataflow API...${NC}"
gcloud services disable dataflow.googleapis.com --force
gcloud services enable dataflow.googleapis.com

echo -e "${CYAN}>>> Running Dataflow job (this will take ~12–16 min)...${NC}"
JOB_OUTPUT=$(gcloud dataflow jobs run spanner-load \
  --gcs-location gs://dataflow-templates/latest/GCS_Text_to_Cloud_Spanner \
  --region=$REGION \
  --parameters \
inputFile=gs://cloud-training/OCBL372/Customer_List.csv,\
instanceId=$INSTANCE_ID,\
databaseId=$DATABASE_ID,\
table=Customer,\
tempLocation=gs://$PROJECT_ID/tmp)

echo -e "${GREEN}>>> Dataflow job submitted successfully.${NC}"

# Extract link from job output
JOB_LINK=$(echo "$JOB_OUTPUT" | grep "https://console.cloud.google.com/dataflow/jobs" | tail -1)

echo -e "${RED}============================================================${NC}"
echo -e "${GREEN}>>> 🌐 View your Dataflow job here:${NC}"
echo -e "${CYAN}$JOB_LINK${NC}"
echo -e "${RED}============================================================${NC}"

# Verify row count (after Dataflow completes)
echo -e "${CYAN}>>> To verify total rows after Dataflow load, run in Spanner Studio:${NC}"
echo -e "${YELLOW}    SELECT COUNT(*) FROM Customer;${NC}"

echo -e "${GREEN}>>> ✅ Script completed (Dataflow job running in background).${NC}"