#!/bin/bash

# ============================================================
#      © ePlus.DEV - Lakehouse Sensitive Data Challenge
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
ASPECT_LOCATION="us"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
BUCKET_NAME="${PROJECT_ID}-bucket"
SOURCE_URI="gs://${BUCKET_NAME}/user-online-sessions.csv"

TEMPLATE_FILE="/tmp/sensitive-data-template.json"
ASPECTS_FILE="/tmp/sensitive-data-aspects.json"
TABLE_DEF_FILE="/tmp/user-online-sessions-tabledef.json"
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
echo -e "${WHITE}Source     : ${CYAN}${SOURCE_URI}${NC}"
echo

# ============================================================
# Enter User 2 email
# ============================================================

echo -e "${YELLOW}${BOLD}Enter the User 2 email from the Lab Details panel.${NC}"
echo -e "${YELLOW}Example for this lab: student-04-e4dc84c46848@qwiklabs.net${NC}"
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
  --quiet || fail "Unable to enable the required APIs."

success "Required APIs are enabled."

# ============================================================
# Step 2: Create BigQuery dataset
# ============================================================

step "[2/9] Creating the US multi-region BigQuery dataset"

if bq show --dataset "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
  warning "Dataset ${DATASET_NAME} already exists."
else
  bq --location=US mk \
    --dataset \
    "${PROJECT_ID}:${DATASET_NAME}" \
    || fail "Unable to create the BigQuery dataset."
fi

DATASET_LOCATION="$(
  bq show \
    --format=json \
    "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null |
    jq -r '.location // empty'
)"

if [[ "${DATASET_LOCATION^^}" != "US" ]]; then
  fail "Dataset location is ${DATASET_LOCATION:-unknown}, but the lab requires US."
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
    || fail "Unable to create the BigQuery Cloud Resource connection."
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
  fail "Unable to detect the connection service account."
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

success "The connection service account can read Cloud Storage objects."

# ============================================================
# Step 5: Create BigLake/Lakehouse table
# ============================================================

step "[5/9] Creating the BigLake Lakehouse table"

if ! gcloud storage objects describe "$SOURCE_URI" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  fail "Source file was not found: ${SOURCE_URI}"
fi

success "Source CSV file exists."

rm -f "$TABLE_DEF_FILE"

bq mkdef \
  --autodetect \
  --connection_id="${PROJECT_ID}.US.${CONNECTION_NAME}" \
  --source_format=CSV \
  "$SOURCE_URI" \
  > "$TABLE_DEF_FILE" \
  || fail "Unable to create the external table definition."

if [[ ! -s "$TABLE_DEF_FILE" ]]; then
  fail "The external table definition is empty."
fi

# Remove an incomplete table from a previous attempt.
if bq show \
  "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" >/dev/null 2>&1; then

  warning "Table ${TABLE_NAME} already exists. It will be recreated."

  bq rm \
    --force \
    --table \
    "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" \
    || fail "Unable to remove the existing table."
fi

TABLE_CREATED=false

for attempt in $(seq 1 18); do
  if bq mk \
    --table \
    --external_table_definition="$TABLE_DEF_FILE" \
    "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}"; then

    TABLE_CREATED=true
    break
  fi

  warning "Table creation is waiting for IAM/API propagation. Retrying..."
  sleep 10
done

if [[ "$TABLE_CREATED" != "true" ]]; then
  fail "Unable to create the BigLake table."
fi

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

TABLE_SOURCE="$(
  echo "$TABLE_INFO" |
    jq -r '.externalDataConfiguration.sourceUris[0] // empty'
)"

if [[ "$TABLE_TYPE" != "EXTERNAL" ]]; then
  fail "The created table is not an external BigLake table."
fi

if [[ "$TABLE_CONNECTION" != *"/connections/${CONNECTION_NAME}" ]]; then
  fail "The BigLake table is not using ${CONNECTION_NAME}."
fi

if [[ "$TABLE_SOURCE" != "$SOURCE_URI" ]]; then
  fail "The BigLake table is not using the expected source file."
fi

success "BigLake table ${DATASET_NAME}.${TABLE_NAME} was created."
echo -e "${WHITE}Connection: ${CYAN}${TABLE_CONNECTION}${NC}"

# ============================================================
# Step 6: Create Sensitive Data Aspect type
# ============================================================

step "[6/9] Creating the Sensitive Data Aspect type"

cat > "$TEMPLATE_FILE" <<'JSON'
{
  "name": "Sensitive Data Aspect",
  "type": "record",
  "recordFields": [
    {
      "index": 1,
      "name": "has-sensitive-data",
      "type": "bool",
      "constraints": {
        "required": false
      },
      "annotations": {
        "displayName": "Has Sensitive Data",
        "description": "Indicates whether this column contains sensitive data.",
        "displayOrder": 1
      }
    }
  ]
}
JSON

if gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" \
  --location="$ASPECT_LOCATION" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  warning "Aspect type ${ASPECT_TYPE_ID} already exists."

  gcloud dataplex aspect-types update "$ASPECT_TYPE_ID" \
    --location="$ASPECT_LOCATION" \
    --project="$PROJECT_ID" \
    --display-name="Sensitive Data Aspect" \
    --description="Identifies columns that contain sensitive data." \
    --metadata-template-file-name="$TEMPLATE_FILE" \
    --quiet >/dev/null 2>&1 || true
else
  gcloud dataplex aspect-types create "$ASPECT_TYPE_ID" \
    --location="$ASPECT_LOCATION" \
    --project="$PROJECT_ID" \
    --display-name="Sensitive Data Aspect" \
    --description="Identifies columns that contain sensitive data." \
    --metadata-template-file-name="$TEMPLATE_FILE" \
    --quiet \
    || fail "Unable to create the Sensitive Data Aspect type."
fi

ASPECT_INFO="$(
  gcloud dataplex aspect-types describe "$ASPECT_TYPE_ID" \
    --location="$ASPECT_LOCATION" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null
)"

if ! echo "$ASPECT_INFO" | jq -e '
  .displayName == "Sensitive Data Aspect"
  and
  (
    .metadataTemplate.recordFields
    | any(
        .name == "has-sensitive-data"
        and .type == "bool"
        and .annotations.displayName == "Has Sensitive Data"
    )
  )
' >/dev/null; then
  fail "The Sensitive Data Aspect type or Boolean field is not configured correctly."
fi

success "Sensitive Data Aspect was created in the US multi-region."
success "Boolean field Has Sensitive Data was created."

# ============================================================
# Step 7: Find the Knowledge Catalog entry
# ============================================================

step "[7/9] Finding the Knowledge Catalog entry for the table"

ENTRY_LOCATION="us"
ENTRY_GROUP="@bigquery"

ENTRY_ID="bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${DATASET_NAME}/tables/${TABLE_NAME}"

FQN="bigquery:${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}"

ENTRY_FOUND=false

for attempt in $(seq 1 30); do
  if gcloud dataplex entries lookup "$ENTRY_ID" \
    --entry-group="$ENTRY_GROUP" \
    --location="$ENTRY_LOCATION" \
    --project="$PROJECT_ID" \
    --view=full \
    --format=json \
    > "$ENTRY_FILE" 2>/dev/null; then

    ENTRY_FOUND=true
    break
  fi

  # Fallback: search by exact fully qualified name.
  SEARCH_RESULTS="$(
    gcloud dataplex entries search \
      "fully_qualified_name=${FQN}" \
      --project="$PROJECT_ID" \
      --scope="projects/${PROJECT_ID}" \
      --limit=10 \
      --format=json 2>/dev/null
  )"

  ENTRY_NAME="$(
    echo "$SEARCH_RESULTS" |
      jq -r --arg fqn "$FQN" '
        .[]?
        | (.dataplexEntry // .entry // .) as $entry
        | select($entry.fullyQualifiedName == $fqn)
        | $entry.name
      ' |
      head -n 1
  )"

  if [[ -n "$ENTRY_NAME" && "$ENTRY_NAME" != "null" ]]; then
    ENTRY_LOCATION="$(
      echo "$ENTRY_NAME" |
        sed -E 's#^projects/[^/]+/locations/([^/]+)/.*#\1#'
    )"

    ENTRY_GROUP="$(
      echo "$ENTRY_NAME" |
        sed -E 's#^.*/entryGroups/([^/]+)/entries/.*#\1#'
    )"

    ENTRY_ID="$(
      echo "$ENTRY_NAME" |
        sed -E 's#^.*/entries/##'
    )"

    ENTRY_FOUND=true
    break
  fi

  warning "Knowledge Catalog is indexing the BigQuery table. Retrying..."
  sleep 5
done

if [[ "$ENTRY_FOUND" != "true" ]]; then
  fail "Unable to find the Knowledge Catalog entry for ${FQN}."
fi

echo -e "${WHITE}Entry location : ${CYAN}${ENTRY_LOCATION}${NC}"
echo -e "${WHITE}Entry group    : ${CYAN}${ENTRY_GROUP}${NC}"
echo -e "${WHITE}Entry ID       : ${CYAN}${ENTRY_ID}${NC}"

success "Knowledge Catalog entry was found."

# ============================================================
# Step 8: Apply aspect to sensitive columns
# ============================================================

