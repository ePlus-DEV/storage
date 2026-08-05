#!/usr/bin/env bash

# ============================================================
#   © ePlus.DEV - Lakehouse Sensitive Data Challenge Lab
# ============================================================

clear

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

DATASET_NAME="online_shop"
TABLE_NAME="user_online_sessions"
CONNECTION_NAME="user_data_connection"

ASPECT_TYPE_ID="sensitive-data-aspect"
ASPECT_DISPLAY_NAME="Sensitive Data Aspect"
ASPECT_LOCATION="us"
ASPECT_FIELD_ID="has-sensitive-data"
ASPECT_FIELD_DISPLAY_NAME="Has Sensitive Data"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
BUCKET_NAME="${PROJECT_ID}-bucket"
SOURCE_URI="gs://${BUCKET_NAME}/user-online-sessions.csv"

TABLE_DEF_FILE="/tmp/user-online-sessions-tabledef.json"
ASPECT_TEMPLATE_FILE="/tmp/sensitive-data-template.json"
ASPECT_VALUES_FILE="/tmp/sensitive-data-values.json"
ENTRY_FILE="/tmp/user-online-sessions-entry.json"

fail() {
  echo
  echo -e "${RED}${BOLD}ERROR: $1${NC}"
  echo
  exit 1
}

success() {
  echo -e "${GREEN}✓ $1${NC}"
}

warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

step() {
  echo
  echo -e "${CYAN}${BOLD}============================================================${NC}"
  echo -e "${CYAN}${BOLD}$1${NC}"
  echo -e "${CYAN}${BOLD}============================================================${NC}"
}

normalize_connection_name() {
  local connection_value="$1"

  connection_value="${connection_value##*/}"
  connection_value="${connection_value##*.}"

  printf '%s' "$connection_value"
}

cleanup() {
  rm -f \
    "$TABLE_DEF_FILE" \
    "$ASPECT_TEMPLATE_FILE" \
    "$ASPECT_VALUES_FILE" \
    "$ENTRY_FILE"
}

trap cleanup EXIT

# ============================================================
# Banner
# ============================================================

echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     © ePlus.DEV - Lakehouse Sensitive Data Challenge    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  fail "Unable to detect the Google Cloud Project ID."
fi

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

echo -e "${WHITE}Project ID : ${CYAN}${PROJECT_ID}${NC}"
echo -e "${WHITE}Dataset    : ${CYAN}${DATASET_NAME}${NC}"
echo -e "${WHITE}Table      : ${CYAN}${TABLE_NAME}${NC}"
echo -e "${WHITE}Connection : ${CYAN}${CONNECTION_NAME}${NC}"
echo -e "${WHITE}Source URI : ${CYAN}${SOURCE_URI}${NC}"
echo

# ============================================================
# Require User 2 email
# ============================================================

echo -e "${YELLOW}${BOLD}Enter the User 2 email from the Lab Details panel.${NC}"
echo -e "${YELLOW}Current lab example: student-04-e4dc84c46848@qwiklabs.net${NC}"
echo

while true; do
  read -r -p "User 2 email: " USER_2

  USER_2="$(echo "$USER_2" | xargs)"

  if [[ -z "$USER_2" ]]; then
    echo -e "${RED}User 2 email is required.${NC}"
    continue
  fi

  if [[ ! "$USER_2" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo -e "${RED}Invalid email address. Please enter it again.${NC}"
    continue
  fi

  break
done

echo
success "User 2 email: ${USER_2}"

# ============================================================
# Step 1: Enable APIs
# ============================================================

step "[1/9] Enabling required Google Cloud APIs"

gcloud services enable \
  bigquery.googleapis.com \
  bigqueryconnection.googleapis.com \
  dataplex.googleapis.com \
  datacatalog.googleapis.com \
  storage.googleapis.com \
  serviceusage.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet \
  || fail "Unable to enable the required APIs."

success "Required APIs are enabled."

# ============================================================
# Step 2: Create US dataset
# ============================================================

step "[2/9] Creating the US multi-region BigQuery dataset"

if bq show \
  --dataset \
  "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then

  warning "Dataset ${DATASET_NAME} already exists."
else
  bq --location=US mk \
    --dataset \
    "${PROJECT_ID}:${DATASET_NAME}" \
    || fail "Unable to create dataset ${DATASET_NAME}."
fi

DATASET_LOCATION="$(
  bq show \
    --format=json \
    "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null |
    jq -r '.location // empty'
)"

if [[ "${DATASET_LOCATION^^}" != "US" ]]; then
  fail "Dataset location is ${DATASET_LOCATION:-unknown}. The lab requires US."
fi

success "Dataset ${DATASET_NAME} exists in US."

# ============================================================
# Step 3: Create Cloud Resource connection
# ============================================================

step "[3/9] Creating the Cloud Resource connection"

if bq show \
  --connection \
  --format=json \
  "${PROJECT_ID}.US.${CONNECTION_NAME}" >/dev/null 2>&1; then

  warning "Connection ${CONNECTION_NAME} already exists."
else
  bq mk \
    --connection \
    --location=US \
    --project_id="$PROJECT_ID" \
    --connection_type=CLOUD_RESOURCE \
    "$CONNECTION_NAME" \
    || fail "Unable to create connection ${CONNECTION_NAME}."
fi

CONNECTION_INFO="$(
  bq show \
    --connection \
    --format=json \
    "${PROJECT_ID}.US.${CONNECTION_NAME}" 2>/dev/null
)"

