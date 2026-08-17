#!/bin/bash

# ============================================================
# Secure Traffic to a Backend Service with API Gateway
# © ePlus.DEV
# ============================================================

set -uo pipefail

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'

# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------

ok() {
  echo "${GREEN_TEXT}${BOLD_TEXT}✓ $*${RESET_FORMAT}"
}

warn() {
  echo "${YELLOW_TEXT}${BOLD_TEXT}⚠ $*${RESET_FORMAT}"
}

error() {
  echo "${RED_TEXT}${BOLD_TEXT}✗ $*${RESET_FORMAT}"
}

section() {
  echo
  echo "${BLUE_TEXT}${BOLD_TEXT}======================================================================${RESET_FORMAT}"
  echo "${BLUE_TEXT}${BOLD_TEXT}$1${RESET_FORMAT}"
  echo "${BLUE_TEXT}${BOLD_TEXT}======================================================================${RESET_FORMAT}"
}

countdown() {
  local seconds="$1"
  local message="$2"

  while [ "$seconds" -gt 0 ]; do
    printf "\r${YELLOW_TEXT}${BOLD_TEXT}%s %3ds${RESET_FORMAT}" \
      "$message" "$seconds"
    sleep 1
    seconds=$((seconds - 1))
  done

  printf "\r%-100s\r" " "
}

wait_api_config() {
  local CONFIG_ID="$1"
  local API_NAME="$2"
  local STATE=""
  local I

  for I in $(seq 1 90); do

    STATE=$(
      gcloud api-gateway api-configs describe "$CONFIG_ID" \
        --api="$API_NAME" \
        --project="$PROJECT_ID" \
        --format="value(state)" \
        2>/dev/null || true
    )

    printf "\r${YELLOW_TEXT}API Config %-24s state: %-10s [%02d/90]${RESET_FORMAT}" \
      "$CONFIG_ID" "${STATE:-PENDING}" "$I"

    if [ "$STATE" = "ACTIVE" ]; then
      echo
      return 0
    fi

    if [ "$STATE" = "FAILED" ]; then
      echo
      return 1
    fi

    sleep 10
  done

  echo
  return 1
}

wait_gateway() {
  local STATE=""
  local I

  for I in $(seq 1 90); do

    STATE=$(
      gcloud api-gateway gateways describe hello-gateway \
        --location="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(state)" \
        2>/dev/null || true
    )

    printf "\r${YELLOW_TEXT}Gateway hello-gateway state: %-10s [%02d/90]${RESET_FORMAT}" \
      "${STATE:-PENDING}" "$I"

    if [ "$STATE" = "ACTIVE" ]; then
      echo
      return 0
    fi

    if [ "$STATE" = "FAILED" ]; then
      echo
      return 1
    fi

    sleep 10
  done

  echo
  return 1
}

# ============================================================
# HEADER
# ============================================================

clear

echo "${CYAN_TEXT}${BOLD_TEXT}======================================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}          API GATEWAY LAB AUTOMATION - ePlus.DEV                    ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}======================================================================${RESET_FORMAT}"
echo

# ============================================================
# TASK 1
# ============================================================

section "[1/6] Detecting environment and deploying API backend"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  error "Unable to detect Project ID."
  exit 1
fi

PROJECT_NUMBER=$(
  gcloud projects describe "$PROJECT_ID" \
    --format="value(projectNumber)" \
    2>/dev/null || true
)

if [ -z "$PROJECT_NUMBER" ]; then
  error "Unable to detect Project Number."
  exit 1
fi

# Lab requires us-east4.
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
GCF_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcf-admin-robot.iam.gserviceaccount.com"

export PROJECT_ID
export PROJECT_NUMBER
export REGION

echo "Project ID     : $PROJECT_ID"
echo "Project number : $PROJECT_NUMBER"
echo "Region         : $REGION"
echo "Compute SA     : $COMPUTE_SA"

gcloud config set project "$PROJECT_ID" --quiet >/dev/null
gcloud config set compute/region "$REGION" --quiet >/dev/null

