#!/bin/bash

clear

# ============================================================
#               © ePlus.DEV - BigLake Lab
# ============================================================

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

# Array of color codes excluding black and white
TEXT_COLORS=(
  "$RED"
  "$GREEN"
  "$YELLOW"
  "$BLUE"
  "$MAGENTA"
  "$CYAN"
)

BG_COLORS=(
  "$BG_RED"
  "$BG_GREEN"
  "$BG_YELLOW"
  "$BG_BLUE"
  "$BG_MAGENTA"
  "$BG_CYAN"
)

# Pick random colors
RANDOM_TEXT_COLOR=${TEXT_COLORS[$((RANDOM % ${#TEXT_COLORS[@]}))]}
RANDOM_BG_COLOR=${BG_COLORS[$((RANDOM % ${#BG_COLORS[@]}))]}

# ------------------------------------------------------------
# Project information
# ------------------------------------------------------------

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "${RED}${BOLD}Unable to detect the Google Cloud Project ID.${RESET}"
  exit 1
fi

export DEVSHELL_PROJECT_ID="$PROJECT_ID"

# ------------------------------------------------------------
# Banner
# ------------------------------------------------------------

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}"
echo "============================================================"
echo "            © ePlus.DEV - BigLake Lab"
echo "============================================================"
echo "${RESET}"

echo "${BOLD}${CYAN}Project ID: ${PROJECT_ID}${RESET}"
echo

# ------------------------------------------------------------
# Enter User 2 email
# ------------------------------------------------------------

echo "${BOLD}${YELLOW}Enter the email address of User 2 from the Lab Details panel.${RESET}"
echo

while true; do
  read -r -p "User 2 email: " USER_2

  # Remove leading and trailing spaces
  USER_2=$(echo "$USER_2" | xargs)

  if [[ -z "$USER_2" ]]; then
    echo "${RED}User 2 email is required. Please enter it again.${RESET}"
    echo
    continue
  fi

  if [[ ! "$USER_2" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "${RED}Invalid email address. Please enter it again.${RESET}"
    echo
    continue
  fi

  break
done

export USER_2

echo
echo "${GREEN}${BOLD}User 2: ${USER_2}${RESET}"
echo
echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Execution${RESET}"
echo

# ------------------------------------------------------------
# Step 1: Fetch taxonomy and policy tag details
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[1/10] Fetching taxonomy name, ID, and policy tag...${RESET}"

TAXONOMY_NAME=$(gcloud data-catalog taxonomies list \
  --location=us \
  --project="$PROJECT_ID" \
  --format="value(displayName)" \
  --limit=1)

if [[ -z "$TAXONOMY_NAME" ]]; then
  echo "${RED}No taxonomy was found in location us.${RESET}"
  exit 1
fi

TAXONOMY_RESOURCE=$(gcloud data-catalog taxonomies list \
  --location=us \
  --project="$PROJECT_ID" \
  --filter="displayName=${TAXONOMY_NAME}" \
  --format="value(name)" \
  --limit=1)

TAXONOMY_ID=$(echo "$TAXONOMY_RESOURCE" | awk -F'/' '{print $6}')

if [[ -z "$TAXONOMY_ID" ]]; then
  echo "${RED}Unable to detect the taxonomy ID.${RESET}"
  exit 1
fi

POLICY_TAG=$(gcloud data-catalog taxonomies policy-tags list \
  --location=us \
  --taxonomy="$TAXONOMY_ID" \
  --project="$PROJECT_ID" \
  --format="value(name)" \
  --limit=1)

if [[ -z "$POLICY_TAG" ]]; then
  echo "${RED}No policy tag was found in taxonomy ${TAXONOMY_NAME}.${RESET}"
  exit 1
fi

export TAXONOMY_NAME
export TAXONOMY_ID
export POLICY_TAG

echo "${GREEN}Taxonomy name: ${TAXONOMY_NAME}${RESET}"
echo "${GREEN}Taxonomy ID  : ${TAXONOMY_ID}${RESET}"
echo "${GREEN}Policy tag   : ${POLICY_TAG}${RESET}"
echo

# ------------------------------------------------------------
# Step 2: Create BigQuery dataset
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[2/10] Creating the BigQuery dataset...${RESET}"

if bq show --dataset "${PROJECT_ID}:online_shop" >/dev/null 2>&1; then
  echo "${YELLOW}Dataset online_shop already exists. Skipping creation.${RESET}"
else
  bq mk \
    --dataset \
    --location=US \
    "${PROJECT_ID}:online_shop"
fi

echo

# ------------------------------------------------------------
# Step 3: Create BigQuery connection
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[3/10] Creating the BigQuery connection...${RESET}"

if bq show \
  --connection \
  --location=US \
  "${PROJECT_ID}.US.user_data_connection" >/dev/null 2>&1; then

  echo "${YELLOW}Connection user_data_connection already exists. Skipping creation.${RESET}"
else
  bq mk \
    --connection \
    --location=US \
    --project_id="$PROJECT_ID" \
    --connection_type=CLOUD_RESOURCE \
    user_data_connection
fi

echo

# ------------------------------------------------------------
# Step 4: Grant Storage Object Viewer to connection SA
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[4/10] Granting the connection service account permission to read Cloud Storage...${RESET}"

SERVICE_ACCOUNT=$(bq show \
  --format=json \
  --connection \
  "${PROJECT_ID}.US.user_data_connection" |
  jq -r '.cloudResource.serviceAccountId')

if [[ -z "$SERVICE_ACCOUNT" || "$SERVICE_ACCOUNT" == "null" ]]; then
  echo "${RED}Unable to detect the BigQuery connection service account.${RESET}"
  exit 1
fi

export SERVICE_ACCOUNT

echo "${GREEN}Connection service account: ${SERVICE_ACCOUNT}${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/storage.objectViewer" \
  --quiet

echo

# ------------------------------------------------------------
# Step 5: Create external table definition
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[5/10] Creating the BigQuery table definition...${RESET}"

bq mkdef \
  --autodetect \
  --connection_id="${PROJECT_ID}.US.user_data_connection" \
  --source_format=CSV \
  "gs://${PROJECT_ID}-bucket/user-online-sessions.csv" \
  > /tmp/tabledef.json

if [[ ! -s /tmp/tabledef.json ]]; then
  echo "${RED}The table definition file could not be created.${RESET}"
  exit 1
fi

echo "${GREEN}Table definition created at /tmp/tabledef.json${RESET}"
echo

# ------------------------------------------------------------
# Step 6: Create BigLake table
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[6/10] Creating the BigLake table...${RESET}"

if bq show \
  "${PROJECT_ID}:online_shop.user_online_sessions" >/dev/null 2>&1; then

  echo "${YELLOW}Table user_online_sessions already exists. Recreating it.${RESET}"

  bq rm \
    --force \
    --table \
    "${PROJECT_ID}:online_shop.user_online_sessions"
fi

bq mk \
  --external_table_definition=/tmp/tabledef.json \
  --project_id="$PROJECT_ID" \
  online_shop.user_online_sessions

echo

# ------------------------------------------------------------
# Step 7: Create schema file
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[7/10] Creating the schema for the BigLake table...${RESET}"

cat > /tmp/schema.json <<EOF
[
  {
    "mode": "NULLABLE",
    "name": "ad_event_id",
    "type": "INTEGER"
  },
  {
    "mode": "NULLABLE",
    "name": "user_id",
    "type": "INTEGER"
  },
  {
    "mode": "NULLABLE",
    "name": "uri",
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "traffic_source",
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "zip",
    "policyTags": {
      "names": [
        "${POLICY_TAG}"
      ]
    },
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "event_type",
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "state",
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "country",
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "city",
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "latitude",
    "policyTags": {
      "names": [
        "${POLICY_TAG}"
      ]
    },
    "type": "FLOAT"
  },
  {
    "mode": "NULLABLE",
    "name": "created_at",
    "type": "TIMESTAMP"
  },
  {
    "mode": "NULLABLE",
    "name": "ip_address",
    "policyTags": {
      "names": [
        "${POLICY_TAG}"
      ]
    },
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "session_id",
    "type": "STRING"
  },
  {
    "mode": "NULLABLE",
    "name": "longitude",
    "policyTags": {
      "names": [
        "${POLICY_TAG}"
      ]
    },
    "type": "FLOAT"
  },
  {
    "mode": "NULLABLE",
    "name": "id",
    "type": "INTEGER"
  }
]
EOF

echo "${GREEN}Schema created at /tmp/schema.json${RESET}"
echo

# ------------------------------------------------------------
# Step 8: Update BigLake table schema
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[8/10] Updating the schema for user_online_sessions...${RESET}"

bq update \
  --schema=/tmp/schema.json \
  "${PROJECT_ID}:online_shop.user_online_sessions"

echo

# ------------------------------------------------------------
# Step 9: Query non-sensitive columns
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[9/10] Running a query that excludes sensitive columns...${RESET}"

bq query \
  --project_id="$PROJECT_ID" \
  --use_legacy_sql=false \
  --format=pretty \
  "
  SELECT
    * EXCEPT(zip, latitude, ip_address, longitude)
  FROM
    \`${PROJECT_ID}.online_shop.user_online_sessions\`
  LIMIT 10
  "

echo

# ------------------------------------------------------------
# Step 10: Remove User 2 Storage Object Viewer permission
# ------------------------------------------------------------

echo "${BOLD}${CYAN}[10/10] Removing Storage Object Viewer from User 2...${RESET}"
echo "${YELLOW}User 2: ${USER_2}${RESET}"

if gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/storage.objectViewer AND bindings.members:user:${USER_2}" \
  --format="value(bindings.members)" |
  grep -Fxq "user:${USER_2}"; then

  gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
    --member="user:${USER_2}" \
    --role="roles/storage.objectViewer" \
    --quiet

  echo "${GREEN}Storage Object Viewer was removed from ${USER_2}.${RESET}"
else
  echo "${YELLOW}${USER_2} does not currently have roles/storage.objectViewer.${RESET}"
fi

echo

# ------------------------------------------------------------
# Completion message
# ------------------------------------------------------------

random_congrats() {
  MESSAGES=(
    "${GREEN}Congratulations! The lab configuration has been completed.${RESET}"
    "${CYAN}Well done! All requested resources were configured successfully.${RESET}"
    "${YELLOW}Amazing job! You have successfully completed the lab.${RESET}"
    "${BLUE}Outstanding! The BigLake configuration is complete.${RESET}"
    "${MAGENTA}Great work! Your Google Cloud resources are ready.${RESET}"
    "${GREEN}Mission accomplished! Keep up the great work.${RESET}"
  )

  RANDOM_INDEX=$((RANDOM % ${#MESSAGES[@]}))
  echo "${BOLD}${MESSAGES[$RANDOM_INDEX]}"
}

random_congrats

echo
echo "${BOLD}${CYAN}Summary${RESET}"
echo "Project ID              : ${PROJECT_ID}"
echo "Dataset                 : online_shop"
echo "BigLake table           : user_online_sessions"
echo "Connection              : user_data_connection"
echo "User 2                  : ${USER_2}"
echo "Removed role            : roles/storage.objectViewer"
echo
echo "${BOLD}${GREEN}© ePlus.DEV${RESET}"
echo

# ------------------------------------------------------------
# Cleanup temporary files
# ------------------------------------------------------------

rm -f /tmp/tabledef.json
rm -f /tmp/schema.json

cd "$HOME" || exit 0

remove_files() {
  for file in *; do
    if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
      if [[ -f "$file" ]]; then
        rm -f "$file"
        echo "File removed: $file"
      fi
    fi
  done
}

remove_files