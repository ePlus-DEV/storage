#!/bin/bash

set -uo pipefail

# ============================================================
#  Create and Add Aspects to Knowledge Catalog Assets - GSP1145
#  Copyright © ePlus.DEV
# ============================================================

# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'

BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear

echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}       ePlus.DEV - INITIATING EXECUTION...            ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo

echo_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warn() {
  echo -e "${YELLOW}[WAITING]${NC} $1"
}

echo_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

die() {
  echo_error "$1"
  exit 1
}

# ============================================================
# Check tools
# ============================================================

command -v gcloud >/dev/null 2>&1 ||
  die "gcloud command was not found."

command -v bq >/dev/null 2>&1 ||
  die "bq command was not found."

command -v jq >/dev/null 2>&1 ||
  die "jq command was not found."

# ============================================================
# Project and account
# ============================================================

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  die "Unable to retrieve the GCP project ID."
fi

gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1 ||
  die "Unable to configure project ${PROJECT_ID}."

ACTIVE_ACCOUNT="$(
  gcloud auth list \
    --filter=status:ACTIVE \
    --format='value(account)' 2>/dev/null |
  head -n1
)"

if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  die "No active Google Cloud account was found."
fi

PROJECT_NUMBER="$(
  gcloud projects describe "${PROJECT_ID}" \
    --format='value(projectNumber)' 2>/dev/null
)"

if [[ -z "${PROJECT_NUMBER}" ]]; then
  die "Unable to retrieve the project number."
fi

# ============================================================
# Variables
# ============================================================

DATASET_ID="customers"
TABLE_ID="customer_details"

LAKE_NAME="orders-lake"
LAKE_DISPLAY_NAME="Orders Lake"

ZONE_NAME="customer-curated-zone"
ZONE_DISPLAY_NAME="Customer Curated Zone"

ASSET_NAME="customer-details-dataset"
ASSET_DISPLAY_NAME="Customer Details Dataset"

ASPECT_TYPE_ID="protected-data-aspect"
ASPECT_TYPE_DISPLAY_NAME="Protected Data Aspect"
ASPECT_FIELD_ID="protected_data_flag"

ASPECT_JSON_FILE="aspect_type.json"
ASPECT_VALUES_FILE="aspect_values.json"
SEARCH_RESULT_FILE="catalog_search.json"
ENTRY_RESULT_FILE="catalog_entry.json"

# ============================================================
# Check BigQuery dataset and table
# ============================================================

echo_info "Checking the pre-created BigQuery dataset..."

if ! bq show \
  --format=prettyjson \
  "${PROJECT_ID}:${DATASET_ID}" \
  > dataset.json 2>/dev/null; then

  die "Dataset ${PROJECT_ID}:${DATASET_ID} was not found. Reopen Cloud Console from the active lab."
fi

if ! bq show \
  --format=prettyjson \
  "${PROJECT_ID}:${DATASET_ID}.${TABLE_ID}" \
  > table.json 2>/dev/null; then

  die "Table ${PROJECT_ID}:${DATASET_ID}.${TABLE_ID} was not found."
fi

DATASET_LOCATION="$(jq -r '.location // empty' dataset.json)"

# ============================================================
# Detect region
# Priority:
# 1. Existing REGION variable
# 2. Lab default region
# 3. Configured compute region
# 4. Default zone converted to region
# 5. Dataset region
# 6. Lab instruction fallback: us-east4
# ============================================================

REGION="${REGION:-}"

if [[ -z "${REGION}" ]]; then
  REGION="$(
    gcloud compute project-info describe \
      --project="${PROJECT_ID}" \
      --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
      2>/dev/null || true
  )"
fi

if [[ -z "${REGION}" || "${REGION}" == "(unset)" ]]; then
  REGION="$(
    gcloud config get-value compute/region 2>/dev/null || true
  )"
fi

if [[ -z "${REGION}" || "${REGION}" == "(unset)" ]]; then
  DEFAULT_ZONE="$(
    gcloud compute project-info describe \
      --project="${PROJECT_ID}" \
      --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
      2>/dev/null || true
  )"

  if [[ -n "${DEFAULT_ZONE}" ]]; then
    REGION="${DEFAULT_ZONE%-*}"
  fi