CONNECTION_SERVICE_ACCOUNT="$(
  echo "$CONNECTION_INFO" |
    jq -r '.cloudResource.serviceAccountId // empty'
)"

if [[ -z "$CONNECTION_SERVICE_ACCOUNT" ]]; then
  fail "Unable to detect the Cloud Resource connection service account."
fi

echo -e "${WHITE}Connection service account:${NC}"
echo -e "${CYAN}${CONNECTION_SERVICE_ACCOUNT}${NC}"

success "Cloud Resource connection is ready."

# ============================================================
# Step 4: Grant Storage access to connection service account
# ============================================================

step "[4/9] Granting Cloud Storage access to the connection"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${CONNECTION_SERVICE_ACCOUNT}" \
  --role="roles/storage.objectViewer" \
  --condition=None \
  --quiet >/dev/null \
  || fail "Unable to grant Storage Object Viewer to the connection service account."

success "Connection service account can read Cloud Storage."

# ============================================================
# Step 5: Create BigLake table
# ============================================================

step "[5/9] Creating the BigLake Lakehouse table"

if ! gcloud storage objects describe "$SOURCE_URI" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  fail "Source file was not found: ${SOURCE_URI}"
fi

success "Source CSV file exists."

TABLE_EXISTS=false
TABLE_VALID=false

if bq show \
  "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" >/dev/null 2>&1; then

  TABLE_EXISTS=true

  TABLE_INFO="$(
    bq show \
      --format=json \
      "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" 2>/dev/null
  )"

  TABLE_TYPE="$(echo "$TABLE_INFO" | jq -r '.type // empty')"

  TABLE_CONNECTION="$(
    echo "$TABLE_INFO" |
      jq -r '.externalDataConfiguration.connectionId // empty'
  )"

  TABLE_CONNECTION_NAME="$(
    normalize_connection_name "$TABLE_CONNECTION"
  )"

  TABLE_SOURCE="$(
    echo "$TABLE_INFO" |
      jq -r '.externalDataConfiguration.sourceUris[0] // empty'
  )"

  if [[ "$TABLE_TYPE" == "EXTERNAL" ]] &&
     [[ "$TABLE_CONNECTION_NAME" == "$CONNECTION_NAME" ]] &&
     [[ "$TABLE_SOURCE" == "$SOURCE_URI" ]]; then

    TABLE_VALID=true
  fi
fi

if [[ "$TABLE_EXISTS" == "true" && "$TABLE_VALID" == "true" ]]; then
  warning "A correctly configured BigLake table already exists."
else
  if [[ "$TABLE_EXISTS" == "true" ]]; then
    warning "Existing table is not configured correctly. Recreating it."

    bq rm \
      --force \
      --table \
      "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" \
      || fail "Unable to remove the existing table."
  fi

  rm -f "$TABLE_DEF_FILE"

  bq mkdef \
    --autodetect \
    --connection_id="${PROJECT_ID}.US.${CONNECTION_NAME}" \
    --source_format=CSV \
    "$SOURCE_URI" \
    > "$TABLE_DEF_FILE" \
    || fail "Unable to create the external table definition."

  if [[ ! -s "$TABLE_DEF_FILE" ]]; then
    fail "External table definition file is empty."
  fi

  TABLE_CREATED=false

  for ATTEMPT in $(seq 1 18); do
    if bq mk \
      --table \
      --external_table_definition="$TABLE_DEF_FILE" \
      "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}"; then

      TABLE_CREATED=true
      break
    fi

    warning "Waiting for IAM and API propagation before retrying table creation..."
    sleep 10
  done

  if [[ "$TABLE_CREATED" != "true" ]]; then
    fail "Unable to create the BigLake table."
  fi
