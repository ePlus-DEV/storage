cat > lab.sh <<'EOF'
#!/usr/bin/env bash

# ============================================================
# Organize and Govern Data with Knowledge Catalog
# Challenge Lab
#
# Lake + Raw Zone + Storage Asset + Aspect
#
# © ePlus.DEV
# ============================================================

set -Eeuo pipefail

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# ------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------
banner() {
  clear || true

  echo -e "${CYAN}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║        KNOWLEDGE CATALOG CHALLENGE LAB                    ║"
  echo "║                                                          ║"
  echo "║     Lake • Raw Zone • Storage Asset • Aspect             ║"
  echo "║                                                          ║"
  echo "║                     © ePlus.DEV                           ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

section() {
  echo
  echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHITE}$1${NC}"
  echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

success() {
  echo -e "${GREEN}✔${NC} $1"
}

warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

error() {
  echo -e "${RED}✘${NC} $1"
}

on_error() {
  local exit_code=$?
  local line_number="$1"

  echo
  error "Script failed at line ${line_number}."
  error "Exit code: ${exit_code}"
  echo -e "${GRAY}© ePlus.DEV${NC}"

  exit "${exit_code}"
}

trap 'on_error $LINENO' ERR

# ------------------------------------------------------------
# Retry helper
# ------------------------------------------------------------
retry() {
  local max_attempts="$1"
  local delay_seconds="$2"

  shift 2

  local attempt=1

  while true; do
    if "$@"; then
      return 0
    fi

    if (( attempt >= max_attempts )); then
      error "Command failed after ${max_attempts} attempts."
      return 1
    fi

    warning "Attempt ${attempt}/${max_attempts} failed."
    warning "Retrying in ${delay_seconds} seconds..."

    sleep "${delay_seconds}"
    ((attempt++))
  done
}

# ------------------------------------------------------------
# Verify required commands
# ------------------------------------------------------------
require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    error "Required command not found: ${command_name}"
    exit 1
  fi
}

# ------------------------------------------------------------
# Extract exact Dataplex entry from search JSON
# ------------------------------------------------------------
extract_entry_name() {
  local json_data="$1"

  printf '%s' "${json_data}" |
    jq -r --arg fqn "${ZONE_FQN}" '
      if type == "array" then
        .[]
      elif type == "object" and (.results? != null) then
        .results[]
      else
        empty
      end
      | (.dataplexEntry // .)
      | select(.fullyQualifiedName? == $fqn)
      | .name
    ' 2>/dev/null |
    head -n 1
}

# ------------------------------------------------------------
# Search using gcloud CLI
# ------------------------------------------------------------
search_entry_with_gcloud() {
  local query=""
  local search_json=""
  local found_entry=""

  local queries=(
    "fully_qualified_name=${ZONE_FQN}"
    "fully_qualified_name=\"${ZONE_FQN}\""
    "displayname:\"${ZONE_DISPLAY_NAME}\" projectid:${PROJECT_ID} location=${REGION}"
    "name:${ZONE_ID} projectid:${PROJECT_ID} location=${REGION}"
  )

  for query in "${queries[@]}"; do
    search_json="$(
      gcloud dataplex entries search "${query}" \
        --project="${PROJECT_ID}" \
        --scope="projects/${PROJECT_ID}" \
        --limit=100 \
        --page-size=100 \
        --format=json \
        2>/dev/null || true
    )"

    if [[ -z "${search_json}" ]]; then
      continue
    fi

    found_entry="$(extract_entry_name "${search_json}")"

    if [[ -n "${found_entry}" && "${found_entry}" != "null" ]]; then
      printf '%s' "${found_entry}"
      return 0
    fi
  done

  return 1
}

