#!/bin/bash

set -Eeuo pipefail

# ============================================================
# Color variables
# ============================================================
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

# ============================================================
# Output helpers
# ============================================================
info() {
  echo "${BLUE}${BOLD}ℹ${RESET} $1"
}

success() {
  echo "${GREEN}${BOLD}✔${RESET} $1"
}

warning() {
  echo "${YELLOW}${BOLD}⚠${RESET} $1"
}

error() {
  echo "${RED}${BOLD}✘${RESET} $1"
}

section() {
  echo
  echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo "${WHITE}${BOLD}$1${RESET}"
  echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

on_error() {
  local exit_code=$?
  local line_number=$1

  echo
  error "Script failed at line ${line_number} with exit code ${exit_code}."
  echo "${CYAN}${BOLD}© ePlus.DEV${RESET}"

  exit "${exit_code}"
}

trap 'on_error $LINENO' ERR

trim_value() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"

  printf '%s' "${value}"
}

# ============================================================
# Start
# ============================================================
clear

echo "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        KNOWLEDGE CATALOG CHALLENGE LAB                    ║"
echo "║                                                            ║"
echo "║      Lake • Zone • Storage Asset • Custom Aspect          ║"
echo "║                                                            ║"
echo "║                     © ePlus.DEV                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "${RESET}"

echo "${YELLOW}${BOLD}Starting${RESET} ${GREEN}${BOLD}Execution - ePlus.DEV${RESET}"

# ============================================================
# Detect project
# ============================================================
section "Detecting project and region"

ID="${DEVSHELL_PROJECT_ID:-}"

if [[ -z "${ID}" ]]; then
  ID=$(gcloud config get-value project 2>/dev/null || true)
fi

if [[ -z "${ID}" || "${ID}" == "(unset)" ]]; then
  ID=$(gcloud projects list \
    --format="value(projectId)" \
    --limit=1)
fi

ID=$(trim_value "${ID}")

if [[ -z "${ID}" ]]; then
  error "Unable to detect the Project ID."
  exit 1
fi

export ID

gcloud config set project "${ID}" >/dev/null

PROJECT_NUMBER=$(gcloud projects describe "${ID}" \
  --format="value(projectNumber)")

# ============================================================
# Detect region from project metadata
# ============================================================
LOCATION=$(gcloud compute project-info describe \
  --project="${ID}" \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
  2>/dev/null || true)

LOCATION=$(trim_value "${LOCATION}")

# Fallback: active gcloud configuration.
if [[ -z "${LOCATION}" || "${LOCATION}" == "(unset)" ]]; then
  LOCATION=$(gcloud config get-value compute/region 2>/dev/null || true)
  LOCATION=$(trim_value "${LOCATION}")

  if [[ "${LOCATION}" == "(unset)" ]]; then
    LOCATION=""
  fi
fi

# Fallback: derive region from default zone.
if [[ -z "${LOCATION}" ]]; then
  DEFAULT_ZONE=$(gcloud compute project-info describe \
    --project="${ID}" \
    --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
    2>/dev/null || true)

  DEFAULT_ZONE=$(trim_value "${DEFAULT_ZONE}")

  if [[ -z "${DEFAULT_ZONE}" || "${DEFAULT_ZONE}" == "(unset)" ]]; then
    DEFAULT_ZONE=$(gcloud config get-value compute/zone 2>/dev/null || true)
    DEFAULT_ZONE=$(trim_value "${DEFAULT_ZONE}")
  fi

  if [[ -n "${DEFAULT_ZONE}" && "${DEFAULT_ZONE}" != "(unset)" ]]; then
    LOCATION="${DEFAULT_ZONE%-*}"
  fi
fi

# Manual input only when automatic detection fails.
while [[ -z "${LOCATION}" ]]; do
  echo
  read -r -p "Enter the lab region: " LOCATION
  LOCATION=$(trim_value "${LOCATION}")

  if [[ -z "${LOCATION}" ]]; then
    error "Region cannot be empty."
  fi
done

export LOCATION

gcloud config set compute/region "${LOCATION}" >/dev/null
gcloud config set dataplex/location "${LOCATION}" >/dev/null 2>&1 || true

echo "${CYAN}${BOLD}Project ID:${RESET}     ${ID}"
echo "${CYAN}${BOLD}Project number:${RESET} ${PROJECT_NUMBER}"
echo "${CYAN}${BOLD}Region:${RESET}         ${LOCATION}"
echo "${CYAN}${BOLD}Bucket:${RESET}         ${ID}"

# ============================================================
# Resource names
# ============================================================
LAKE_ID="customer-engagements"
ZONE_ID="raw-event-data"
ASSET_ID="raw-event-files"