fi

TABLE_VERIFIED=false

for ATTEMPT in $(seq 1 10); do
  TABLE_INFO="$(
    bq show \
      --format=json \
      "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" 2>/dev/null
  )"

  TABLE_TYPE="$(echo "$TABLE_INFO" | jq -r '.type // empty')"

  TABLE_CONNECTION="$(
    echo "$TABLE_INFO" |
      jq -r '.externalDataConfiguration.connectionId // empty'
  )"

  TABLE_CONNECTION_NAME="$(
    normalize_connection_name "$TABLE_CONNECTION"
  )"

  TABLE_SOURCE="$(
    echo "$TABLE_INFO" |
      jq -r '.externalDataConfiguration.sourceUris[0] // empty'
  )"

  if [[ "$TABLE_TYPE" == "EXTERNAL" ]] &&
     [[ "$TABLE_CONNECTION_NAME" == "$CONNECTION_NAME" ]] &&
     [[ "$TABLE_SOURCE" == "$SOURCE_URI" ]]; then

    TABLE_VERIFIED=true
    break
  fi

  sleep 5
done

if [[ "$TABLE_VERIFIED" != "true" ]]; then
  echo -e "${YELLOW}Returned connection ID: ${TABLE_CONNECTION:-empty}${NC}"
  echo -e "${YELLOW}Returned source URI   : ${TABLE_SOURCE:-empty}${NC}"
  fail "The BigLake table configuration could not be verified."
fi

success "BigLake table ${DATASET_NAME}.${TABLE_NAME} is configured correctly."
echo -e "${WHITE}Connection ID:${NC} ${CYAN}${TABLE_CONNECTION}${NC}"

# ============================================================
# Step 6: Create Sensitive Data Aspect type
# ============================================================

step "[6/9] Creating the Sensitive Data Aspect type"

cat > "$ASPECT_TEMPLATE_FILE" <<JSON
{
  "name": "${ASPECT_TYPE_ID}",
  "type": "record",
  "recordFields": [
    {
      "index": 1,
      "name": "${ASPECT_FIELD_ID}",
      "type": "bool",
      "constraints": {
        "required": false
      },
      "annotations": {
        "displayName": "${ASPECT_FIELD_DISPLAY_NAME}",
        "description": "Indicates whether the column contains sensitive data.",
        "displayOrder": 1
      }
    }
  ]
}
JSON

# Validate generated JSON before sending it to Google Cloud.
jq empty "$ASPECT_TEMPLATE_FILE" \
  || fail "Generated aspect template JSON is invalid."

ASPECT_EXISTS=false
ASPECT_CORRECT=false

if gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" \
  --location="$ASPECT_LOCATION" \
  --project="$PROJECT_ID" \
  --format=json > /tmp/existing-aspect.json 2>/dev/null; then

  ASPECT_EXISTS=true

  if jq -e \
    --arg display_name "$ASPECT_DISPLAY_NAME" \
    --arg field_id "$ASPECT_FIELD_ID" \
    --arg field_display "$ASPECT_FIELD_DISPLAY_NAME" '
      .displayName == $display_name
      and
      (
        .metadataTemplate.recordFields
        | any(
            .name == $field_id
            and .type == "bool"
            and .annotations.displayName == $field_display
          )
      )
    ' /tmp/existing-aspect.json >/dev/null; then

    ASPECT_CORRECT=true
  fi
fi

rm -f /tmp/existing-aspect.json

if [[ "$ASPECT_EXISTS" == "true" && "$ASPECT_CORRECT" == "true" ]]; then
  warning "Sensitive Data Aspect already exists and is configured correctly."
else
  if [[ "$ASPECT_EXISTS" == "true" ]]; then
    warning "Existing aspect type is incorrect. Recreating it."

    gcloud dataplex aspect-types delete "$ASPECT_TYPE_ID" \
      --location="$ASPECT_LOCATION" \
      --project="$PROJECT_ID" \
      --quiet \
      || fail "Unable to delete the incorrect aspect type."
  fi

  gcloud dataplex aspect-types create "$ASPECT_TYPE_ID" \
    --location="$ASPECT_LOCATION" \
    --project="$PROJECT_ID" \
    --display-name="$ASPECT_DISPLAY_NAME" \
    --description="Identifies columns containing sensitive data." \
    --metadata-template-file-name="$ASPECT_TEMPLATE_FILE" \
    --quiet \
    || fail "Unable to create the Sensitive Data Aspect type."