# ------------------------------------------------------------
# Search using Dataplex REST API
#
# IMPORTANT:
# searchEntries requires POST, not GET.
# Request body must be empty.
# ------------------------------------------------------------
search_entry_with_rest() {
  local access_token=""
  local search_url=""
  local search_json=""
  local found_entry=""

  access_token="$(gcloud auth print-access-token)"

  search_url="$(
    python3 - "${PROJECT_ID}" "${ZONE_FQN}" <<'PY'
import sys
import urllib.parse

project_id = sys.argv[1]
zone_fqn = sys.argv[2]

endpoint = (
    f"https://dataplex.googleapis.com/v1/"
    f"projects/{project_id}/locations/global:searchEntries"
)

parameters = {
    "query": f"fully_qualified_name={zone_fqn}",
    "scope": f"projects/{project_id}",
    "pageSize": "100",
}

print(endpoint + "?" + urllib.parse.urlencode(parameters))
PY
  )"

  # Do not use curl -G here. This endpoint requires POST.
  search_json="$(
    curl -sS \
      --request POST \
      --header "Authorization: Bearer ${access_token}" \
      --header "x-goog-user-project: ${PROJECT_ID}" \
      --header "Content-Length: 0" \
      "${search_url}" \
      2>/dev/null || true
  )"

  if [[ -z "${search_json}" ]]; then
    return 1
  fi

  found_entry="$(extract_entry_name "${search_json}")"

  if [[ -n "${found_entry}" && "${found_entry}" != "null" ]]; then
    printf '%s' "${found_entry}"
    return 0
  fi

  return 1
}

# ------------------------------------------------------------
# Find the Knowledge Catalog entry for the zone
# ------------------------------------------------------------
find_zone_entry() {
  local found_entry=""

  found_entry="$(search_entry_with_gcloud || true)"

  if [[ -n "${found_entry}" ]]; then
    printf '%s' "${found_entry}"
    return 0
  fi

  found_entry="$(search_entry_with_rest || true)"

  if [[ -n "${found_entry}" ]]; then
    printf '%s' "${found_entry}"
    return 0
  fi

  return 1
}

banner

# ============================================================
# Environment validation
# ============================================================
section "Environment validation"

require_command gcloud
require_command curl
require_command jq
require_command python3

success "Required commands are available."

# ============================================================
# Detect Google Cloud configuration
# ============================================================
section "Detecting Google Cloud configuration"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  PROJECT_ID="$(
    gcloud projects list \
      --format="value(projectId)" \
      --limit=1
  )"
fi

if [[ -z "${PROJECT_ID}" ]]; then
  error "Unable to detect PROJECT_ID."
  exit 1
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

PROJECT_NUMBER="$(
  gcloud projects describe "${PROJECT_ID}" \
    --format="value(projectNumber)"
)"

CURRENT_ACCOUNT="$(
  gcloud config get-value account 2>/dev/null || true
)"

DEFAULT_REGION="$(
  gcloud compute project-info describe \
    --project="${PROJECT_ID}" \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
    2>/dev/null || true
)"

DEFAULT_ZONE="$(
  gcloud compute project-info describe \
    --project="${PROJECT_ID}" \
    --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
    2>/dev/null || true
)"

# ------------------------------------------------------------
# Exact lab requirements
# ------------------------------------------------------------
REGION="us-west1"

# In this lab, the required bucket name is the same as PROJECT_ID.
BUCKET_NAME="${PROJECT_ID}"

# Resource IDs
LAKE_ID="customer-engagements"
ZONE_ID="raw-event-data"
ASSET_ID="raw-event-files"
ASPECT_TYPE_ID="protected-raw-data-aspect"

# Display names required by the grader
LAKE_DISPLAY_NAME="Customer Engagements"
ZONE_DISPLAY_NAME="Raw Event Data"
ASSET_DISPLAY_NAME="Raw Event Files"
ASPECT_DISPLAY_NAME="Protected Raw Data Aspect"

# Aspect field
ASPECT_FIELD_ID="protected_raw_data_flag"
ASPECT_FIELD_DISPLAY_NAME="Protected Raw Data Flag"

# Fully qualified name of the zone
ZONE_FQN="dataplex:${PROJECT_ID}.${REGION}.${LAKE_ID}.${ZONE_ID}"

# Root-level aspect key
ASPECT_KEY="${PROJECT_ID}.${REGION}.${ASPECT_TYPE_ID}"

# Working files
WORK_DIR="${HOME}/knowledge-catalog-lab"
ASPECT_TEMPLATE_FILE="${WORK_DIR}/aspect-template.json"
ASPECT_DATA_FILE="${WORK_DIR}/aspect-data.json"

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo -e "${CYAN}Project ID:${NC}             ${PROJECT_ID}"
echo -e "${CYAN}Project number:${NC}         ${PROJECT_NUMBER}"
echo -e "${CYAN}Current account:${NC}        ${CURRENT_ACCOUNT}"
echo -e "${CYAN}Detected region:${NC}        ${DEFAULT_REGION:-Not configured}"
echo -e "${CYAN}Required region:${NC}        ${REGION}"
echo -e "${CYAN}Detected zone:${NC}          ${DEFAULT_ZONE:-Not configured}"
echo -e "${CYAN}Bucket name:${NC}            ${BUCKET_NAME}"
echo -e "${CYAN}Zone FQN:${NC}               ${ZONE_FQN}"