ASPECT_TYPE_ID="protected-raw-data-aspect"
ASPECT_DISPLAY_NAME="Protected Raw Data Aspect"
ASPECT_FIELD_ID="protected_raw_data_flag"
ASPECT_FIELD_DISPLAY_NAME="Protected Raw Data Flag"

WORK_DIR="${HOME}/knowledge-catalog-lab"
ASPECT_TEMPLATE_FILE="${WORK_DIR}/aspect-template.json"
ASPECT_DATA_FILE="${WORK_DIR}/aspect-data.json"
ENTRY_FILE="${WORK_DIR}/bucket-entry.json"
VERIFY_FILE="${WORK_DIR}/verify-entry.json"

mkdir -p "${WORK_DIR}"

# ============================================================
# Enable APIs
# ============================================================
section "Enabling required APIs"

# Data Catalog API is deprecated and is not required.
gcloud services enable \
  dataplex.googleapis.com \
  storage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  --project="${ID}" \
  --quiet

success "Required APIs are enabled."

# ============================================================
# Task 1: Create lake
# ============================================================
section "Task 1: Create lake and raw zone"

if gcloud dataplex lakes describe "${LAKE_ID}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  >/dev/null 2>&1; then

  success "Lake ${LAKE_ID} already exists."
else
  info "Creating Customer Engagements lake..."

  gcloud dataplex lakes create "${LAKE_ID}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --display-name="Customer Engagements" \
    --quiet

  success "Lake created."
fi

