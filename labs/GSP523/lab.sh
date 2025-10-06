#!/bin/bash

# ===============================================
#  Welcome Banner + Subscribe Call-to-Action
# ===============================================

clear
echo -e "\033[1;34m============================================\033[0m"
echo -e "   ▶️  Don't forget to \033[1;31mSUBSCRIBE\033[0m ❤️"
echo -e "   🔗 Channel: \033[1;36mhttps://eplus.dev\033[0m"
echo -e "\033[1;34m============================================\033[0m\n"

# Spinner Function
spinner() {
  local pid=$1
  local delay=0.1
  local spin='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    for i in {0..3}; do
      echo -ne "\r⏳ Loading... ${spin:$i:1} "
      sleep $delay
    done
  done
  echo -ne "\r✅  Ready!             \n"
}

# Short spinner before main script
( sleep 3 ) & spinner $!

# ======================
# Begin Main Script Tasks
# ======================

gcloud auth list

gcloud services enable aiplatform.googleapis.com

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

bq mk --connection --location=$REGION --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE vector_conn

SERVICE_ACCOUNT=$(bq show --format=json --connection $PROJECT_ID.$REGION.vector_conn | jq -r '.cloudResource.serviceAccountId')
echo "Service Account: $SERVICE_ACCOUNT"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/bigquery.dataOwner"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/aiplatform.user"

sleep 20

# Task 2: External Table
bq query --use_legacy_sql=false "
CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT_ID}.gcc_bqml_dataset.gcc_image_object_table\`
WITH CONNECTION \`${REGION}.vector_conn\`
OPTIONS (
  object_metadata = 'SIMPLE',
  uris = ['gs://${PROJECT_ID}/*']
);"

sleep 10

# Task 3: Create Model
bq query --use_legacy_sql=false "
CREATE OR REPLACE MODEL \`${PROJECT_ID}.gcc_bqml_dataset.gcc_embedding\`
REMOTE WITH CONNECTION \`${REGION}.vector_conn\`
OPTIONS (
  endpoint = 'multimodalembedding@001'
);"

sleep 10

# Generate Embeddings
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`${PROJECT_ID}.gcc_bqml_dataset.gcc_retail_store_embeddings\` AS
SELECT *, REGEXP_EXTRACT(uri, r'[^/]+$') AS product_name
FROM ML.GENERATE_EMBEDDING(
  MODEL \`${PROJECT_ID}.gcc_bqml_dataset.gcc_embedding\`,
  TABLE \`${PROJECT_ID}.gcc_bqml_dataset.gcc_image_object_table\`
);"

sleep 10

bq show --format=prettyjson ${PROJECT_ID}:gcc_bqml_dataset.gcc_retail_store_embeddings

sleep 10

# Task 4: Vector Search
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`${PROJECT_ID}.gcc_bqml_dataset.gcc_vector_search_table\` AS
SELECT
  base.uri,
  base.product_name,
  base.content_type,
  distance
FROM VECTOR_SEARCH(
  TABLE \`${PROJECT_ID}.gcc_bqml_dataset.gcc_retail_store_embeddings\`,
  'ml_generate_embedding_result',
  (
    SELECT ml_generate_embedding_result AS embedding_col
    FROM ML.GENERATE_EMBEDDING(
      MODEL \`${PROJECT_ID}.gcc_bqml_dataset.gcc_embedding\`,
      (SELECT 'Men Sweaters' AS content),
      STRUCT(TRUE AS flatten_json_output)
    )
  ),
  top_k => 3,
  distance_type => 'COSINE'
);"

sleep 20

# ===============================================
# Closing Message
# ===============================================
echo -e "\n\033[1;32m🎯 Tutorial Completed Successfully!\033[0m"
echo -e "👉 Don’t forget to Subscribe here: \033[1;36mhttps://eplus.dev\033[0m\n"