if [[ -n "${DEFAULT_REGION}" && "${DEFAULT_REGION}" != "${REGION}" ]]; then
  warning "Detected default region is ${DEFAULT_REGION}."
  warning "The script uses ${REGION} because the lab requires it."
fi

success "Cloud configuration detected."

# ============================================================
# Enable APIs
# ============================================================
section "Enabling required APIs"

gcloud services enable \
  dataplex.googleapis.com \
  datacatalog.googleapis.com \
  storage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet

success "Required APIs are enabled."

info "Waiting for API activation to propagate..."
sleep 10

# ============================================================
# Task 1: Create the lake
# ============================================================
section "Task 1: Create lake and regional raw zone"

if gcloud dataplex lakes describe "${LAKE_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  >/dev/null 2>&1; then

  success "Lake ${LAKE_ID} already exists."
else
  info "Creating lake: ${LAKE_DISPLAY_NAME}"

  retry 5 15 \
    gcloud dataplex lakes create "${LAKE_ID}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --display-name="${LAKE_DISPLAY_NAME}" \
      --description="Customer engagement data lake" \
      --quiet

  success "Lake created."
fi

LAKE_STATE="$(
  gcloud dataplex lakes describe "${LAKE_ID}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --format="value(state)"
)"

echo -e "${CYAN}Lake state:${NC} ${LAKE_STATE}"

# ============================================================
# Task 1: Create the raw zone
# ============================================================
if gcloud dataplex zones describe "${ZONE_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --lake="${LAKE_ID}" \
  >/dev/null 2>&1; then

  success "Zone ${ZONE_ID} already exists."
else
  info "Creating regional raw zone: ${ZONE_DISPLAY_NAME}"

  retry 5 15 \
    gcloud dataplex zones create "${ZONE_ID}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --lake="${LAKE_ID}" \
      --display-name="${ZONE_DISPLAY_NAME}" \
      --description="Regional raw event data zone" \
      --type="RAW" \
      --resource-location-type="SINGLE_REGION" \
      --quiet

  success "Regional raw zone created."
fi

ZONE_STATE="$(
  gcloud dataplex zones describe "${ZONE_ID}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --lake="${LAKE_ID}" \
    --format="value(state)"
)"

ZONE_UID="$(
  gcloud dataplex zones describe "${ZONE_ID}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --lake="${LAKE_ID}" \
    --format="value(uid)"
)"

echo -e "${CYAN}Zone state:${NC} ${ZONE_STATE}"
echo -e "${CYAN}Zone UID:${NC}   ${ZONE_UID}"

success "Task 1 resources are ready."

# ============================================================
# Task 2: Create Cloud Storage bucket
# ============================================================
section "Task 2: Create and attach Cloud Storage bucket"

if gcloud storage buckets describe "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  >/dev/null 2>&1; then

  success "Bucket gs://${BUCKET_NAME} already exists."
else
  info "Creating bucket gs://${BUCKET_NAME}"

  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --quiet

  success "Cloud Storage bucket created."
fi

BUCKET_LOCATION="$(
  gcloud storage buckets describe "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --format="value(location)"
)"

echo -e "${CYAN}Bucket location:${NC} ${BUCKET_LOCATION}"

# ============================================================
# Authorize Dataplex service agent
# ============================================================
info "Authorizing the Dataplex service agent for the bucket..."

if gcloud dataplex lakes authorize \
  --project="${PROJECT_ID}" \
  --storage-bucket-resource="${BUCKET_NAME}" \
  --quiet; then

  success "Dataplex service agent authorized."
else
  warning "Authorization command returned an error."
  warning "The service agent might already be authorized."
fi

# ============================================================
# Attach bucket as asset
# ============================================================
if gcloud dataplex assets describe "${ASSET_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --lake="${LAKE_ID}" \
  --zone="${ZONE_ID}" \
  >/dev/null 2>&1; then

  success "Asset ${ASSET_ID} already exists."
