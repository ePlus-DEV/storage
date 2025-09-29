#!/bin/bash
# © 2025 Eplus.Dev - All Rights Reserved

# ====== COLOR ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# ====== CONFIG ======
CUSTOMER_PROJECT="qwiklabs-gcp-04-7d5861d831d8"
CUSTOMER_DATASET="customer_dataset"
CUSTOMER_VIEW="customer_authorized_view_mz9o"

PARTNER_PROJECT="qwiklabs-gcp-01-b5652795dd71"
PARTNER_DATASET="demo_dataset"
PARTNER_VIEW="authorized_view_b9g4"
PARTNER_USER="student-00-30098cb3cb36@qwiklabs.net"

echo -e "${BLUE}=============================="
echo -e "STEP 2: Update Customer Table"
echo -e "==============================${NC}"

# Set project
gcloud config set project $CUSTOMER_PROJECT >/dev/null 2>&1

# Update county values
echo -e "${YELLOW}📊 Updating customer table with county data...${NC}"
bq query --use_legacy_sql=false "
UPDATE \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.customer_info\` cust
SET cust.county = vw.county
FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${PARTNER_VIEW}\` vw
WHERE vw.zip_code = cust.postal_code;
" && echo -e "${GREEN}✅ Customer table updated.${NC}"

echo -e "${BLUE}=============================="
echo -e "STEP 3: Create Customer Authorized View"
echo -e "==============================${NC}"

# Create view
echo -e "${YELLOW}📊 Creating customer authorized view...${NC}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE VIEW \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_VIEW}\` AS
SELECT county, COUNT(1) AS Count
FROM \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.customer_info\` cust
GROUP BY county
HAVING county IS NOT NULL;
" && echo -e "${GREEN}✅ Customer authorized view created.${NC}"

# Grant IAM to partner user
echo -e "${YELLOW}🔑 Granting Data Viewer role to partner user...${NC}"
gcloud projects add-iam-policy-binding $CUSTOMER_PROJECT \
  --member="user:${PARTNER_USER}" \
  --role="roles/bigquery.dataViewer" >/dev/null 2>&1 && \
  echo -e "${GREEN}✅ Partner user granted access.${NC}" || \
  echo -e "${RED}❌ Could not grant IAM. Please do it manually in IAM console.${NC}"

echo -e "${GREEN}🎉 DONE! Task 2 and 3 completed successfully.${NC}"
echo -e "${BLUE}➡️ Next: Create the Looker Studio visualization manually.${NC}"