# ------------------------------------------------------------
# Enable APIs
# ------------------------------------------------------------

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Enabling required Google Cloud APIs${RESET_FORMAT}"

gcloud services enable \
  apigateway.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  apikeys.googleapis.com \
  iam.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

if [ $? -ne 0 ]; then
  error "Failed to enable required APIs."
  exit 1
fi

countdown 20 "Waiting for API propagation..."

# ------------------------------------------------------------
# Ensure Compute default SA exists
# ------------------------------------------------------------

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Checking Compute Engine default service account${RESET_FORMAT}"

for I in $(seq 1 12); do

  if gcloud iam service-accounts describe "$COMPUTE_SA" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then
    break
  fi

  printf "\rWaiting for Compute default service account... [%02d/12]" "$I"
  sleep 5

done

echo

# ------------------------------------------------------------
# IAM from reference script + build permissions
# ------------------------------------------------------------

echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Preparing IAM permissions${RESET_FORMAT}"

for ROLE in \
  roles/serviceusage.serviceUsageAdmin \
  roles/artifactregistry.reader \
  roles/cloudbuild.builds.builder
do

  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="$ROLE" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true

done

# Restore Cloud Functions service-agent permission if needed.

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GCF_SERVICE_AGENT}" \
  --role="roles/cloudfunctions.serviceAgent" \
  --condition=None \
  --quiet >/dev/null 2>&1 || true

countdown 30 "Waiting for IAM propagation..."

# ------------------------------------------------------------
# Prepare source code
# ------------------------------------------------------------

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Preparing helloGET source code${RESET_FORMAT}"

cd "$HOME" || exit 1

if [ ! -d "$HOME/nodejs-docs-samples" ]; then

  git clone --depth=1 \
    https://github.com/GoogleCloudPlatform/nodejs-docs-samples.git

fi

FUNCTION_DIR="$HOME/nodejs-docs-samples/functions/helloworld/helloworldGet"

if [ ! -d "$FUNCTION_DIR" ]; then
  error "Function source directory not found."
  exit 1
fi

cd "$FUNCTION_DIR" || exit 1

# ------------------------------------------------------------
# Deploy helloGET
# ------------------------------------------------------------

if gcloud functions describe helloGET \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Cloud Function helloGET already exists."

else

  echo
  echo "${YELLOW_TEXT}${BOLD_TEXT}→ Deploying helloGET using Node.js 22${RESET_FORMAT}"

  DEPLOY_OK=false

  # ----------------------------------------------------------
  # First try: current default deployment (Gen 2)
  # ----------------------------------------------------------

  for ATTEMPT in 1 2 3; do

    echo
    echo "Deployment attempt $ATTEMPT/3..."

    if gcloud functions deploy helloGET \
        --runtime=nodejs22 \
        --region="$REGION" \
        --trigger-http \
        --allow-unauthenticated \
        --project="$PROJECT_ID" \
        --quiet
    then

      DEPLOY_OK=true
      break

    fi

    warn "Deployment attempt $ATTEMPT failed."

    if [ "$ATTEMPT" -lt 3 ]; then
      countdown 30 "Waiting before retry..."
    fi

  done

  # ----------------------------------------------------------
  # Fallback for gcf-v2-uploads bucket error
  # ----------------------------------------------------------

  if [ "$DEPLOY_OK" != "true" ]; then

    echo
    warn "Gen 2 deployment is still failing."
    warn "Trying Cloud Functions 1st gen with the same Node.js 22 runtime."

    if gcloud functions deploy helloGET \
        --no-gen2 \
        --runtime=nodejs22 \
        --region="$REGION" \
        --trigger-http \
        --allow-unauthenticated \
        --project="$PROJECT_ID" \
        --quiet
    then

      DEPLOY_OK=true

    fi

  fi

  if [ "$DEPLOY_OK" != "true" ]; then
    error "helloGET deployment failed."
    exit 1
  fi

fi

FUNCTION_URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/helloGET"

echo
echo "Function URL:"
echo "$FUNCTION_URL"

ok "Task 1 backend deployed."

# ============================================================
# TASK 2
# ============================================================