else
  info "Attaching the bucket as asset: ${ASSET_DISPLAY_NAME}"

  retry 6 15 \
    gcloud dataplex assets create "${ASSET_ID}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --lake="${LAKE_ID}" \
      --zone="${ZONE_ID}" \
      --display-name="${ASSET_DISPLAY_NAME}" \
      --description="Raw customer event files" \
      --resource-type="STORAGE_BUCKET" \
      --resource-name="projects/${PROJECT_NUMBER}/buckets/${BUCKET_NAME}" \
      --resource-read-access-mode="DIRECT" \
      --quiet

  success "Cloud Storage bucket attached to the raw zone."
fi

ASSET_STATE="$(
  gcloud dataplex assets describe "${ASSET_ID}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --lake="${LAKE_ID}" \
    --zone="${ZONE_ID}" \
    --format="value(state)"
)"

echo -e "${CYAN}Asset state:${NC} ${ASSET_STATE}"

success "Task 2 resources are ready."

# ============================================================
# Task 3: Create aspect metadata template
# ============================================================
section "Task 3: Create and attach the aspect"

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
        "description": "Indicates whether raw data is protected",
        "displayOrder": 1
      }
    }
  ]
}
JSON

success "Aspect metadata template created."

echo
echo -e "${GRAY}---------------- Aspect template ----------------${NC}"
jq . "${ASPECT_TEMPLATE_FILE}"
echo -e "${GRAY}-------------------------------------------------${NC}"

# ============================================================
# Create aspect type
# ============================================================
if gcloud dataplex aspect-types describe "${ASPECT_TYPE_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  >/dev/null 2>&1; then

  success "Aspect type ${ASPECT_TYPE_ID} already exists."
else
  info "Creating aspect type: ${ASPECT_DISPLAY_NAME}"

  retry 5 15 \
    gcloud dataplex aspect-types create "${ASPECT_TYPE_ID}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --display-name="${ASPECT_DISPLAY_NAME}" \
      --description="Identifies protected raw data" \
      --metadata-template-file-name="${ASPECT_TEMPLATE_FILE}" \
      --quiet

  success "Aspect type created."
fi

ASPECT_TYPE_NAME="$(
  gcloud dataplex aspect-types describe "${ASPECT_TYPE_ID}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --format="value(name)"
)"

echo -e "${CYAN}Aspect type:${NC} ${ASPECT_TYPE_NAME}"

# ============================================================
# Create aspect instance data
# ============================================================
cat > "${ASPECT_DATA_FILE}" <<JSON
{
  "${ASPECT_KEY}": {
    "data": {
      "${ASPECT_FIELD_ID}": "Y"
    }
  }
}
JSON

success "Aspect data file created."

echo
echo -e "${GRAY}------------------ Aspect data ------------------${NC}"
jq . "${ASPECT_DATA_FILE}"
echo -e "${GRAY}-------------------------------------------------${NC}"

# ============================================================
# Locate zone entry
# ============================================================
info "Locating the Knowledge Catalog entry for ${ZONE_DISPLAY_NAME}..."
echo -e "${CYAN}Exact FQN:${NC} ${ZONE_FQN}"

ZONE_ENTRY_NAME=""

for attempt in {1..30}; do
  ZONE_ENTRY_NAME="$(find_zone_entry || true)"

  if [[ -n "${ZONE_ENTRY_NAME}" && "${ZONE_ENTRY_NAME}" != "null" ]]; then
    echo
    success "Knowledge Catalog zone entry found."
    break
  fi

  warning "Zone entry is not available yet (${attempt}/30)."
  sleep 10
done

if [[ -z "${ZONE_ENTRY_NAME}" || "${ZONE_ENTRY_NAME}" == "null" ]]; then
  echo
  error "Unable to locate the zone entry after multiple attempts."
  echo
  info "Diagnostic search results:"

  gcloud dataplex entries search \
    "displayname:\"${ZONE_DISPLAY_NAME}\"" \
    --project="${PROJECT_ID}" \
    --scope="projects/${PROJECT_ID}" \
    --limit=20 \
    --format="table(
      dataplexEntry.name:label=ENTRY,
      dataplexEntry.displayName:label=DISPLAY_NAME,
      dataplexEntry.fullyQualifiedName:label=FQN
    )" || true

  exit 1
fi

echo -e "${CYAN}Entry resource:${NC}"
echo "${ZONE_ENTRY_NAME}"

# ============================================================
# Attach aspect to the zone
# ============================================================
info "Attaching ${ASPECT_DISPLAY_NAME} to ${ZONE_DISPLAY_NAME}..."

