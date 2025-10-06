#!/bin/bash
# ============================================================
# 🌐 RAG PIPELINE WITH BIGQUERY & VERTEX AI
# 📜 Copyright (c) 2025 ePlus.DEV. All rights reserved.
# 🧑‍💻 Author: Nguyễn Ngọc Minh Hoàng (David) - ePlus.DEV
# 🪪 License: This script is part of Google Cloud Skills Boost lab automation.
# 🔥 Purpose: Automate Tasks 1 → 4 for "Create a RAG Application with BigQuery"
# ============================================================

# ---------[ 🎨 DEFINE COLORS ]------------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

echo -e "${PURPLE}============================================================${RESET}"
echo -e "🌐 ${CYAN}Create a RAG Application with BigQuery - GSP1289${RESET}"
echo -e "📜 ${YELLOW}Copyright (c) 2025 ePlus.DEV | All rights reserved.${RESET}"
echo -e "${PURPLE}============================================================${RESET}"
echo ""

# ---------[ 0. SETUP ENVIRONMENT VARIABLES ]-----------------
echo -e "${BLUE}🔧 Setting up environment variables...${RESET}"
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us"  # ✅ Always use 'us' (multi-region) to avoid location constraint issues

echo -e "✅ ${WHITE}Project ID:${RESET} ${CYAN}$PROJECT_ID${RESET}"
echo -e "✅ ${WHITE}Region:${RESET} ${CYAN}$REGION${RESET}"
sleep 2

# ---------[ 1. ENABLE REQUIRED APIS ]------------------------
echo -e "\n${BLUE}🚀 Enabling required APIs...${RESET}"
gcloud services enable bigquery.googleapis.com aiplatform.googleapis.com
echo -e "✅ ${GREEN}APIs enabled successfully!${RESET}"
sleep 2

# ---------[ 2. CREATE DATASET IN BIGQUERY ]-----------------
echo -e "\n${BLUE}📁 Creating BigQuery dataset...${RESET}"
bq --location=$REGION mk --dataset ${PROJECT_ID}:CustomerReview || echo -e "⚠️ ${YELLOW}Dataset already exists${RESET}"
sleep 2

# ---------[ 3. CREATE EMBEDDING MODEL ]---------------------
echo -e "\n${BLUE}🧠 Creating embedding model...${RESET}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE MODEL \`${PROJECT_ID}.CustomerReview.Embeddings\`
REMOTE WITH CONNECTION \`${REGION}.embedding_conn\`
OPTIONS (ENDPOINT = 'text-embedding-005');
"
echo -e "✅ ${GREEN}Embedding model created!${RESET}"
sleep 2

# ---------[ 4. LOAD CSV DATA INTO BIGQUERY ]---------------
echo -e "\n${BLUE}📊 Loading customer review CSV into BigQuery...${RESET}"
bq query --use_legacy_sql=false "
LOAD DATA OVERWRITE ${PROJECT_ID}.CustomerReview.customer_reviews
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
    uris = ['gs://spls/gsp1249/customer_reviews.csv']
);
"
echo -e "✅ ${GREEN}Customer review data loaded successfully!${RESET}"
sleep 2

# ---------[ 5. GENERATE EMBEDDINGS FROM TEXT ]-------------
echo -e "\n${BLUE}🧬 Generating vector embeddings from reviews...${RESET}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`${PROJECT_ID}.CustomerReview.customer_reviews_embedded\` AS
SELECT *
FROM ML.GENERATE_EMBEDDING(
    MODEL \`${PROJECT_ID}.CustomerReview.Embeddings\`,
    (
      SELECT review_text AS content
      FROM \`${PROJECT_ID}.CustomerReview.customer_reviews\`
    )
);
"
echo -e "✅ ${GREEN}Embeddings generated successfully!${RESET}"
sleep 2

# ---------[ 6. CREATE VECTOR INDEX (optional) ]------------
echo -e "\n${BLUE}📚 Creating vector index (optional)...${RESET}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE VECTOR INDEX \`${PROJECT_ID}.CustomerReview.reviews_index\`
ON \`${PROJECT_ID}.CustomerReview.customer_reviews_embedded\`(ml_generate_embedding_result)
OPTIONS (distance_type = 'COSINE', index_type = 'IVF');
"
echo -e "✅ ${GREEN}Vector index created!${RESET}"
sleep 2

# ---------[ 7. PERFORM VECTOR SEARCH ]---------------------
echo -e "\n${BLUE}🔎 Performing vector search for query 'service'...${RESET}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`${PROJECT_ID}.CustomerReview.vector_search_result\` AS
SELECT
    query.query,
    base.content
FROM
    VECTOR_SEARCH(
        TABLE \`${PROJECT_ID}.CustomerReview.customer_reviews_embedded\`,
        'ml_generate_embedding_result',
        (
            SELECT
                ml_generate_embedding_result,
                content AS query
            FROM
                ML.GENERATE_EMBEDDING(
                    MODEL \`${PROJECT_ID}.CustomerReview.Embeddings\`,
                    (SELECT 'service' AS content)
                )
        ),
        top_k => 5,
        options => '{\"fraction_lists_to_search\": 0.01}'
    );
"
echo -e "✅ ${GREEN}Vector search completed successfully!${RESET}"
sleep 2

# ---------[ 8. CREATE GEMINI MODEL ]-----------------------
echo -e "\n${BLUE}🤖 Creating Gemini LLM model...${RESET}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE MODEL \`${PROJECT_ID}.CustomerReview.Gemini\`
REMOTE WITH CONNECTION \`${REGION}.embedding_conn\`
OPTIONS (ENDPOINT = 'gemini-2.0-flash');
"
echo -e "✅ ${GREEN}Gemini model created!${RESET}"
sleep 2

# ---------[ 9. GENERATE RAG-BASED RESPONSE ]---------------
echo -e "\n${BLUE}💡 Generating enhanced RAG-based response...${RESET}"
bq query --use_legacy_sql=false "
SELECT
    ml_generate_text_llm_result AS generated
FROM
    ML.GENERATE_TEXT(
        MODEL \`${PROJECT_ID}.CustomerReview.Gemini\`,
        (
            SELECT
                CONCAT(
                    'Summarize what customers think about our services: ',
                    STRING_AGG(FORMAT('review text: %s', base.content), ',\n')
                ) AS prompt
            FROM
                \`${PROJECT_ID}.CustomerReview.vector_search_result\` AS base
        ),
        STRUCT(
            0.4 AS temperature,
            300 AS max_output_tokens,
            0.5 AS top_p,
            5 AS top_k,
            TRUE AS flatten_json_output
        )
    );
"
echo -e "✅ ${GREEN}Enhanced response generated successfully!${RESET}"
sleep 2

# ---------[ ✅ FINISH ]------------------------------------
echo -e "\n${PURPLE}============================================================${RESET}"
echo -e "🎉 ${GREEN}RAG pipeline completed successfully!${RESET}"
echo -e "📊 ${WHITE}Result:${RESET} Check the output of the last query above 👆"
echo -e "📜 ${YELLOW}Copyright © 2025 ePlus.DEV - All rights reserved.${RESET}"
echo -e "${PURPLE}============================================================${RESET}"