section "[2/6] Testing API backend"

BACKEND_RESPONSE=""

for I in $(seq 1 24); do

  BACKEND_RESPONSE=$(
    curl -fsS \
      "$FUNCTION_URL" \
      2>/dev/null || true
  )

  if [ "$BACKEND_RESPONSE" = "Hello World!" ]; then
    break
  fi

  printf "\rWaiting for backend response... [%02d/24]" "$I"
  sleep 5

done

echo

if [ "$BACKEND_RESPONSE" != "Hello World!" ]; then

  error "Backend test failed."
  echo "Response:"
  echo "$BACKEND_RESPONSE"
  exit 1

fi

ok "Backend response: Hello World!"
ok "Task 2 completed."

# ============================================================
# TASK 3
# ============================================================

section "[3/6] Creating API and Gateway"

cd "$HOME" || exit 1

# ------------------------------------------------------------
# Detect existing API connected to hello-gateway first
# ------------------------------------------------------------

API_ID=""

if gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  EXISTING_CONFIG=$(
    gcloud api-gateway gateways describe hello-gateway \
      --location="$REGION" \
      --project="$PROJECT_ID" \
      --format="value(apiConfig)" \
      2>/dev/null || true
  )

  API_ID=$(
    echo "$EXISTING_CONFIG" |
    sed -n 's#.*apis/\([^/]*\)/configs/.*#\1#p'
  )

fi

# ------------------------------------------------------------
# Find Hello World API if Gateway doesn't already exist
# ------------------------------------------------------------

if [ -z "$API_ID" ]; then

  API_ID=$(
    gcloud api-gateway apis list \
      --project="$PROJECT_ID" \
      --filter='displayName="Hello World API"' \
      --format="value(name)" \
      2>/dev/null |
    head -n1 |
    awk -F/ '{print $NF}'
  )

fi

# ------------------------------------------------------------
# Create API if needed
# ------------------------------------------------------------

if [ -z "$API_ID" ]; then

  API_ID="hello-world-$(tr -dc 'a-z' </dev/urandom | head -c 8)"

  echo "Creating API:"
  echo "$API_ID"

  gcloud api-gateway apis create "$API_ID" \
    --display-name="Hello World API" \
    --project="$PROJECT_ID" \
    --quiet

  if [ $? -ne 0 ]; then
    error "Unable to create API."
    exit 1
  fi

else

  ok "Using API: $API_ID"

fi

export API_ID

# ------------------------------------------------------------
# OpenAPI #1
# ------------------------------------------------------------

cat > "$HOME/openapi2-functions.yaml" <<EOF
swagger: '2.0'

info:
  title: ${API_ID} description
  description: Sample API on API Gateway with a Google Cloud Functions backend
  version: 1.0.0

schemes:
  - https

produces:
  - application/json

paths:
  /hello:
    get:
      summary: Greet a user
      operationId: hello

      x-google-backend:
        address: ${FUNCTION_URL}

      responses:
        '200':
          description: A successful response
          schema:
            type: string
EOF

INITIAL_CONFIG="hello-world-config"

# ------------------------------------------------------------
# Create initial config only if Gateway does not yet exist
# ------------------------------------------------------------

if ! gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  if ! gcloud api-gateway api-configs describe "$INITIAL_CONFIG" \
      --api="$API_ID" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then

    echo
    echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Creating Hello World Config${RESET_FORMAT}"

    gcloud api-gateway api-configs create "$INITIAL_CONFIG" \
      --project="$PROJECT_ID" \
      --api="$API_ID" \
      --openapi-spec="$HOME/openapi2-functions.yaml" \
      --backend-auth-service-account="$COMPUTE_SA" \
      --display-name="Hello World Config" \
      --async \
      --quiet

    if [ $? -ne 0 ]; then
      error "Unable to start initial API config creation."
      exit 1
    fi

  fi

  if ! wait_api_config "$INITIAL_CONFIG" "$API_ID"; then
    error "Initial API config failed."
    exit 1
  fi

  # ----------------------------------------------------------
  # Create Gateway
  # ----------------------------------------------------------

  echo
  echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Creating Hello Gateway${RESET_FORMAT}"

  gcloud api-gateway gateways create hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --api="$API_ID" \
    --api-config="$INITIAL_CONFIG" \
    --display-name="Hello Gateway" \
    --async \
    --quiet

  if [ $? -ne 0 ]; then
    error "Unable to start Gateway creation."
    exit 1
  fi