fi

ASPECT_INFO="$(
  gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" \
    --location="$ASPECT_LOCATION" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null
)"

if ! echo "$ASPECT_INFO" |
  jq -e \
    --arg display_name "$ASPECT_DISPLAY_NAME" \
    --arg template_name "$ASPECT_TYPE_ID" \
    --arg field_id "$ASPECT_FIELD_ID" \
    --arg field_display "$ASPECT_FIELD_DISPLAY_NAME" '
      .displayName == $display_name
      and .metadataTemplate.name == $template_name
      and
      (
        .metadataTemplate.recordFields
        | any(
            .name == $field_id
            and .type == "bool"
            and .annotations.displayName == $field_display
          )
      )
    ' >/dev/null; then

  echo "$ASPECT_INFO" | jq .
  fail "Sensitive Data Aspect verification failed."
fi

success "Aspect type: ${ASPECT_DISPLAY_NAME}"
success "Boolean field: ${ASPECT_FIELD_DISPLAY_NAME}"
success "Aspect location: ${ASPECT_LOCATION}"

# ============================================================
# Step 7: Locate Knowledge Catalog entry
# ============================================================

step "[7/9] Locating the Knowledge Catalog entry"

ENTRY_GROUP="@bigquery"
ENTRY_LOCATION="us"

ENTRY_ID="bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${DATASET_NAME}/tables/${TABLE_NAME}"

ENTRY_FOUND=false

for ATTEMPT in $(seq 1 36); do
  if gcloud dataplex entries lookup "$ENTRY_ID" \
    --entry-group="$ENTRY_GROUP" \
    --location="$ENTRY_LOCATION" \
    --project="$PROJECT_ID" \
    --view=all \
    --format=json \
    > "$ENTRY_FILE" 2>/dev/null; then

    ENTRY_FOUND=true
    break
  fi

  warning "Knowledge Catalog is indexing the BigQuery table. Retrying..."
  sleep 5
done

if [[ "$ENTRY_FOUND" != "true" ]]; then
  fail "Unable to locate the Knowledge Catalog entry for the BigLake table."
fi

success "Knowledge Catalog entry was found."
echo -e "${WHITE}Entry group:${NC} ${CYAN}${ENTRY_GROUP}${NC}"
echo -e "${WHITE}Entry ID   :${NC} ${CYAN}${ENTRY_ID}${NC}"

# ============================================================
# Step 8: Apply aspect to four sensitive columns
# ============================================================

step "[8/9] Applying the aspect to sensitive columns"

ASPECT_REFERENCE="${PROJECT_ID}.${ASPECT_LOCATION}.${ASPECT_TYPE_ID}"

cat > "$ASPECT_VALUES_FILE" <<JSON
{
  "${ASPECT_REFERENCE}@Schema.zip": {
    "data": {
      "${ASPECT_FIELD_ID}": true
    }
  },
  "${ASPECT_REFERENCE}@Schema.latitude": {
    "data": {
      "${ASPECT_FIELD_ID}": true
    }
  },
  "${ASPECT_REFERENCE}@Schema.ip_address": {
    "data": {
      "${ASPECT_FIELD_ID}": true
    }
  },
  "${ASPECT_REFERENCE}@Schema.longitude": {
    "data": {
      "${ASPECT_FIELD_ID}": true
    }
  }
}
JSON

jq empty "$ASPECT_VALUES_FILE" \
  || fail "Generated aspect values JSON is invalid."

ASPECT_APPLIED=false

for ATTEMPT in $(seq 1 18); do
  if gcloud dataplex entries modify "$ENTRY_ID" \
    --entry-group="$ENTRY_GROUP" \
    --location="$ENTRY_LOCATION" \
    --project="$PROJECT_ID" \
    --update-aspects="$ASPECT_VALUES_FILE" \
    --quiet; then

    ASPECT_APPLIED=true
    break
  fi

  warning "Waiting for aspect and catalog propagation before retrying..."
  sleep 10
done

if [[ "$ASPECT_APPLIED" != "true" ]]; then
  fail "Unable to apply the Sensitive Data Aspect to the table columns."
fi

gcloud dataplex entries lookup "$ENTRY_ID" \
  --entry-group="$ENTRY_GROUP" \
  --location="$ENTRY_LOCATION" \
  --project="$PROJECT_ID" \
  --view=all \
  --format=json \
  > "$ENTRY_FILE" \
  || fail "Unable to retrieve the entry for aspect verification."

VERIFY_FAILED=false

