#!/bin/bash
# ==============================================================
#  © ePlus.DEV - BigLake and Sensitive Data Aspect Challenge Lab
# ==============================================================

# Define color variables
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---------------------------------------------------- start ---------------------------------------------------- #

echo "${BG_MAGENTA}${WHITE}${BOLD}  © ePlus.DEV - Starting Execution  ${RESET}"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
BQ_LOCATION="US"
DATAPLEX_LOCATION="us"
DATASET_NAME="ecommerce"
CONNECTION_ID="customer_data_connection"
TABLE_NAME="customer_online_sessions"
ASPECT_TYPE_ID="sensitive-data-aspect"
GCS_URI="gs://qwiklabs-gcp-04-3793299b45dd-bucket/customer-online-sessions.csv"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "${RED}${BOLD}ERROR: Google Cloud project is not configured.${RESET}"
  exit 1
fi

echo "${CYAN}${BOLD}Project ID :${RESET} $PROJECT_ID"
echo "${CYAN}${BOLD}Location   :${RESET} $BQ_LOCATION"
echo

# Enable required APIs
echo "${YELLOW}${BOLD}[1/6] Enabling required APIs...${RESET}"
gcloud services enable \
  bigquery.googleapis.com \
  bigqueryconnection.googleapis.com \
  dataplex.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet || exit 1

# Task 1: Create the BigQuery dataset in the US multi-region
echo "${YELLOW}${BOLD}[2/6] Creating BigQuery dataset: $DATASET_NAME...${RESET}"
if bq show "$PROJECT_ID:$DATASET_NAME" >/dev/null 2>&1; then
  echo "${GREEN}Dataset already exists.${RESET}"
else
  bq --location="$BQ_LOCATION" mk \
    --dataset \
    "$PROJECT_ID:$DATASET_NAME" || exit 1
fi

# Task 2: Create the Cloud Resource connection
echo "${YELLOW}${BOLD}[3/6] Creating Cloud Resource connection: $CONNECTION_ID...${RESET}"
if bq show --connection "$PROJECT_ID.$BQ_LOCATION.$CONNECTION_ID" >/dev/null 2>&1; then
  echo "${GREEN}Connection already exists.${RESET}"
else
  bq mk \
    --connection \
    --location="$BQ_LOCATION" \
    --project_id="$PROJECT_ID" \
    --connection_type=CLOUD_RESOURCE \
    "$CONNECTION_ID" || exit 1
fi

# Get the connection service account without grep/awk character trimming
echo "${YELLOW}${BOLD}[4/6] Granting Cloud Storage read permission...${RESET}"
CONNECTION_SA=$(bq show \
  --format=prettyjson \
  --connection "$PROJECT_ID.$BQ_LOCATION.$CONNECTION_ID" \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["cloudResource"]["serviceAccountId"])')

if [[ -z "$CONNECTION_SA" ]]; then
  echo "${RED}${BOLD}ERROR: Could not read the connection service account.${RESET}"
  exit 1
fi

echo "${CYAN}Connection service account: $CONNECTION_SA${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$CONNECTION_SA" \
  --role="roles/storage.objectViewer" \
  --condition=None \
  --quiet >/dev/null || exit 1

# Allow the IAM binding to become available before schema auto-detection
sleep 15

# Create a BigLake external table with the connection and schema auto-detection
echo "${YELLOW}${BOLD}[5/6] Creating BigLake table: $TABLE_NAME...${RESET}"

bq rm -f -t "$PROJECT_ID:$DATASET_NAME.$TABLE_NAME" >/dev/null 2>&1

bq mkdef \
  --source_format=CSV \
  --autodetect=true \
  --connection_id="$PROJECT_ID.$BQ_LOCATION.$CONNECTION_ID" \
  "$GCS_URI" > biglake_table_definition.json || exit 1

bq --location="$BQ_LOCATION" mk \
  --table \
  --external_table_definition=biglake_table_definition.json \
  "$PROJECT_ID:$DATASET_NAME.$TABLE_NAME" || exit 1

# Task 3: Create the Sensitive Data Aspect type
echo "${YELLOW}${BOLD}[6/6] Creating and applying Sensitive Data Aspect...${RESET}"

cat > sensitive_data_aspect_type.json <<'EOF'
{
  "name": "SensitiveDataAspect",
  "type": "record",
  "recordFields": [
    {
      "name": "has_sensitive_data",
      "type": "bool",
      "index": 1,
      "annotations": {
        "displayName": "Has Sensitive Data",
        "displayOrder": 1
      }
    },
    {
      "name": "sensitive_data_type",
      "type": "enum",
      "index": 2,
      "enumValues": [
        {
          "name": "Location Info",
          "index": 1
        },
        {
          "name": "Contact Info",
          "index": 2
        },
        {
          "name": "None",
          "index": 3
        }
      ],
      "annotations": {
        "displayName": "Sensitive Data Type",
        "displayOrder": 2
      }
    }
  ]
}
EOF

if gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" \
  --location="$DATAPLEX_LOCATION" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "${GREEN}Aspect type already exists.${RESET}"
else
  gcloud dataplex aspect-types create "$ASPECT_TYPE_ID" \
    --location="$DATAPLEX_LOCATION" \
    --project="$PROJECT_ID" \
    --display-name="Sensitive Data Aspect" \
    --metadata-template-file-name=sensitive_data_aspect_type.json \
    --quiet || exit 1
fi

cat > sensitive_data_aspect_values.json <<EOF
{
  "$PROJECT_ID.$DATAPLEX_LOCATION.$ASPECT_TYPE_ID": {
    "data": {
      "has_sensitive_data": true,
      "sensitive_data_type": "Location Info"
    }
  }
}
EOF

ENTRY_NAME="projects/$PROJECT_ID/locations/$DATAPLEX_LOCATION/entryGroups/@bigquery/entries/bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DATASET_NAME/tables/$TABLE_NAME"

ASPECT_APPLIED=false
for ATTEMPT in 1 2 3 4 5 6; do
  if gcloud dataplex entries modify "$ENTRY_NAME" \
    --update-aspects=sensitive_data_aspect_values.json \
    --project="$PROJECT_ID" \
    --quiet; then
    ASPECT_APPLIED=true
    break
  fi

  echo "${YELLOW}Knowledge Catalog entry is not ready. Retrying ($ATTEMPT/6)...${RESET}"
  sleep 10
done

if [[ "$ASPECT_APPLIED" != "true" ]]; then
  echo "${RED}${BOLD}ERROR: Could not apply the aspect to the BigQuery table.${RESET}"
  exit 1
fi

echo
echo "${GREEN}${BOLD}Dataset   : $PROJECT_ID:$DATASET_NAME${RESET}"
echo "${GREEN}${BOLD}Connection: $PROJECT_ID.$BQ_LOCATION.$CONNECTION_ID${RESET}"
echo "${GREEN}${BOLD}Table     : $PROJECT_ID:$DATASET_NAME.$TABLE_NAME${RESET}"
echo "${GREEN}${BOLD}Aspect    : Sensitive Data Aspect${RESET}"
echo "${GREEN}${BOLD}Values    : Has Sensitive Data = TRUE; Sensitive Data Type = Location Info${RESET}"
echo
echo "${BG_RED}${WHITE}${BOLD}  Congratulations For Completing The Lab !!!  ${RESET}"

# ----------------------------------------------------- end ----------------------------------------------------- #