else

  ok "hello-gateway already exists."

fi

if ! wait_gateway; then
  error "Gateway failed to become ACTIVE."
  exit 1
fi

GATEWAY_URL=$(
  gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(defaultHostname)"
)

if [ -z "$GATEWAY_URL" ]; then
  error "Gateway hostname could not be determined."
  exit 1
fi

echo
echo "Gateway URL:"
echo "https://${GATEWAY_URL}"

# Initial test.
INITIAL_RESPONSE=$(
  curl -fsS \
    "https://${GATEWAY_URL}/hello" \
    2>/dev/null || true
)

if [ "$INITIAL_RESPONSE" = "Hello World!" ]; then

  ok "Initial Gateway test: Hello World!"

else

  warn "Initial request is already protected."
  warn "This is OK if the script was previously partially completed."

fi

ok "Task 3 completed."

# ============================================================
# TASK 4
# ============================================================

section "[4/6] Creating and restricting API key"

# ------------------------------------------------------------
# Get exact Managed Service for THIS API
# ------------------------------------------------------------

MANAGED_SERVICE=$(
  gcloud api-gateway apis describe "$API_ID" \
    --project="$PROJECT_ID" \
    --format="value(managedService)" \
    2>/dev/null || true
)

if [ -z "$MANAGED_SERVICE" ]; then
  error "Unable to determine Managed Service for $API_ID."
  exit 1
fi

echo "Managed Service : $MANAGED_SERVICE"

# ------------------------------------------------------------
# Enable Managed Service BEFORE creating/restricting key
# ------------------------------------------------------------

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Enabling Managed Service${RESET_FORMAT}"

SERVICE_ENABLED=false

for I in $(seq 1 24); do

  if gcloud services enable "$MANAGED_SERVICE" \
      --project="$PROJECT_ID" \
      --quiet >/dev/null 2>&1; then

    SERVICE_ENABLED=true
    break

  fi

  printf "\rManaged Service is propagating... [%02d/24]" "$I"
  sleep 10

done

echo

if [ "$SERVICE_ENABLED" != "true" ]; then
  error "Unable to enable Managed Service."
  exit 1
fi

ok "Managed Service enabled."

countdown 15 "Waiting for Service Management propagation..."

# ------------------------------------------------------------
# Find API key from a previous run
# ------------------------------------------------------------

KEY_NAME=$(
  gcloud services api-keys list \
    --project="$PROJECT_ID" \
    --filter='displayName="awesome"' \
    --format="value(name)" \
    2>/dev/null |
  head -n1
)

if [ -z "$KEY_NAME" ]; then

  echo
  echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Creating restricted API key${RESET_FORMAT}"

  gcloud services api-keys create \
    --display-name="awesome" \
    --api-target="service=${MANAGED_SERVICE}" \
    --project="$PROJECT_ID" \
    --quiet

  if [ $? -ne 0 ]; then
    error "API key creation failed."
    exit 1
  fi

  # Wait for new key resource to appear.

  for I in $(seq 1 24); do

    KEY_NAME=$(
      gcloud services api-keys list \
        --project="$PROJECT_ID" \
        --filter='displayName="awesome"' \
        --format="value(name)" \
        2>/dev/null |
      head -n1
    )

    if [ -n "$KEY_NAME" ]; then
      break
    fi

    printf "\rWaiting for API key resource... [%02d/24]" "$I"
    sleep 5

  done

  echo

else

  echo
  warn "API key 'awesome' already exists."
  echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Fixing API restriction on existing key${RESET_FORMAT}"

  # IMPORTANT:
  # This repairs API keys created by the old script without restrictions.

  gcloud services api-keys update "$KEY_NAME" \
    --api-target="service=${MANAGED_SERVICE}" \
    --project="$PROJECT_ID" \
    --quiet

  if [ $? -ne 0 ]; then
    error "Unable to apply API restriction to existing API key."
    exit 1
  fi

