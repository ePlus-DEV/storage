#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================
#        © ePlus.DEV - BigLake Challenge Lab Solution
# ==============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}▶ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail()    { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }

trap 'echo -e "${RED}✗ Failed at line ${LINENO}: ${BASH_COMMAND}${NC}" >&2' ERR

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
BQ_LOCATION="US"
DATAPLEX_LOCATION="us"
DATASET_ID="ecommerce"
CONNECTION_ID="customer_data_connection"
TABLE_ID="customer_online_sessions"
BUCKET_NAME="qwiklabs-gcp-04-3793299b45dd-bucket"
SOURCE_URI="gs://${BUCKET_NAME}/customer-online-sessions.csv"
ASPECT_TYPE_ID="sensitive-data-aspect"

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || fail "Google Cloud project is not set."

clear
printf "${CYAN}"
printf '╔══════════════════════════════════════════════════════╗\n'
printf '║       © ePlus.DEV - BigLake Challenge Lab          ║\n'
printf '╚══════════════════════════════════════════════════════╝\n'
printf "${NC}\n"
printf 'Project ID : %s\n' "$PROJECT_ID"
printf 'Dataset    : %s\n' "$DATASET_ID"
printf 'Connection : %s\n' "$CONNECTION_ID"
printf 'Table      : %s\n\n' "$TABLE_ID"

# --------------------------------------------------------------
# Task 1: Create the BigQuery dataset
# --------------------------------------------------------------
info "Enabling required APIs..."
gcloud services enable \
  bigquery.googleapis.com \
  bigqueryconnection.googleapis.com \
  dataplex.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet
success "Required APIs are enabled."

info "Creating BigQuery dataset ${DATASET_ID} in US..."
if bq show --project_id="$PROJECT_ID" "${PROJECT_ID}:${DATASET_ID}" >/dev/null 2>&1; then
  success "Dataset ${DATASET_ID} already exists."
else
  bq mk \
    --project_id="$PROJECT_ID" \
    --location="$BQ_LOCATION" \
    --dataset "${PROJECT_ID}:${DATASET_ID}"
  success "Dataset ${DATASET_ID} created."
fi

# --------------------------------------------------------------
# Task 2: Create Cloud Resource connection and BigLake table
# --------------------------------------------------------------
info "Creating Cloud Resource connection ${CONNECTION_ID}..."
if bq show \
  --connection \
  --project_id="$PROJECT_ID" \
  --location="$BQ_LOCATION" \
  "${PROJECT_ID}.${DATAPLEX_LOCATION}.${CONNECTION_ID}" >/dev/null 2>&1; then
  success "Connection ${CONNECTION_ID} already exists."
else
  bq mk \
    --connection \
    --project_id="$PROJECT_ID" \
    --location="$BQ_LOCATION" \
    --connection_type=CLOUD_RESOURCE \
    "$CONNECTION_ID"
  success "Connection ${CONNECTION_ID} created."
fi

info "Getting the connection service account..."
CONNECTION_SA=""
for attempt in {1..10}; do
  CONNECTION_SA="$(
    bq show \
      --connection \
      --project_id="$PROJECT_ID" \
      --location="$BQ_LOCATION" \
      --format=json \
      "${PROJECT_ID}.${DATAPLEX_LOCATION}.${CONNECTION_ID}" 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cloudResource", {}).get("serviceAccountId", ""))' \
      || true
  )"

  [[ -n "$CONNECTION_SA" ]] && break
  sleep 3
done

[[ -n "$CONNECTION_SA" ]] || fail "Could not get the connection service account."
printf 'Connection service account: %s\n' "$CONNECTION_SA"

info "Granting Storage Object Viewer to the connection service account..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${CONNECTION_SA}" \
  --role="roles/storage.objectViewer" \
  --condition=None \
  --quiet >/dev/null
success "Storage permission granted."

info "Creating BigLake table ${DATASET_ID}.${TABLE_ID}..."
bq query \
  --project_id="$PROJECT_ID" \
  --location="$BQ_LOCATION" \
  --use_legacy_sql=false \
  "CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT_ID}.${DATASET_ID}.${TABLE_ID}\`
   WITH CONNECTION \`${PROJECT_ID}.${DATAPLEX_LOCATION}.${CONNECTION_ID}\`
   OPTIONS (
     format = 'CSV',
     uris = ['${SOURCE_URI}'],
     skip_leading_rows = 1
   );"
success "BigLake table created with schema auto-detection."

# --------------------------------------------------------------
# Task 3: Create and apply the Sensitive Data Aspect
# --------------------------------------------------------------
ASPECT_TEMPLATE="${HOME}/sensitive_data_aspect.json"
ASPECT_VALUES="${HOME}/sensitive_data_values.yaml"

cat > "$ASPECT_TEMPLATE" <<'JSON'
{
  "name": "sensitive_data_aspect",
  "type": "record",
  "recordFields": [
    {
      "index": 1,
      "name": "has_sensitive_data",
      "type": "bool",
      "constraints": {
        "required": true
      },
      "annotations": {
        "displayName": "Has Sensitive Data",
        "displayOrder": 1
      }
    },
    {
      "index": 2,
      "name": "sensitive_data_type",
      "type": "enum",
      "enumValues": [
        {
          "index": 1,
          "name": "Location Info"
        },
        {
          "index": 2,
          "name": "Contact Info"
        },
        {
          "index": 3,
          "name": "None"
        }
      ],
      "constraints": {
        "required": true
      },
      "annotations": {
        "displayName": "Sensitive Data Type",
        "displayOrder": 2
      }
    }
  ]
}
JSON

info "Creating Sensitive Data Aspect..."
if gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" \
  --project="$PROJECT_ID" \
  --location="$DATAPLEX_LOCATION" >/dev/null 2>&1; then
  success "Sensitive Data Aspect already exists."
else
  gcloud dataplex aspect-types create "$ASPECT_TYPE_ID" \
    --project="$PROJECT_ID" \
    --location="$DATAPLEX_LOCATION" \
    --display-name="Sensitive Data Aspect" \
    --metadata-template-file-name="$ASPECT_TEMPLATE" \
    --quiet
  success "Sensitive Data Aspect created."
fi

cat > "$ASPECT_VALUES" <<YAML
"${PROJECT_ID}.${DATAPLEX_LOCATION}.${ASPECT_TYPE_ID}":
  data:
    has_sensitive_data: true
    sensitive_data_type: "Location Info"
YAML

ENTRY_ID="bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${DATASET_ID}/tables/${TABLE_ID}"

info "Applying the aspect to ${TABLE_ID}..."
ASPECT_APPLIED=false
for attempt in {1..12}; do
  if gcloud dataplex entries modify "$ENTRY_ID" \
    --project="$PROJECT_ID" \
    --location="$DATAPLEX_LOCATION" \
    --entry-group="@bigquery" \
    --update-aspects="$ASPECT_VALUES" \
    --quiet; then
    ASPECT_APPLIED=true
    break
  fi

  warning "Knowledge Catalog is still synchronizing. Retrying (${attempt}/12)..."
  sleep 5
done

[[ "$ASPECT_APPLIED" == true ]] || fail "Could not apply the aspect after multiple attempts."
success "Aspect applied: Has Sensitive Data = TRUE, Sensitive Data Type = Location Info."

printf "\n${GREEN}"
printf '╔══════════════════════════════════════════════════════╗\n'
printf '║                 ALL TASKS COMPLETED                  ║\n'
printf '╚══════════════════════════════════════════════════════╝\n'
printf "${NC}"
printf '\nClick Check my progress for Tasks 1, 2, and 3.\n'