ASPECT_ATTACHED=false

# Preferred command for first-party/system entries.
if gcloud dataplex entries modify "${ZONE_ENTRY_NAME}" \
  --project="${PROJECT_ID}" \
  --update-aspects="${ASPECT_DATA_FILE}" \
  --quiet; then

  ASPECT_ATTACHED=true
  success "Aspect attached with 'entries modify'."
else
  warning "'entries modify' did not succeed."
  info "Trying 'entries update-aspects'..."

  if gcloud dataplex entries update-aspects "${ZONE_ENTRY_NAME}" \
    --project="${PROJECT_ID}" \
    --aspects="${ASPECT_DATA_FILE}" \
    --quiet; then

    ASPECT_ATTACHED=true
    success "Aspect attached with 'entries update-aspects'."
  fi
fi

if [[ "${ASPECT_ATTACHED}" != "true" ]]; then
  error "Unable to attach the aspect to the zone."
  exit 1
fi

# ============================================================
# Verify attached aspect
# ============================================================
info "Verifying the attached aspect..."

if gcloud dataplex entries lookup "${ZONE_ENTRY_NAME}" \
  --project="${PROJECT_ID}" \
  --view="all" \
  --format="yaml(
    name,
    displayName,
    fullyQualifiedName,
    aspects
  )"; then

  success "Aspect verification completed."
else
  warning "Lookup verification failed; trying describe..."

  gcloud dataplex entries describe "${ZONE_ENTRY_NAME}" \
    --project="${PROJECT_ID}" \
    --view="all" \
    --format="yaml(
      name,
      displayName,
      fullyQualifiedName,
      aspects
    )" || true
fi

# ============================================================
# Final resource verification
# ============================================================
section "Final resource verification"

echo -e "${CYAN}Lake${NC}"

gcloud dataplex lakes describe "${LAKE_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    name.basename():label=ID,
    state:label=STATE
  )"

echo
echo -e "${CYAN}Raw zone${NC}"

gcloud dataplex zones describe "${ZONE_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --lake="${LAKE_ID}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    name.basename():label=ID,
    type:label=TYPE,
    resourceSpec.locationType:label=LOCATION_TYPE,
    state:label=STATE
  )"

echo
echo -e "${CYAN}Cloud Storage bucket${NC}"

gcloud storage buckets describe "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  --format="table(
    name:label=BUCKET,
    location:label=LOCATION,
    storageClass:label=STORAGE_CLASS
  )"

echo
echo -e "${CYAN}Dataplex asset${NC}"

gcloud dataplex assets describe "${ASSET_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --lake="${LAKE_ID}" \
  --zone="${ZONE_ID}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    name.basename():label=ID,
    resourceSpec.type:label=TYPE,
    resourceSpec.name:label=RESOURCE,
    state:label=STATE
  )"

echo
echo -e "${CYAN}Aspect type${NC}"

gcloud dataplex aspect-types describe "${ASPECT_TYPE_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    name.basename():label=ID,
    uid:label=UID
  )"

echo
echo -e "${CYAN}Aspect search verification${NC}"

gcloud dataplex entries search \
  "aspect=${ASPECT_KEY}" \
  --project="${PROJECT_ID}" \
  --scope="projects/${PROJECT_ID}" \
  --limit=20 \
  --format="table(
    dataplexEntry.displayName:label=DISPLAY_NAME,
    dataplexEntry.fullyQualifiedName:label=FQN,
    dataplexEntry.name:label=ENTRY
  )" || true

# ============================================================
# Completion banner
# ============================================================
echo
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  ALL TASKS COMPLETED                      ║"
echo "╠════════════════════════════════════════════════════════════╣"
printf "║ %-58s ║\n" "Project: ${PROJECT_ID}"
printf "║ %-58s ║\n" "Region: ${REGION}"
printf "║ %-58s ║\n" "Lake: ${LAKE_DISPLAY_NAME}"
printf "║ %-58s ║\n" "Zone: ${ZONE_DISPLAY_NAME}"
printf "║ %-58s ║\n" "Asset: ${ASSET_DISPLAY_NAME}"
printf "║ %-58s ║\n" "Aspect: ${ASPECT_DISPLAY_NAME}"
printf "║ %-58s ║\n" "Protected Raw Data Flag: Y"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║                     © ePlus.DEV                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}Click Check my progress for all three tasks.${NC}"
EOF

chmod +x lab.sh
./lab.sh