# Wait for lake activation.
for attempt in {1..30}; do
  LAKE_STATE=$(gcloud dataplex lakes describe "${LAKE_ID}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --format="value(state)" \
    2>/dev/null || true)

  if [[ "${LAKE_STATE}" == "ACTIVE" ]]; then
    success "Lake state: ACTIVE"
    break
  fi

  warning "Lake state: ${LAKE_STATE:-UNKNOWN} (${attempt}/30)"
  sleep 5
done

# ============================================================
# Task 1: Create raw zone
# ============================================================
if gcloud dataplex zones describe "${ZONE_ID}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  --lake="${LAKE_ID}" \
  >/dev/null 2>&1; then

  success "Zone ${ZONE_ID} already exists."
else
  info "Creating Raw Event Data zone..."

  gcloud dataplex zones create "${ZONE_ID}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --lake="${LAKE_ID}" \
    --display-name="Raw Event Data" \
    --type="RAW" \
    --resource-location-type="SINGLE_REGION" \
    --discovery-enabled \
    --quiet

  success "Raw zone created."
fi

# Wait for zone activation.
for attempt in {1..30}; do
  ZONE_STATE=$(gcloud dataplex zones describe "${ZONE_ID}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --lake="${LAKE_ID}" \
    --format="value(state)" \
    2>/dev/null || true)

  if [[ "${ZONE_STATE}" == "ACTIVE" ]]; then
    success "Zone state: ACTIVE"
    break
  fi

  warning "Zone state: ${ZONE_STATE:-UNKNOWN} (${attempt}/30)"
  sleep 5
done

success "Task 1 completed."

# ============================================================
# Task 2: Create Cloud Storage bucket
# ============================================================
section "Task 2: Create and attach Cloud Storage bucket"

if gcloud storage buckets describe "gs://${ID}" \
  --project="${ID}" \
  >/dev/null 2>&1; then

  success "Bucket gs://${ID} already exists."
else
  info "Creating bucket gs://${ID}..."

  gcloud storage buckets create "gs://${ID}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --default-storage-class="STANDARD" \
    --uniform-bucket-level-access \
    --quiet

  success "Cloud Storage bucket created."
fi

# Authorize the Dataplex service agent.
info "Authorizing Dataplex to access the bucket..."

if gcloud dataplex lakes authorize \
  --project="${ID}" \
  --storage-bucket-resource="${ID}" \
  --quiet; then

  success "Dataplex bucket access authorized."
else
  warning "Bucket authorization may already be configured."
fi

# ============================================================
# Task 2: Attach bucket as asset
# ============================================================
if gcloud dataplex assets describe "${ASSET_ID}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  --lake="${LAKE_ID}" \
  --zone="${ZONE_ID}" \
  >/dev/null 2>&1; then

  success "Asset ${ASSET_ID} already exists."
else
  info "Creating Raw Event Files asset..."

  gcloud dataplex assets create "${ASSET_ID}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --lake="${LAKE_ID}" \
    --zone="${ZONE_ID}" \
    --display-name="Raw Event Files" \
    --resource-type="STORAGE_BUCKET" \
    --resource-name="projects/${ID}/buckets/${ID}" \
    --resource-read-access-mode="DIRECT" \
    --discovery-enabled \
    --quiet

  success "Raw Event Files asset created."
fi

# Wait for asset activation.
for attempt in {1..40}; do
  ASSET_STATE=$(gcloud dataplex assets describe "${ASSET_ID}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --lake="${LAKE_ID}" \
    --zone="${ZONE_ID}" \
    --format="value(state)" \
    2>/dev/null || true)

  if [[ "${ASSET_STATE}" == "ACTIVE" ]]; then
    success "Asset state: ACTIVE"
    break
  fi

  warning "Asset state: ${ASSET_STATE:-UNKNOWN} (${attempt}/40)"
  sleep 5
done

success "Task 2 completed."

# ============================================================
# Task 3: Create aspect type
# ============================================================
section "Task 3: Create Protected Raw Data Aspect"

cat > "${ASPECT_TEMPLATE_FILE}" <<JSON
{
  "name": "protected_raw_data_aspect",
  "type": "record",
  "recordFields": [
    {
      "index": 1,
      "name": "${ASPECT_FIELD_ID}",
      "type": "enum",
      "enumValues": [
        {
          "index": 1,
          "name": "Y"
        },
        {
          "index": 2,
          "name": "N"
        }
      ],
      "annotations": {
        "displayName": "${ASPECT_FIELD_DISPLAY_NAME}",
        "description": "Indicates whether the raw data is protected",
        "displayOrder": 1
      }
    }
  ]
}
JSON

echo
echo "${CYAN}${BOLD}Aspect template:${RESET}"
jq . "${ASPECT_TEMPLATE_FILE}"

if gcloud dataplex aspect-types describe "${ASPECT_TYPE_ID}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  >/dev/null 2>&1; then

  success "Aspect type ${ASPECT_TYPE_ID} already exists."
else
  info "Creating ${ASPECT_DISPLAY_NAME}..."

  gcloud dataplex aspect-types create "${ASPECT_TYPE_ID}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --display-name="${ASPECT_DISPLAY_NAME}" \
    --description="Marks whether raw data is protected" \
    --metadata-template-file-name="${ASPECT_TEMPLATE_FILE}" \
    --quiet

  success "Aspect type created."
fi

# ============================================================
# Task 3: Create aspect data
# ============================================================
ASPECT_KEY="${ID}.${LOCATION}.${ASPECT_TYPE_ID}"
BUCKET_FQN="gcs:${ID}"

cat > "${ASPECT_DATA_FILE}" <<JSON
{
  "${ASPECT_KEY}": {
    "data": {
      "${ASPECT_FIELD_ID}": "Y"
    }
  }
}
JSON

echo
echo "${CYAN}${BOLD}Aspect data:${RESET}"
jq . "${ASPECT_DATA_FILE}"

# ============================================================
# Task 3: Lookup exact Cloud Storage bucket entry
# ============================================================
section "Locating Raw Event Files entry"

info "Looking up exact Cloud Storage FQN: ${BUCKET_FQN}"

ENTRY_NAME=""

for attempt in {1..36}; do
  if gcloud dataplex entries lookup "${BUCKET_FQN}" \
    --project="${ID}" \
    --location="${LOCATION}" \
    --view="all" \
    --format=json \
    > "${ENTRY_FILE}" 2>/dev/null; then

    FOUND_FQN=$(jq -r '.fullyQualifiedName // empty' "${ENTRY_FILE}")
    FOUND_ENTRY_NAME=$(jq -r '.name // empty' "${ENTRY_FILE}")

    if [[ "${FOUND_FQN}" == "${BUCKET_FQN}" && -n "${FOUND_ENTRY_NAME}" ]]; then
      ENTRY_NAME="${FOUND_ENTRY_NAME}"
      success "Exact Cloud Storage entry found."
      break
    fi
  fi

  warning "Cloud Storage entry is not available yet (${attempt}/36)."
  sleep 5
done

if [[ -z "${ENTRY_NAME}" ]]; then
  error "Unable to locate the entry with FQN ${BUCKET_FQN}."
  echo
  info "Knowledge Catalog search results for the bucket:"

  gcloud dataplex entries search "${ID}" \
    --project="${ID}" \
    --scope="projects/${ID}" \
    --limit=50 \
    --format="table(
      dataplexEntry.entrySource.system:label=SYSTEM,
      dataplexEntry.displayName:label=DISPLAY_NAME,
      dataplexEntry.fullyQualifiedName:label=FQN,
      dataplexEntry.name:label=ENTRY
    )" || true

  exit 1
fi

ENTRY_SYSTEM=$(jq -r '.entrySource.system // "UNKNOWN"' "${ENTRY_FILE}")
ENTRY_RESOURCE=$(jq -r '.entrySource.resource // "UNKNOWN"' "${ENTRY_FILE}")

echo "${CYAN}${BOLD}Entry name:${RESET}     ${ENTRY_NAME}"
echo "${CYAN}${BOLD}Entry FQN:${RESET}      ${BUCKET_FQN}"
echo "${CYAN}${BOLD}Entry system:${RESET}   ${ENTRY_SYSTEM}"
echo "${CYAN}${BOLD}Entry resource:${RESET} ${ENTRY_RESOURCE}"

if [[ "${ENTRY_SYSTEM}" == "BIGQUERY" ]]; then
  error "The selected entry is a BigQuery entry, not Raw Event Files."
  exit 1
fi

# ============================================================
# Task 3: Attach aspect to asset entry
# ============================================================
section "Attaching aspect to Raw Event Files"

gcloud dataplex entries update "${ENTRY_NAME}" \
  --update-aspects="${ASPECT_DATA_FILE}" \
  --quiet

success "Protected Raw Data Aspect attached to Raw Event Files."

# ============================================================
# Task 3: Verify aspect
# ============================================================
section "Verifying attached aspect"

gcloud dataplex entries lookup "${BUCKET_FQN}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  --view="all" \
  --format=json \
  > "${VERIFY_FILE}"

ASPECT_TYPE_RESOURCE_SUFFIX="/locations/${LOCATION}/aspectTypes/${ASPECT_TYPE_ID}"

if jq -e \
  --arg expected_fqn "${BUCKET_FQN}" \
  --arg suffix "${ASPECT_TYPE_RESOURCE_SUFFIX}" \
  --arg field "${ASPECT_FIELD_ID}" '
    .fullyQualifiedName == $expected_fqn
    and any(
      (.aspects // {} | to_entries[]);
      (.value.aspectType // "" | endswith($suffix))
      and .value.data[$field] == "Y"
    )
  ' "${VERIFY_FILE}" >/dev/null; then

  success "Protected Raw Data Flag is set to Y on Raw Event Files."
else
  error "Aspect verification failed."
  jq . "${VERIFY_FILE}"
  exit 1
fi

echo
echo "${CYAN}${BOLD}Verified aspect:${RESET}"

jq \
  --arg suffix "${ASPECT_TYPE_RESOURCE_SUFFIX}" '
    .aspects
    | to_entries[]
    | select(.value.aspectType | endswith($suffix))
  ' "${VERIFY_FILE}"

# ============================================================
# Final verification
# ============================================================
section "Final resource verification"

echo "${CYAN}${BOLD}Lake${RESET}"

gcloud dataplex lakes describe "${LAKE_ID}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    name.basename():label=ID,
    state:label=STATE
  )"

echo
echo "${CYAN}${BOLD}Raw zone${RESET}"

gcloud dataplex zones describe "${ZONE_ID}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  --lake="${LAKE_ID}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    name.basename():label=ID,
    type:label=TYPE,
    resourceSpec.locationType:label=LOCATION_TYPE,
    state:label=STATE
  )"

echo
echo "${CYAN}${BOLD}Raw Event Files asset${RESET}"

gcloud dataplex assets describe "${ASSET_ID}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  --lake="${LAKE_ID}" \
  --zone="${ZONE_ID}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    name.basename():label=ID,
    resourceSpec.name:label=RESOURCE,
    state:label=STATE
  )"

echo
echo "${CYAN}${BOLD}Protected Raw Data Aspect${RESET}"

gcloud dataplex aspect-types describe "${ASPECT_TYPE_ID}" \
  --project="${ID}" \
  --location="${LOCATION}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    name.basename():label=ID,
    uid:label=UID
  )"

# ============================================================
# Complete
# ============================================================
echo
echo "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  ALL TASKS COMPLETED                      ║"
echo "╠════════════════════════════════════════════════════════════╣"
printf "║ %-58s ║\n" "Project: ${ID}"
printf "║ %-58s ║\n" "Region: ${LOCATION}"
printf "║ %-58s ║\n" "Lake: Customer Engagements"
printf "║ %-58s ║\n" "Zone: Raw Event Data"
printf "║ %-58s ║\n" "Asset: Raw Event Files"
printf "║ %-58s ║\n" "Aspect: Protected Raw Data Aspect"
printf "║ %-58s ║\n" "Protected Raw Data Flag: Y"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║                     © ePlus.DEV                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "${RESET}"

echo "${RED}${BOLD}Congratulations${RESET} ${WHITE}${BOLD}for${RESET} ${GREEN}${BOLD}Completing the Lab !!! - ePlus.DEV${RESET}"