for COLUMN_NAME in zip latitude ip_address longitude; do
  ASPECT_SUFFIX=".${ASPECT_LOCATION}.${ASPECT_TYPE_ID}@Schema.${COLUMN_NAME}"

  if jq -e \
    --arg suffix "$ASPECT_SUFFIX" \
    --arg field_id "$ASPECT_FIELD_ID" '
      [
        (.aspects // {})
        | to_entries[]
        | select(
            (.key | endswith($suffix))
            and
            (.value.data[$field_id] == true)
          )
      ]
      | length > 0
    ' "$ENTRY_FILE" >/dev/null; then

    success "Aspect verified on column: ${COLUMN_NAME}"
  else
    echo -e "${RED}✗ Aspect was not found on column: ${COLUMN_NAME}${NC}"
    VERIFY_FAILED=true
  fi
done

if [[ "$VERIFY_FAILED" == "true" ]]; then
  echo
  echo -e "${YELLOW}Returned aspects:${NC}"
  jq '.aspects // {}' "$ENTRY_FILE"
  fail "One or more sensitive columns are missing the required aspect."
fi

# ============================================================
# Step 9: Remove User 2 direct Cloud Storage roles
# ============================================================

step "[9/9] Removing direct Cloud Storage IAM roles from User 2"

USER_ROLES="$(
  gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:${USER_2}" \
    --format="value(bindings.role)" 2>/dev/null
)"

STORAGE_ROLES="$(
  echo "$USER_ROLES" |
    grep '^roles/storage\.' |
    sort -u || true
)"

if [[ -z "$STORAGE_ROLES" ]]; then
  warning "No direct project-level Cloud Storage role was found for ${USER_2}."
else
  while IFS= read -r STORAGE_ROLE; do
    [[ -z "$STORAGE_ROLE" ]] && continue

    echo -e "${YELLOW}Removing ${STORAGE_ROLE} from ${USER_2}...${NC}"

    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
      --member="user:${USER_2}" \
      --role="$STORAGE_ROLE" \
      --condition=None \
      --quiet >/dev/null \
      || fail "Unable to remove ${STORAGE_ROLE} from ${USER_2}."

    success "Removed ${STORAGE_ROLE}"
  done <<< "$STORAGE_ROLES"
fi

REMAINING_USER_ROLES="$(
  gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:${USER_2}" \
    --format="value(bindings.role)" 2>/dev/null
)"

REMAINING_STORAGE_ROLES="$(
  echo "$REMAINING_USER_ROLES" |
    grep '^roles/storage\.' || true
)"

if [[ -n "$REMAINING_STORAGE_ROLES" ]]; then
  echo "$REMAINING_STORAGE_ROLES"
  fail "User 2 still has a direct Cloud Storage project role."
fi

success "User 2 no longer has a direct Cloud Storage project role."

if echo "$REMAINING_USER_ROLES" | grep -Fxq "roles/viewer"; then
  success "Project Viewer role remains assigned to User 2."
else
  warning "Direct roles/viewer was not detected. The script did not remove or change Viewer permissions."
fi

# ============================================================
# Final summary
# ============================================================

echo
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 LAB CONFIGURATION COMPLETE               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${WHITE}Project ID      :${NC} ${CYAN}${PROJECT_ID}${NC}"
echo -e "${WHITE}Dataset         :${NC} ${CYAN}${DATASET_NAME}${NC}"
echo -e "${WHITE}BigLake table   :${NC} ${CYAN}${TABLE_NAME}${NC}"
echo -e "${WHITE}Connection      :${NC} ${CYAN}${CONNECTION_NAME}${NC}"
echo -e "${WHITE}Aspect type     :${NC} ${CYAN}${ASPECT_DISPLAY_NAME}${NC}"
echo -e "${WHITE}Aspect field    :${NC} ${CYAN}${ASPECT_FIELD_DISPLAY_NAME}${NC}"
echo -e "${WHITE}Aspect location :${NC} ${CYAN}${ASPECT_LOCATION}${NC}"
echo -e "${WHITE}User 2          :${NC} ${CYAN}${USER_2}${NC}"

echo
echo -e "${GREEN}${BOLD}Protected columns:${NC}"
echo "  ✓ zip"
echo "  ✓ latitude"
echo "  ✓ ip_address"
echo "  ✓ longitude"

echo
echo -e "${YELLOW}${BOLD}Return to the lab page and click Check my progress for all tasks.${NC}"
echo -e "${MAGENTA}${BOLD}© ePlus.DEV${NC}"
echo