#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -euo pipefail

# Do not erase unrelated Cloud Shell files; this script only creates lab resources.
# ANSI output is optional; do not fail when running without a TTY.
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]] && command -v tput >/dev/null 2>&1; then
  BLACK="$(tput setaf 0)"; RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"; BLUE="$(tput setaf 4)"; MAGENTA="$(tput setaf 5)"
  CYAN="$(tput setaf 6)"; WHITE="$(tput setaf 7)"
  BG_BLACK="$(tput setab 0)"; BG_RED="$(tput setab 1)"; BG_GREEN="$(tput setab 2)"
  BG_YELLOW="$(tput setab 3)"; BG_BLUE="$(tput setab 4)"; BG_MAGENTA="$(tput setab 5)"
  BG_CYAN="$(tput setab 6)"; BG_WHITE="$(tput setab 7)"
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
else
  BLACK=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; WHITE=''
  BG_BLACK=''; BG_RED=''; BG_GREEN=''; BG_YELLOW=''; BG_BLUE=''; BG_MAGENTA=''; BG_CYAN=''; BG_WHITE=''
  BOLD=''; RESET=''
fi

# Array of color codes excluding black and white
TEXT_COLORS=("$RED" "$GREEN" "$YELLOW" "$BLUE" "$MAGENTA" "$CYAN")
BG_COLORS=("$BG_RED" "$BG_GREEN" "$BG_YELLOW" "$BG_BLUE" "$BG_MAGENTA" "$BG_CYAN")

# Pick random colors
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

#----------------------------------------------------start--------------------------------------------------#

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}ePlus.DEV – Starting Execution${RESET}"

# Step 1: Create a Cloud Resource Connection
echo "${BLUE}${BOLD}Creating a Cloud Resource Connection${RESET}"
bq mk --connection --location=US --project_id=$DEVSHELL_PROJECT_ID --connection_type=CLOUD_RESOURCE gemini_conn

# Step 2: Export Service Account ID
echo "${GREEN}${BOLD}Exporting Service Account ID${RESET}"
export SERVICE_ACCOUNT=$(bq show --format=json --connection $DEVSHELL_PROJECT_ID.US.gemini_conn | jq -r '.cloudResource.serviceAccountId')

# Step 3: Add IAM Policy Binding to Project
echo "${YELLOW}${BOLD}Adding IAM Policy Binding to Project${RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member=serviceAccount:$SERVICE_ACCOUNT \
    --role="roles/aiplatform.user"

# Step 4: Add IAM Policy Binding to GCS Bucket
echo "${MAGENTA}${BOLD}Adding IAM Policy Binding to GCS Bucket${RESET}"
gcloud storage buckets add-iam-policy-binding gs://$DEVSHELL_PROJECT_ID-bucket \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/storage.objectAdmin"

# Step 5: Create BigQuery Dataset
echo "${CYAN}${BOLD}Creating BigQuery Dataset${RESET}"
bq mk gemini_demo

# Step 6: Load Customer Reviews Data
echo "${RED}${BOLD}Loading Customer Reviews Data${RESET}"
bq query --use_legacy_sql=false \
"LOAD DATA OVERWRITE gemini_demo.customer_reviews
(customer_review_id INT64, customer_id INT64, location_id INT64, review_datetime DATETIME, review_text STRING, social_media_source STRING, social_media_handle STRING)
FROM FILES (
  format = 'CSV',
  uris = ['gs://$DEVSHELL_PROJECT_ID-bucket/gsp1249/customer_reviews.csv']);"

# Step 7: Query Customer Reviews Table
echo "${BLUE}${BOLD}Querying Customer Reviews Table${RESET}"
bq query --nouse_legacy_sql \
'SELECT * FROM `gemini_demo.customer_reviews` 
ORDER BY review_datetime'

echo

sleep 30

# Step 8: Create Remote Model with Connection
echo "${GREEN}${BOLD}Creating Remote Model with Connection${RESET}"
bq query --use_legacy_sql=false \
"
CREATE OR REPLACE MODEL \`gemini_demo.gemini_pro\`
REMOTE WITH CONNECTION \`us.gemini_conn\`
OPTIONS (endpoint = 'gemini-pro')
"

# Step 9: Wait for Model to Deploy
echo "${YELLOW}${BOLD}Waiting for Model to Deploy${RESET}"
sleep 30

# Step 10: Generate Sentiment Analysis Results
echo "${MAGENTA}${BOLD}Generating Sentiment Analysis Results${RESET}"
bq query --nouse_legacy_sql \
'CREATE OR REPLACE TABLE
`gemini_demo.customer_reviews_analysis` AS (
SELECT ml_generate_text_llm_result, social_media_source, review_text, customer_id, location_id, review_datetime
FROM
ML.GENERATE_TEXT(
MODEL `gemini_demo.gemini_pro`,
(
   SELECT social_media_source, customer_id, location_id, review_text, review_datetime, CONCAT(
      "Classify the sentiment of the following text as positive or negative. ",
      review_text, " In your response don''t include the sentiment explanation. Remove all extraneous information from your response, it should be a boolean response either positive or negative.") AS prompt
   FROM `gemini_demo.customer_reviews`
),
STRUCT(
   0.2 AS temperature, TRUE AS flatten_json_output)))'

# Step 12: Query Customer Reviews Analysis Table
echo "${BLUE}${BOLD}Querying Customer Reviews Analysis Table${RESET}"
bq query --nouse_legacy_sql \
'SELECT *
FROM `gemini_demo.customer_reviews_analysis`
ORDER BY review_datetime'

echo

# Step 13: Create Cleaned Data View
echo "${GREEN}${BOLD}Creating Cleaned Data View${RESET}"
bq query --nouse_legacy_sql \
'CREATE OR REPLACE VIEW `gemini_demo.cleaned_data_view` AS
SELECT 
  REPLACE(REPLACE(LOWER(ml_generate_text_llm_result), ".", ""), " ", "") AS sentiment,
  REGEXP_REPLACE(
    REGEXP_REPLACE(
      REGEXP_REPLACE(social_media_source, r"Google(\+|\sReviews|\sLocal|\sMy\sBusiness|\sreviews|\sMaps)?", "Google"),
      "YELP", "Yelp"
    ),
    r"SocialMedia1?", "Social Media"
  ) AS social_media_source,
  review_text, 
  customer_id, 
  location_id, 
  review_datetime
FROM `gemini_demo.customer_reviews_analysis`'

# Step 14: Query Cleaned Data View
echo "${YELLOW}${BOLD}Querying Cleaned Data View${RESET}"
bq query --nouse_legacy_sql \
'SELECT * 
FROM `gemini_demo.cleaned_data_view`
ORDER BY review_datetime'

echo

# Step 15: Summarize Sentiment Analysis Results
echo "${MAGENTA}${BOLD}Summarizing Sentiment Analysis Results${RESET}"
bq query --nouse_legacy_sql \
'SELECT sentiment, COUNT(*) AS count
FROM `gemini_demo.cleaned_data_view`
WHERE sentiment IN ("positive", "negative")
GROUP BY sentiment'

echo

printf '\nAll GSP1249 CLI steps finished. Verify each Check my progress in Google Skills.\n'