fi

if [ -z "$KEY_NAME" ]; then
  error "API key resource not found."
  exit 1
fi

# ------------------------------------------------------------
# Retrieve API key value
# ------------------------------------------------------------

API_KEY=""

for I in $(seq 1 24); do

  API_KEY=$(
    gcloud services api-keys get-key-string "$KEY_NAME" \
      --project="$PROJECT_ID" \
      --format="value(keyString)" \
      2>/dev/null || true
  )

  if [ -n "$API_KEY" ]; then
    break
  fi

  printf "\rWaiting for API key value... [%02d/24]" "$I"
  sleep 5

done

echo

if [ -z "$API_KEY" ]; then
  error "Unable to retrieve API key value."
  exit 1
fi

export API_KEY

ok "API key created."
ok "API key restricted to:"
echo "  $MANAGED_SERVICE"

ok "Task 4 completed."

# ============================================================
# TASK 5
# ============================================================

section "[5/6] Creating secured API config"

# ------------------------------------------------------------
# Find Qwiklabs User Service Account
# ------------------------------------------------------------

QWIKLABS_SA=$(
  gcloud iam service-accounts list \
    --project="$PROJECT_ID" \
    --filter='displayName="Qwiklabs User Service Account"' \
    --format="value(email)" \
    2>/dev/null |
  head -n1
)

# Reference labs often use:
# PROJECT_ID@PROJECT_ID.iam.gserviceaccount.com

if [ -z "$QWIKLABS_SA" ]; then

  POSSIBLE_QWIKLABS_SA="${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

  if gcloud iam service-accounts describe "$POSSIBLE_QWIKLABS_SA" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then

    QWIKLABS_SA="$POSSIBLE_QWIKLABS_SA"

  fi

fi

# Try any SA with Qwiklabs in its display name.

if [ -z "$QWIKLABS_SA" ]; then

  QWIKLABS_SA=$(
    gcloud iam service-accounts list \
      --project="$PROJECT_ID" \
      --filter='displayName:Qwiklabs' \
      --format="value(email)" \
      2>/dev/null |
    head -n1
  )

fi

if [ -z "$QWIKLABS_SA" ]; then

  warn "Qwiklabs User Service Account was not found."
  warn "Falling back to Compute Engine default service account."

  QWIKLABS_SA="$COMPUTE_SA"

fi

echo "Backend SA      : $QWIKLABS_SA"

# ------------------------------------------------------------
# Give backend SA permission to invoke function.
# Best effort because some Qwiklabs IAM policies are restricted.
# ------------------------------------------------------------

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Preparing backend service account permissions${RESET_FORMAT}"

for ROLE in \
  roles/cloudfunctions.invoker \
  roles/run.invoker \
  roles/serviceusage.serviceUsageAdmin
do

  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${QWIKLABS_SA}" \
    --role="$ROLE" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true

done

# ------------------------------------------------------------
# Secured OpenAPI
# ------------------------------------------------------------

cat > "$HOME/openapi2-functions2.yaml" <<EOF
swagger: '2.0'

info:
  title: ${API_ID} description
  description: Sample API on API Gateway with a Google Cloud Functions backend
  version: 1.0.0

schemes:
  - https

produces:
  - application/json

paths:
  /hello:
    get:
      summary: Greet a user
      operationId: hello

      x-google-backend:
        address: ${FUNCTION_URL}

      security:
        - api_key: []

      responses:
        '200':
          description: A successful response
          schema:
            type: string

securityDefinitions:
  api_key:
    type: "apiKey"
    name: "key"
    in: "query"
EOF

# ------------------------------------------------------------
# Configs are immutable.
#
# First run       => hello-config
# Rerun/old config => hello-config-HHMMSS
#
# Display name remains exactly "Hello Config".
# ------------------------------------------------------------

SEC_CONFIG_ID="hello-config"