fi

if [[ -z "${REGION}" || "${REGION}" == "(unset)" ]]; then
  case "${DATASET_LOCATION}" in
    US|EU|"")
      REGION="us-east4"
      ;;
    *)
      REGION="${DATASET_LOCATION}"
      ;;
  esac
fi

echo_success "Lab environment detected"
echo_info "Account: ${ACTIVE_ACCOUNT}"
echo_info "Project ID: ${PROJECT_ID}"
echo_info "Project Number: ${PROJECT_NUMBER}"
echo_info "Region: ${REGION}"
echo_info "Dataset Location: ${DATASET_LOCATION}"
echo

# ============================================================
# Enable APIs
# ============================================================

echo_info "Enabling required Google Cloud APIs..."

if ! gcloud services enable \
  dataplex.googleapis.com \
  bigquery.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet; then

  die "Unable to enable the required APIs."
fi

echo_success "Required APIs are enabled."

echo_warn "Waiting for API propagation..."
sleep 15

# ============================================================
# Helper: wait for resource state
# ============================================================

wait_for_resource() {
  local resource_type="$1"
  local attempt=0
  local state=""

  while [[ "${attempt}" -lt 30 ]]; do
    case "${resource_type}" in
      lake)
        state="$(
          gcloud dataplex lakes describe "${LAKE_NAME}" \
            --project="${PROJECT_ID}" \
            --location="${REGION}" \
            --format='value(state)' 2>/dev/null || true
        )"
        ;;

      zone)
        state="$(
          gcloud dataplex zones describe "${ZONE_NAME}" \
            --project="${PROJECT_ID}" \
            --location="${REGION}" \
            --lake="${LAKE_NAME}" \
            --format='value(state)' 2>/dev/null || true
        )"
        ;;

      asset)
        state="$(
          gcloud dataplex assets describe "${ASSET_NAME}" \
            --project="${PROJECT_ID}" \
            --location="${REGION}" \
            --lake="${LAKE_NAME}" \
            --zone="${ZONE_NAME}" \
            --format='value(state)' 2>/dev/null || true
        )"
        ;;
    esac

    if [[ "${state}" == "ACTIVE" ]]; then
      echo_success "${resource_type^} is ACTIVE."
      return 0
    fi

    if [[ "${state}" == "FAILED" ]]; then
      echo_error "${resource_type^} entered FAILED state."
      return 1
    fi

    attempt=$((attempt + 1))

    echo_warn "${resource_type^} state: ${state:-PENDING}. Attempt ${attempt}/30..."
    sleep 10
  done

  echo_error "${resource_type^} did not become ACTIVE in time."
  return 1
}

# ============================================================
# Task 1.1: Create lake
# ============================================================

echo_info "Creating Dataplex lake..."

if gcloud dataplex lakes describe "${LAKE_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  >/dev/null 2>&1; then

  echo_warn "Lake already exists: ${LAKE_NAME}"

else
  LAKE_OUTPUT="$(
    gcloud dataplex lakes create "${LAKE_NAME}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --display-name="${LAKE_DISPLAY_NAME}" \
      --quiet 2>&1
  )"

  LAKE_STATUS=$?

  echo "${LAKE_OUTPUT}"

  if [[ "${LAKE_STATUS}" -ne 0 ]]; then
    if echo "${LAKE_OUTPUT}" |
      grep -q "constraints/gcp.resourceLocations"; then

      echo_error "Region ${REGION} is blocked by the current project policy."
      echo_error "This Cloud Shell may belong to an expired or different lab."
    fi

    exit 1
  fi
fi

wait_for_resource lake ||
  die "Lake creation failed."

# ============================================================
# Task 1.2: Create curated zone
# ============================================================

echo_info "Creating curated zone..."

if gcloud dataplex zones describe "${ZONE_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --lake="${LAKE_NAME}" \
  >/dev/null 2>&1; then

  echo_warn "Zone already exists: ${ZONE_NAME}"

else
  if ! gcloud dataplex zones create "${ZONE_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --lake="${LAKE_NAME}" \
    --display-name="${ZONE_DISPLAY_NAME}" \
    --type="CURATED" \
    --resource-location-type="SINGLE_REGION" \
    --quiet; then

    die "Unable to create the curated zone."
  fi