step "[8/9] Applying the aspect to sensitive columns"

ASPECT_REFERENCE="${PROJECT_ID}.${ASPECT_LOCATION}.${ASPECT_TYPE_ID}"

cat > "$ASPECTS_FILE" <<JSON
{
  "${ASPECT_REFERENCE}@Schema.zip": {
    "data": {
      "has-sensitive-data": true
    }
  },
  "${ASPECT_REFERENCE}@Schema.latitude": {
    "data": {
      "has-sensitive-data": true
    }
  },
  "${ASPECT_REFERENCE}@Schema.ip_address": {
    "data": {
      "has-sensitive-data": true
    }
  },
  "${ASPECT_REFERENCE}@Schema.longitude": {
    "data": {
      "has-sensitive-data": true
    }
  }
}
JSON

ASPECT_APPLIED=false

for attempt in $(seq 1 12); do
  if gcloud dataplex entries modify "$ENTRY_ID" \
    --entry-group="$ENTRY_GROUP" \
    --location="$ENTRY_LOCATION" \
    --project="$PROJECT_ID" \
    --update-aspects="$ASPECTS_FILE" \
    --quiet; then

    ASPECT_APPLIED=true
    break
  fi

  warning "Aspect attachment is waiting for catalog propagation. Retrying..."
  sleep 10
done

if [[ "$ASPECT_APPLIED" != "true" ]]; then
  fail "Unable to apply the aspect to the sensitive columns."
fi

gcloud dataplex entries lookup "$ENTRY_ID" \
  --entry-group="$ENTRY_GROUP" \
  --location="$ENTRY_LOCATION" \
  --project="$PROJECT_ID" \
  --view=all \
  --format=json \
  > "$ENTRY_FILE" \
  || fail "Unable to verify the attached aspects."

VERIFY_FAILED=false

for COLUMN_NAME in zip latitude ip_address longitude; do
  ASPECT_SUFFIX=".${ASPECT_LOCATION}.${ASPECT_TYPE_ID}@Schema.${COLUMN_NAME}"

  if jq -e --arg suffix "$ASPECT_SUFFIX" '
    [
      (.aspects // {})
      | to_entries[]
      | select(
          (.key | endswith($suffix))
          and
          (.value.data["has-sensitive-data"] == true)
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
  fail "One or more sensitive columns do not have the required aspect."
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
    sort -u
)"

if [[ -z "$STORAGE_ROLES" ]]; then
  warning "No direct Cloud Storage project role was found for ${USER_2}."
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

REMAINING_STORAGE_ROLES="$(
  gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:${USER_2}" \
    --format="value(bindings.role)" 2>/dev/null |
    grep '^roles/storage\.' || true
)"

if [[ -n "$REMAINING_STORAGE_ROLES" ]]; then
  echo "$REMAINING_STORAGE_ROLES"
  fail "User 2 still has a direct Cloud Storage project role."
fi

if echo "$(
  gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:${USER_2}" \
    --format="value(bindings.role)" 2>/dev/null
)" | grep -Fxq "roles/viewer"; then
  success "Project Viewer role remains assigned to User 2."
else
  warning "No direct roles/viewer binding was detected. The script did not remove or modify Viewer access."
fi

# ============================================================
# Final verification
# ============================================================

echo
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 LAB CONFIGURATION COMPLETE               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${WHITE}Project ID:${NC}       ${CYAN}${PROJECT_ID}${NC}"
echo -e "${WHITE}Dataset:${NC}          ${CYAN}${DATASET_NAME}${NC}"
echo -e "${WHITE}BigLake table:${NC}     ${CYAN}${TABLE_NAME}${NC}"
echo -e "${WHITE}Connection:${NC}       ${CYAN}${CONNECTION_NAME}${NC}"
echo -e "${WHITE}Aspect type:${NC}      ${CYAN}Sensitive Data Aspect${NC}"
echo -e "${WHITE}Aspect location:${NC}  ${CYAN}${ASPECT_LOCATION}${NC}"
echo -e "${WHITE}User 2:${NC}           ${CYAN}${USER_2}${NC}"

echo
echo -e "${GREEN}${BOLD}Sensitive columns:${NC}"
echo "  ✓ zip"
echo "  ✓ latitude"
echo "  ✓ ip_address"
echo "  ✓ longitude"

echo
echo -e "${YELLOW}${BOLD}Return to the lab page and click Check my progress for all three tasks.${NC}"
echo -e "${MAGENTA}${BOLD}© ePlus.DEV${NC}"
echo

rm -f \
  "$TEMPLATE_FILE" \
  "$ASPECTS_FILE" \
  "$TABLE_DEF_FILE" \
  "$ENTRY_FILE"