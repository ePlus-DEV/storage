#!/bin/bash
# ===================================================================
# 🌐 BigQuery + Gemini Remote Models Automation Script
# 📅 Version: 1.0.0 - 2025-10-06
# 👨‍💻 Author: Nguyễn Ngọc Minh Hoàng (David)
# 🏷️ Copyright © 2025 ePlus.DEV
# 📜 License: MIT – This script is for educational and automation purposes.
# ❗ Do not redistribute without permission from ePlus.DEV
# ===================================================================

# ========================= 🎨 COLOR PALETTE =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ========================= 🔧 SETUP ENVIRONMENT ======================
echo -e "${BLUE}📦 Initializing environment...${NC}"
PROJECT_ID=$(gcloud config get-value project)
REGION="us"
DATASET="gemini_demo"
CONNECTION_ID="gemini_conn"

# Auto-generate bucket name (format: qwiklabs-gcp-xx-<PROJECT_ID>-bucket)
BUCKET_NAME="${PROJECT_ID}-bucket"

echo -e "${YELLOW}🔎 Project ID: ${BOLD}${PROJECT_ID}${NC}"
echo -e "${YELLOW}🌎 Region: ${BOLD}${REGION}${NC}"
echo -e "${YELLOW}📂 Dataset: ${BOLD}${DATASET}${NC}"
echo -e "${YELLOW}🔗 Connection: ${BOLD}${CONNECTION_ID}${NC}"
echo -e "${YELLOW}🪣 Bucket: ${BOLD}${BUCKET_NAME}${NC}"
echo -e "=============================================================="

# ========================= 🛠️ ENABLE APIS ===========================
echo -e "${BLUE}🔧 Enabling Google Cloud APIs...${NC}"
gcloud services enable bigquery.googleapis.com \
    bigqueryconnection.googleapis.com \
    aiplatform.googleapis.com \
    storage.googleapis.com

# ========================= 📁 CREATE DATASET ========================
echo -e "${BLUE}📁 Creating BigQuery dataset...${NC}"
bq --location=$REGION mk -d --description "Gemini Demo Dataset" $PROJECT_ID:$DATASET || echo "✅ Dataset already exists."

# ========================= 🔗 CREATE CONNECTION =====================
echo -e "${BLUE}🔗 Creating connection to Vertex AI...${NC}"
bq mk --connection \
  --display_name="Gemini Connection" \
  --connection_type=CLOUD_RESOURCE \
  --project_id=$PROJECT_ID \
  --location=$REGION \
  $CONNECTION_ID || echo "✅ Connection already exists."

# Get service account of connection
CONN_SA=$(bq show --connection --location=$REGION $PROJECT_ID.$CONNECTION_ID | grep serviceAccountId | awk '{print $2}')
echo -e "${GREEN}✅ Connection service account: ${BOLD}${CONN_SA}${NC}"

# ========================= 🔑 GRANT IAM ROLES =======================
echo -e "${BLUE}🔑 Granting IAM roles...${NC}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CONN_SA" \
  --role="roles/aiplatform.user"

gsutil iam ch serviceAccount:$CONN_SA:roles/storage.objectAdmin gs://$BUCKET_NAME

# ========================= 📤 LOAD CUSTOMER REVIEWS =================
echo -e "${BLUE}📥 Loading customer_reviews.csv into BigQuery...${NC}"
bq query --use_legacy_sql=false "
LOAD DATA OVERWRITE ${DATASET}.customer_reviews
(
  customer_review_id INT64,
  customer_id INT64,
  location_id INT64,
  review_datetime DATETIME,
  review_text STRING,
  social_media_source STRING,
  social_media_handle STRING
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://${BUCKET_NAME}/gsp1246/customer_reviews.csv']
);
"

# ========================= 🖼️ CREATE OBJECT TABLE ===================
echo -e "${BLUE}🖼️ Creating external object table for images...${NC}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE EXTERNAL TABLE ${DATASET}.review_images
WITH CONNECTION \`${REGION}.${CONNECTION_ID}\`
OPTIONS (
  object_metadata = 'SIMPLE',
  uris = ['gs://${BUCKET_NAME}/gsp1246/images/*']
);
"

# ========================= 🤖 CREATE GEMINI MODEL ===================
echo -e "${BLUE}🤖 Creating Gemini 2.0 Flash model...${NC}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE MODEL ${DATASET}.gemini_2_0_flash
REMOTE WITH CONNECTION \`${REGION}.${CONNECTION_ID}\`
OPTIONS (endpoint = 'gemini-2.0-flash');
"

# ========================= 🔍 KEYWORDS EXTRACTION ===================
echo -e "${BLUE}🔍 Running keywords extraction...${NC}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE ${DATASET}.customer_reviews_keywords AS (
  SELECT ml_generate_text_llm_result, social_media_source, review_text, customer_id, location_id, review_datetime
  FROM ML.GENERATE_TEXT(
    MODEL ${DATASET}.gemini_2_0_flash,
    (
      SELECT social_media_source, customer_id, location_id, review_text, review_datetime,
      CONCAT('For each review, provide keywords as JSON list. ', review_text) AS prompt
      FROM ${DATASET}.customer_reviews
    ),
    STRUCT(0.2 AS temperature, TRUE AS flatten_json_output)
  )
);
"

# ========================= 📊 SENTIMENT ANALYSIS ====================
echo -e "${BLUE}📊 Classifying sentiment (positive/negative)...${NC}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE ${DATASET}.customer_reviews_analysis AS (
  SELECT ml_generate_text_llm_result, social_media_source, review_text, customer_id, location_id, review_datetime
  FROM ML.GENERATE_TEXT(
    MODEL ${DATASET}.gemini_2_0_flash,
    (
      SELECT social_media_source, customer_id, location_id, review_text, review_datetime,
      CONCAT('Classify the following text as positive or negative. ', review_text) AS prompt
      FROM ${DATASET}.customer_reviews
    ),
    STRUCT(0.2 AS temperature, TRUE AS flatten_json_output)
  )
);
"

# ========================= 🧹 CLEAN SENTIMENT DATA ==================
echo -e "${BLUE}🧹 Cleaning sentiment data...${NC}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE VIEW ${DATASET}.cleaned_data_view AS
SELECT
  REPLACE(REPLACE(REPLACE(LOWER(ml_generate_text_llm_result), '.', ''), ' ', ''), '\n', '') AS sentiment,
  social_media_source,
  review_text,
  customer_id,
  location_id,
  review_datetime
FROM ${DATASET}.customer_reviews_analysis;
"

# ========================= 🖼️ IMAGE ANALYSIS =======================
echo -e "${BLUE}🖼️ Analyzing review images with Gemini...${NC}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE ${DATASET}.review_images_results AS (
  SELECT uri, ml_generate_text_llm_result
  FROM ML.GENERATE_TEXT(
    MODEL ${DATASET}.gemini_2_0_flash,
    TABLE ${DATASET}.review_images,
    STRUCT(
      0.2 AS temperature,
      'For each image, provide a summary and keywords as JSON.' AS PROMPT,
      TRUE AS FLATTEN_JSON_OUTPUT
    )
  )
);
"

# ========================= ✅ DONE ================================
echo -e "\n${GREEN}🎉 All tasks completed successfully!${NC}"
echo -e "${BOLD}📊 Dataset:${NC} ${YELLOW}${DATASET}${NC}"
echo -e "${BOLD}🔗 BigQuery URL:${NC} https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
echo -e "${BOLD}📜 Script:${NC} ${BLUE}bigquery_gemini_lab.sh${NC} – © 2025 ePlus.DEV"