fi

wait_for_resource zone ||
  die "Zone creation failed."

# ============================================================
# Task 1.3: Attach BigQuery dataset
# ============================================================

echo_info "Attaching the BigQuery dataset..."

if gcloud dataplex assets describe "${ASSET_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --lake="${LAKE_NAME}" \
  --zone="${ZONE_NAME}" \
  >/dev/null 2>&1; then

  echo_warn "Asset already exists: ${ASSET_NAME}"

else
  if ! gcloud dataplex assets create "${ASSET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --lake="${LAKE_NAME}" \
    --zone="${ZONE_NAME}" \
    --display-name="${ASSET_DISPLAY_NAME}" \
    --resource-type="BIGQUERY_DATASET" \
    --resource-name="projects/${PROJECT_NUMBER}/datasets/${DATASET_ID}" \
    --resource-read-access-mode="DIRECT" \
    --quiet; then

    die "Unable to attach the BigQuery dataset."
  fi
fi

wait_for_resource asset ||
  die "Asset creation failed."

# ============================================================
# Task 2: Create aspect type JSON
# ============================================================

echo_info "Generating aspect type JSON..."

cat > "${ASPECT_JSON_FILE}" <<JSON
{
  "name": "protected_data",
  "type": "record",
  "recordFields": [
    {
      "index": 1,
      "name": "${ASPECT_FIELD_ID}",
      "type": "enum",
      "constraints": {
        "required": true
      },
      "annotations": {
        "displayName": "Protected Data Flag"
      },
      "enumValues": [
        {
          "index": 1,
          "name": "Yes"
        },
        {
          "index": 2,
          "name": "No"
        }
      ]
    }
  ]
}
JSON

echo_success "Aspect type JSON generated."

# ============================================================
# Task 2: Create aspect type
# ============================================================

echo_info "Creating aspect type..."

if gcloud dataplex aspect-types describe "${ASPECT_TYPE_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  >/dev/null 2>&1; then

  echo_warn "Aspect type already exists: ${ASPECT_TYPE_ID}"

else
  if ! gcloud dataplex aspect-types create "${ASPECT_TYPE_ID}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --display-name="${ASPECT_TYPE_DISPLAY_NAME}" \
    --metadata-template-file-name="${ASPECT_JSON_FILE}" \
    --quiet; then

    die "Unable to create the aspect type."
  fi
fi

echo_success "Aspect type is ready."

# ============================================================
# Task 3: Find customer_details entry
# ============================================================

TABLE_FQN="bigquery:${PROJECT_ID}.${DATASET_ID}.${TABLE_ID}"
ENTRY_NAME=""

echo_info "Searching Knowledge Catalog for ${TABLE_ID}..."

for ATTEMPT in $(seq 1 30); do
  if gcloud dataplex entries search \
    "fully_qualified_name=${TABLE_FQN}" \
    --project="${PROJECT_ID}" \
    --scope="projects/${PROJECT_ID}" \
    --limit=20 \
    --format=json \
    > "${SEARCH_RESULT_FILE}" 2>/dev/null; then

    ENTRY_NAME="$(
      jq -r --arg fqn "${TABLE_FQN}" '
        def results:
          if type == "array" then
            .[]
          elif type == "object" and (.results? | type == "array") then
            .results[]
          else
            empty
          end;

        [
          results
          | (.dataplexEntry // .entry // .)
          | select(.fullyQualifiedName == $fqn)
          | .name
        ][0] // empty
      ' "${SEARCH_RESULT_FILE}"
    )"
  fi

  if [[ -n "${ENTRY_NAME}" ]]; then
    break
  fi

  echo_warn "Catalog entry not available yet. Attempt ${ATTEMPT}/30..."
  sleep 10
done

if [[ -z "${ENTRY_NAME}" ]]; then
  die "Unable to find ${TABLE_FQN} in Knowledge Catalog."
fi

echo_success "Catalog entry found:"
echo "  ${ENTRY_NAME}"

# ============================================================
# Task 3: Build aspect values JSON
# ============================================================

