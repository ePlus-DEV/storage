#!/bin/bash
set -e

# =========================
# Color
# =========================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
BUCKET="${PROJECT_ID}-bucket"

LAKE_ID="ecommerce-lake"
ZONE_ID="customer-contact-raw-zone"
ASSET_ID="contact-info"
SCAN_ID="customer-orders-data-quality-job"

echo -e "${BLUE}Project: ${PROJECT_ID}${NC}"
echo -e "${BLUE}Region : ${REGION}${NC}"

# =========================
# Enable APIs
# =========================
echo -e "${YELLOW}Enabling required APIs...${NC}"
gcloud services enable \
  dataplex.googleapis.com \
  datacatalog.googleapis.com \
  bigquery.googleapis.com \
  storage.googleapis.com \
  cloudresourcemanager.googleapis.com

# =========================
# Task 1: Create lake
# =========================
echo -e "${YELLOW}Creating Dataplex lake...${NC}"
if ! gcloud dataplex lakes describe "$LAKE_ID" --location="$REGION" >/dev/null 2>&1; then
  gcloud dataplex lakes create "$LAKE_ID" \
    --location="$REGION" \
    --display-name="Ecommerce Lake"
else
  echo -e "${GREEN}Lake already exists.${NC}"
fi

echo -e "${YELLOW}Waiting for lake to become active...${NC}"
sleep 30

# =========================
# Task 1: Create raw zone
# =========================
echo -e "${YELLOW}Creating raw zone...${NC}"
if ! gcloud dataplex zones describe "$ZONE_ID" \
  --lake="$LAKE_ID" \
  --location="$REGION" >/dev/null 2>&1; then

  gcloud dataplex zones create "$ZONE_ID" \
    --lake="$LAKE_ID" \
    --location="$REGION" \
    --display-name="Customer Contact Raw Zone" \
    --type=RAW \
    --resource-location-type=SINGLE_REGION
else
  echo -e "${GREEN}Zone already exists.${NC}"
fi

echo -e "${YELLOW}Waiting for zone to become active...${NC}"
sleep 60

# =========================
# Task 1: Attach BigQuery dataset as asset
# =========================
echo -e "${YELLOW}Creating BigQuery dataset asset...${NC}"
if ! gcloud dataplex assets describe "$ASSET_ID" \
  --lake="$LAKE_ID" \
  --zone="$ZONE_ID" \
  --location="$REGION" >/dev/null 2>&1; then

  gcloud dataplex assets create "$ASSET_ID" \
    --lake="$LAKE_ID" \
    --zone="$ZONE_ID" \
    --location="$REGION" \
    --display-name="Contact Info" \
    --resource-type=BIGQUERY_DATASET \
    --resource-name="projects/${PROJECT_ID}/datasets/customers" \
    --discovery-enabled
else
  echo -e "${GREEN}Asset already exists.${NC}"
fi

echo -e "${GREEN}Task 1 done. You can click Check my progress.${NC}"

# =========================
# Task 2: Query BigQuery table
# =========================
echo -e "${YELLOW}Running BigQuery query for Task 2...${NC}"
bq query --use_legacy_sql=false "
SELECT *
FROM \`${PROJECT_ID}.customers.contact_info\`
ORDER BY id
LIMIT 50;
"

echo -e "${GREEN}Task 2 done. You can click Check my progress.${NC}"

# =========================
# Task 3: Create YAML file
# =========================
echo -e "${YELLOW}Creating data quality YAML file...${NC}"
cat > dq-customer-raw-data.yaml <<YAML
rules:
- nonNullExpectation: {}
  column: id
  dimension: COMPLETENESS
  threshold: 1
- regexExpectation:
    regex: '^[^@]+[@]{1}[^@]+$'
  column: email
  dimension: CONFORMANCE
  ignoreNull: true
  threshold: .85
postScanActions:
  bigqueryExport:
    resultsTable: projects/${PROJECT_ID}/datasets/customers_dq_dataset/tables/dq_results
YAML

echo -e "${YELLOW}Uploading YAML file to Cloud Storage...${NC}"
gsutil cp dq-customer-raw-data.yaml gs://${BUCKET}/dq-customer-raw-data.yaml

echo -e "${GREEN}Task 3 done. You can click Check my progress.${NC}"

# =========================
# Task 4: Create data quality scan
# =========================
echo -e "${YELLOW}Creating data quality scan...${NC}"
if ! gcloud dataplex datascans describe "$SCAN_ID" \
  --location="$REGION" >/dev/null 2>&1; then

  gcloud dataplex datascans create data-quality "$SCAN_ID" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --data-source-resource="//bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/customers/tables/contact_info" \
    --data-quality-spec-file="gs://${BUCKET}/dq-customer-raw-data.yaml"
else
  echo -e "${GREEN}Data scan already exists.${NC}"
fi

echo -e "${YELLOW}Running data quality scan...${NC}"
gcloud dataplex datascans run "$SCAN_ID" \
  --location="$REGION"

echo -e "${GREEN}Task 4 command done.${NC}"
echo -e "${YELLOW}Wait a few minutes, then check result in Knowledge Catalog / Dataplex.${NC}"

# =========================
# Helper query for Task 5
# =========================
echo -e "${BLUE}After the scan finishes, run this query to view DQ results:${NC}"
cat <<SQL

bq query --use_legacy_sql=false "
SELECT
  rule_name,
  rule_type,
  dimension,
  column_id,
  passed,
  pass_ratio,
  failed_records,
  rule_failed_records_query
FROM \`${PROJECT_ID}.customers_dq_dataset.dq_results\`
ORDER BY invocation_id DESC;
"

SQL

echo -e "${GREEN}All main steps completed. - ePlus.DEV${NC}"