if gcloud api-gateway api-configs describe "$SEC_CONFIG_ID" \
    --api="$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  CURRENT_GATEWAY_CONFIG=$(
    gcloud api-gateway gateways describe hello-gateway \
      --location="$REGION" \
      --project="$PROJECT_ID" \
      --format="value(apiConfig)" \
      2>/dev/null || true
  )

  if [[ "$CURRENT_GATEWAY_CONFIG" == *"/configs/${SEC_CONFIG_ID}" ]]; then

    # An existing hello-config may have been created by the old/broken
    # script. Create a fresh config to guarantee the security spec.

    SEC_CONFIG_ID="hello-config-$(date +%H%M%S)"

  else

    SEC_CONFIG_ID="hello-config-$(date +%H%M%S)"

  fi

fi

echo
echo "Secured Config  : $SEC_CONFIG_ID"

# ------------------------------------------------------------
# Only one API config may be creating at a time.
# ------------------------------------------------------------

echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Waiting for any existing config operation${RESET_FORMAT}"

for I in $(seq 1 30); do

  CREATING_COUNT=$(
    gcloud api-gateway api-configs list \
      --api="$API_ID" \
      --project="$PROJECT_ID" \
      --filter='state!=ACTIVE' \
      --format='value(state)' \
      2>/dev/null |
    grep -c . || true
  )

  if [ "${CREATING_COUNT:-0}" -eq 0 ]; then
    break
  fi

  printf "\rWaiting for previous config operation... [%02d/30]" "$I"
  sleep 10

done

echo

# ------------------------------------------------------------
# Create secured config
# ------------------------------------------------------------

echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Creating Hello Config${RESET_FORMAT}"

gcloud api-gateway api-configs create "$SEC_CONFIG_ID" \
  --project="$PROJECT_ID" \
  --display-name="Hello Config" \
  --api="$API_ID" \
  --openapi-spec="$HOME/openapi2-functions2.yaml" \
  --backend-auth-service-account="$QWIKLABS_SA" \
  --async \
  --quiet

if [ $? -ne 0 ]; then
  error "Unable to start secured API config creation."
  exit 1
fi

if ! wait_api_config "$SEC_CONFIG_ID" "$API_ID"; then
  error "Secured API config failed."
  exit 1
fi

ok "Secured API config is ACTIVE."

# ------------------------------------------------------------
# Update Gateway
# ------------------------------------------------------------

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}→ Updating hello-gateway to secured config${RESET_FORMAT}"

gcloud api-gateway gateways update hello-gateway \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --api="$API_ID" \
  --api-config="$SEC_CONFIG_ID" \
  --async \
  --quiet

if [ $? -ne 0 ]; then
  error "Unable to start Gateway update."
  exit 1
fi

if ! wait_gateway; then
  error "Gateway update failed."
  exit 1
fi

# Confirm Gateway is actually pointing to secured config.

CURRENT_GATEWAY_CONFIG=$(
  gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(apiConfig)" \
    2>/dev/null || true
)

echo
echo "Gateway config:"
echo "$CURRENT_GATEWAY_CONFIG"

if [[ "$CURRENT_GATEWAY_CONFIG" != *"/configs/${SEC_CONFIG_ID}" ]]; then
  error "Gateway is not using the secured API config."
  exit 1
fi

# Re-enable managed service after config deployment.

gcloud services enable "$MANAGED_SERVICE" \
  --project="$PROJECT_ID" \
  --quiet >/dev/null 2>&1 || true

ok "Task 5 completed."

# ============================================================
# TASK 6
# ============================================================

section "[6/6] Testing API key security"

GATEWAY_URL=$(
  gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(defaultHostname)"
)

if [ -z "$GATEWAY_URL" ]; then
  error "Gateway URL not found."
  exit 1
fi

echo "Gateway URL:"
echo "https://${GATEWAY_URL}"

echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Waiting for secured config and API-key propagation...${RESET_FORMAT}"

FINAL_OK=false
LAST_NO_KEY_CODE=""
LAST_NO_KEY_RESPONSE=""
LAST_KEY_CODE=""
LAST_KEY_RESPONSE=""