ASPECT_REFERENCE="${PROJECT_ID}.${REGION}.${ASPECT_TYPE_ID}"

echo_info "Generating aspect values for table and columns..."

jq -n \
  --arg aspect "${ASPECT_REFERENCE}" \
  --arg field "${ASPECT_FIELD_ID}" '
    def protected_value:
      {
        "data": {
          ($field): "Yes"
        }
      };

    reduce [
      "zip",
      "state",
      "last_name",
      "country",
      "email",
      "latitude",
      "first_name",
      "city",
      "longitude"
    ][] as $column (
      {
        ($aspect): protected_value
      };

      . + {
        ($aspect + "@Schema." + $column): protected_value
      }
    )
  ' > "${ASPECT_VALUES_FILE}"

echo_success "Aspect values JSON generated."

# ============================================================
# Task 3: Attach aspects
# ============================================================

echo_info "Adding Protected Data Aspect to the table..."

if ! gcloud dataplex entries update-aspects "${ENTRY_NAME}" \
  --aspects="${ASPECT_VALUES_FILE}" \
  --quiet; then

  die "Unable to attach aspects to the Knowledge Catalog entry."
fi

echo_success "Protected Data Aspect attached to:"
echo "  - customer_details table"
echo "  - zip"
echo "  - state"
echo "  - last_name"
echo "  - country"
echo "  - email"
echo "  - latitude"
echo "  - first_name"
echo "  - city"
echo "  - longitude"

# ============================================================
# Verify aspects
# ============================================================

echo_info "Verifying the attached aspects..."

sleep 5

if ! gcloud dataplex entries lookup "${ENTRY_NAME}" \
  --view="all" \
  --format=json \
  > "${ENTRY_RESULT_FILE}"; then

  die "Unable to verify the entry aspects."
fi

ASPECT_COUNT="$(
  jq --arg aspect "${ASPECT_REFERENCE}" '
    [
      (.aspects // {})
      | to_entries[]
      | select(
          .key == $aspect or
          (.key | startswith($aspect + "@Schema."))
        )
    ]
    | length
  ' "${ENTRY_RESULT_FILE}"
)"

echo
echo_info "Protected Data Aspects found: ${ASPECT_COUNT}/10"

jq -r --arg aspect "${ASPECT_REFERENCE}" '
  (.aspects // {})
  | to_entries[]
  | select(
      .key == $aspect or
      (.key | startswith($aspect + "@Schema."))
    )
  | "  ✓ " + .key + " = " +
    (.value.data.protected_data_flag // "")
' "${ENTRY_RESULT_FILE}" |
sort

if [[ "${ASPECT_COUNT}" -ge 10 ]]; then
  echo_success "All required aspects were verified."
else
  echo_warn "Aspect propagation is still in progress."
  echo_warn "Wait approximately one minute before checking progress."
fi

# ============================================================
# Task 4: Search using the aspect
# ============================================================

echo_info "Searching assets using Protected Data Aspect..."

gcloud dataplex entries search \
  "aspect=${ASPECT_REFERENCE}" \
  --project="${PROJECT_ID}" \
  --scope="projects/${PROJECT_ID}" \
  --limit=20 \
  --format="table(
    dataplexEntry.entrySource.displayName,
    dataplexEntry.fullyQualifiedName
  )" 2>/dev/null || true

# ============================================================
# Cleanup temporary local files
# ============================================================

rm -f \
  dataset.json \
  table.json \
  "${SEARCH_RESULT_FILE}" \
  "${ENTRY_RESULT_FILE}"

# ============================================================
# Final message
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}              LAB COMPLETED SUCCESSFULLY!              ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo

echo_success "Lake: ${LAKE_DISPLAY_NAME}"
echo_success "Zone: ${ZONE_DISPLAY_NAME}"
echo_success "Asset: ${ASSET_DISPLAY_NAME}"
echo_success "Aspect Type: ${ASPECT_TYPE_DISPLAY_NAME}"
echo_success "Attached Aspects: ${ASPECT_COUNT}/10"

echo
echo_info "On the lab page, click Check my progress for every task."
echo_info "For Task 4, open Knowledge Catalog > Search > Aspect Types."
echo_info "Select Protected Data Aspect and open customer_details."
echo

echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"