# ------------------------------------------------------------
# We require BOTH conditions:
#
# 1. Request WITHOUT key must be rejected.
# 2. Request WITH valid key must return Hello World!
#
# This avoids falsely marking Task 6 complete while the old
# unprotected config is still being served.
# ------------------------------------------------------------

for I in $(seq 1 36); do

  LAST_NO_KEY_CODE=$(
    curl -sS \
      -o /tmp/no-key-response.txt \
      -w "%{http_code}" \
      "https://${GATEWAY_URL}/hello" \
      2>/dev/null || true
  )

  LAST_NO_KEY_RESPONSE=$(
    cat /tmp/no-key-response.txt 2>/dev/null || true
  )

  LAST_KEY_CODE=$(
    curl -sS \
      -o /tmp/key-response.txt \
      -w "%{http_code}" \
      "https://${GATEWAY_URL}/hello?key=${API_KEY}" \
      2>/dev/null || true
  )

  LAST_KEY_RESPONSE=$(
    cat /tmp/key-response.txt 2>/dev/null || true
  )

  printf "\rAttempt %02d/36 | no-key HTTP %-3s | with-key HTTP %-3s" \
    "$I" \
    "${LAST_NO_KEY_CODE:----}" \
    "${LAST_KEY_CODE:----}"

  # Without key must NOT get Hello World!
  # With key must get HTTP 200 + Hello World!

  if [ "$LAST_NO_KEY_RESPONSE" != "Hello World!" ] &&
     [ "$LAST_KEY_CODE" = "200" ] &&
     [ "$LAST_KEY_RESPONSE" = "Hello World!" ]; then

    FINAL_OK=true
    break

  fi

  sleep 10

done

echo
echo

echo "${CYAN_TEXT}${BOLD_TEXT}Test WITHOUT API key:${RESET_FORMAT}"
echo "HTTP ${LAST_NO_KEY_CODE:-unknown}"

if [ -n "$LAST_NO_KEY_RESPONSE" ]; then
  echo "$LAST_NO_KEY_RESPONSE"
fi

echo
echo "${CYAN_TEXT}${BOLD_TEXT}Test WITH API key:${RESET_FORMAT}"
echo "HTTP ${LAST_KEY_CODE:-unknown}"

if [ -n "$LAST_KEY_RESPONSE" ]; then
  echo "$LAST_KEY_RESPONSE"
fi

echo

if [ "$FINAL_OK" != "true" ]; then

  error "Task 6 verification failed."

  echo
  echo "Expected:"
  echo "  WITHOUT key -> rejected / UNAUTHENTICATED"
  echo "  WITH key    -> HTTP 200 + Hello World!"
  echo

  exit 1

fi

ok "Request without API key is rejected."
ok "Request with API key returns Hello World!"
ok "Task 6 completed."

# ============================================================
# FINAL VALIDATION
# ============================================================

section "FINAL RESOURCE VALIDATION"

echo "Project ID      : $PROJECT_ID"
echo "Project Number  : $PROJECT_NUMBER"
echo "Region          : $REGION"
echo "Function        : helloGET"
echo "API ID          : $API_ID"
echo "Gateway ID      : hello-gateway"
echo "Gateway URL     : https://${GATEWAY_URL}"
echo "Managed Service : $MANAGED_SERVICE"
echo "Secured Config  : $SEC_CONFIG_ID"
echo "Backend SA      : $QWIKLABS_SA"
echo "API Key         : ${API_KEY:0:8}...${API_KEY: -4}"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}======================================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}                       LAB COMPLETED                                ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}======================================================================${RESET_FORMAT}"
echo

echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 1 - Deploying an API Backend${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 2 - Test the API Backend${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 3 - Creating a Gateway${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 4 - Securing Access by Using an API Key${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 5 - Create and deploy a new API config${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 6 - Testing Calls Using Your API Key${RESET_FORMAT}"

echo
echo "${CYAN_TEXT}${BOLD_TEXT}Click Check my progress for Tasks 1 → 6.${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}© ePlus.DEV${RESET_FORMAT}"
echo