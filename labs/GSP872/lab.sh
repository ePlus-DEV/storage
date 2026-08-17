#!/bin/bash

# ============================================================
# Secure Traffic to a Backend Service with API Gateway
# © ePlus.DEV
# ============================================================

set -uo pipefail

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

# ============================================================
# HELPERS
# ============================================================

ok() {
  echo "${GREEN_TEXT}${BOLD_TEXT}✓ $*${RESET_FORMAT}"
}

warn() {
  echo "${YELLOW_TEXT}${BOLD_TEXT}⚠ $*${RESET_FORMAT}"
}

fail() {
  echo "${RED_TEXT}${BOLD_TEXT}✗ $*${RESET_FORMAT}"
  exit 1
}

section() {
  echo
  echo "${BLUE_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
  echo "${BLUE_TEXT}${BOLD_TEXT}$1${RESET_FORMAT}"
  echo "${BLUE_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
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

  printf "\r%-90s\r" " "
}

wait_api_config() {
  local CONFIG_ID="$1"
  local API_ID_ARG="$2"
  local STATE=""
  local I

  for I in $(seq 1 90); do

    STATE=$(
      gcloud api-gateway api-configs describe "$CONFIG_ID" \
        --api="$API_ID_ARG" \
        --project="$PROJECT_ID" \
        --format="value(state)" \
        2>/dev/null || true
    )

    printf "\r${YELLOW_TEXT}API Config %-22s : %-10s [%02d/90]${RESET_FORMAT}" \
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

    printf "\r${YELLOW_TEXT}Gateway hello-gateway : %-10s [%02d/90]${RESET_FORMAT}" \
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
# START
# ============================================================

clear

echo "${BLUE_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}         INITIATING EXECUTION - ePlus.DEV             ${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo

# ============================================================
# TASK 1
# ============================================================

section "[1/6] Deploying an API Backend"

echo "${CYAN_TEXT}${BOLD_TEXT}Detecting Qwiklabs environment...${RESET_FORMAT}"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  fail "Unable to detect Project ID."
fi

PROJECT_NUMBER=$(
  gcloud projects describe "$PROJECT_ID" \
    --format="value(projectNumber)" \
    2>/dev/null || true
)

if [ -z "$PROJECT_NUMBER" ]; then
  fail "Unable to detect Project Number."
fi

# ------------------------------------------------------------
# Detect the region assigned by Qwiklabs.
#
# IMPORTANT:
# Do not hard-code us-east4.
# The current project can enforce gcp.resourceLocations.
# ------------------------------------------------------------

REGION=$(
  gcloud compute project-info describe \
    --project="$PROJECT_ID" \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
    2>/dev/null || true
)

# Try deriving region from default zone.

if [ -z "$REGION" ]; then

  DEFAULT_ZONE=$(
    gcloud compute project-info describe \
      --project="$PROJECT_ID" \
      --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
      2>/dev/null || true
  )

  if [ -n "$DEFAULT_ZONE" ]; then
    REGION="${DEFAULT_ZONE%-*}"
  fi

fi

# Final fallback: gcloud configuration.

if [ -z "$REGION" ]; then
  REGION=$(gcloud config get-value compute/region 2>/dev/null || true)
fi

if [ -z "$REGION" ] || [ "$REGION" = "(unset)" ]; then
  fail "Unable to detect the Qwiklabs region."
fi

export PROJECT_ID
export PROJECT_NUMBER
export REGION

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo
echo "Project ID     : $PROJECT_ID"
echo "Project number : $PROJECT_NUMBER"
echo "Region         : $REGION"
echo "Compute SA     : $COMPUTE_SA"
echo

gcloud config set project "$PROJECT_ID" \
  --quiet >/dev/null

gcloud config set compute/region "$REGION" \
  --quiet >/dev/null

# ------------------------------------------------------------
# Enable APIs
# ------------------------------------------------------------

echo "${MAGENTA_TEXT}${BOLD_TEXT}Enabling required Google Cloud services...${RESET_FORMAT}"

gcloud services enable \
  apigateway.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  apikeys.googleapis.com \
  iam.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet || fail "Unable to enable required APIs."

countdown 20 "Waiting for API propagation..."

# ------------------------------------------------------------
# IAM
# ------------------------------------------------------------

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Adding required IAM bindings...${RESET_FORMAT}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/serviceusage.serviceUsageAdmin" \
  --condition=None \
  --quiet >/dev/null 2>&1 || true

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/artifactregistry.reader" \
  --condition=None \
  --quiet >/dev/null 2>&1 || true

countdown 30 "Waiting for IAM propagation..."

# ------------------------------------------------------------
# Clone repository
# ------------------------------------------------------------

echo
echo "${BLUE_TEXT}${BOLD_TEXT}Preparing Node.js sample repository...${RESET_FORMAT}"

cd "$HOME" || exit 1

if [ ! -d "$HOME/nodejs-docs-samples" ]; then

  git clone --depth=1 \
    https://github.com/GoogleCloudPlatform/nodejs-docs-samples.git \
    || fail "Unable to clone nodejs-docs-samples."

else

  ok "nodejs-docs-samples already exists."

fi

FUNCTION_DIR="$HOME/nodejs-docs-samples/functions/helloworld/helloworldGet"

[ -d "$FUNCTION_DIR" ] || fail "helloworldGet source directory not found."

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
  echo "${YELLOW_TEXT}${BOLD_TEXT}Deploying helloGET...${RESET_FORMAT}"

  DEPLOY_SUCCESS=false

  for ATTEMPT in $(seq 1 12); do

    echo
    echo "Deployment attempt $ATTEMPT/12..."

    if gcloud functions deploy helloGET \
        --runtime=nodejs22 \
        --region="$REGION" \
        --trigger-http \
        --allow-unauthenticated \
        --project="$PROJECT_ID" \
        --quiet \
        2>&1 | tee /tmp/helloGET-deploy.log
    then

      DEPLOY_SUCCESS=true
      break
    fi

    # No point retrying a region explicitly rejected by Org Policy.

    if grep -q "constraints/gcp.resourceLocations" \
        /tmp/helloGET-deploy.log 2>/dev/null; then

      echo
      fail "Region $REGION is blocked by the project's resource location policy."

    fi

    warn "Deployment attempt $ATTEMPT failed."

    if [ "$ATTEMPT" -lt 12 ]; then
      countdown 45 "Waiting before retry..."
    fi

  done

  [ "$DEPLOY_SUCCESS" = "true" ] || fail "helloGET deployment failed."

fi

# ------------------------------------------------------------
# Detect actual function URL
# ------------------------------------------------------------

FUNCTION_URL=$(
  gcloud functions describe helloGET \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(serviceConfig.uri)" \
    2>/dev/null || true
)

if [ -z "$FUNCTION_URL" ]; then

  FUNCTION_URL=$(
    gcloud functions describe helloGET \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format="value(httpsTrigger.url)" \
      2>/dev/null || true
  )

fi

[ -n "$FUNCTION_URL" ] || fail "Unable to determine helloGET URL."

echo
echo "Function URL:"
echo "$FUNCTION_URL"

ok "TASK 1 completed."

# ============================================================
# TASK 2
# ============================================================

section "[2/6] Testing the API Backend"

BACKEND_RESPONSE=""

for I in $(seq 1 24); do

  BACKEND_RESPONSE=$(
    curl -fsSL "$FUNCTION_URL" \
      2>/dev/null || true
  )

  if [ "$BACKEND_RESPONSE" = "Hello World!" ]; then
    break
  fi

  printf "\rWaiting for backend... [%02d/24]" "$I"
  sleep 5

done

echo

if [ "$BACKEND_RESPONSE" != "Hello World!" ]; then

  echo "Response:"
  echo "$BACKEND_RESPONSE"

  fail "Backend did not return Hello World!"

fi

ok "Backend returned: Hello World!"
ok "TASK 2 completed."

# ============================================================
# TASK 3
# ============================================================

section "[3/6] Creating a Gateway"

cd "$HOME" || exit 1

# ------------------------------------------------------------
# Detect API from existing gateway if script is re-run.
# ------------------------------------------------------------

API_ID=""

if gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  EXISTING_API_CONFIG=$(
    gcloud api-gateway gateways describe hello-gateway \
      --location="$REGION" \
      --project="$PROJECT_ID" \
      --format="value(apiConfig)" \
      2>/dev/null || true
  )

  API_ID=$(
    echo "$EXISTING_API_CONFIG" \
      | sed -n 's#.*apis/\([^/]*\)/configs/.*#\1#p'
  )

fi

# ------------------------------------------------------------
# Otherwise find previous Hello World API.
# ------------------------------------------------------------

if [ -z "$API_ID" ]; then

  API_ID=$(
    gcloud api-gateway apis list \
      --project="$PROJECT_ID" \
      --filter='displayName="Hello World API"' \
      --sort-by='~createTime' \
      --limit=1 \
      --format="value(name)" \
      2>/dev/null \
      | awk -F/ '{print $NF}'
  )

fi

# ------------------------------------------------------------
# Create ONE API_ID.
#
# Fixes the old script bug that generated API_ID twice.
# ------------------------------------------------------------

if [ -z "$API_ID" ]; then

  API_ID="hello-world-$(tr -dc 'a-z' </dev/urandom | head -c 8)"

  echo "${CYAN_TEXT}${BOLD_TEXT}Creating API: $API_ID${RESET_FORMAT}"

  gcloud api-gateway apis create "$API_ID" \
    --display-name="Hello World API" \
    --project="$PROJECT_ID" \
    --quiet \
    || fail "Unable to create API."

else

  ok "Using API: $API_ID"

fi

export API_ID

# ------------------------------------------------------------
# OpenAPI #1
#
# Fixes old hard-coded project:
# us-east4-qwiklabs-gcp-01-b47a65687b9f
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
# Create Gateway only when absent.
# ------------------------------------------------------------

if ! gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  if ! gcloud api-gateway api-configs describe "$INITIAL_CONFIG" \
      --api="$API_ID" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then

    echo
    echo "${MAGENTA_TEXT}${BOLD_TEXT}Creating Hello World Config...${RESET_FORMAT}"

    gcloud api-gateway api-configs create "$INITIAL_CONFIG" \
      --project="$PROJECT_ID" \
      --api="$API_ID" \
      --openapi-spec="$HOME/openapi2-functions.yaml" \
      --backend-auth-service-account="$COMPUTE_SA" \
      --display-name="Hello World Config" \
      --async \
      --quiet \
      || fail "Unable to start API config creation."

  fi

  wait_api_config "$INITIAL_CONFIG" "$API_ID" \
    || fail "Hello World Config failed."

  echo
  echo "${MAGENTA_TEXT}${BOLD_TEXT}Creating Hello Gateway...${RESET_FORMAT}"

  gcloud api-gateway gateways create hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --api="$API_ID" \
    --api-config="$INITIAL_CONFIG" \
    --display-name="Hello Gateway" \
    --async \
    --quiet \
    || fail "Unable to start Gateway creation."

else

  ok "hello-gateway already exists."

fi

wait_gateway || fail "Gateway did not become ACTIVE."

GATEWAY_URL=$(
  gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(defaultHostname)" \
    2>/dev/null || true
)

[ -n "$GATEWAY_URL" ] || fail "Unable to determine Gateway URL."

echo
echo "Gateway URL:"
echo "https://${GATEWAY_URL}"

INITIAL_GATEWAY_RESPONSE=$(
  curl -fsSL \
    "https://${GATEWAY_URL}/hello" \
    2>/dev/null || true
)

if [ "$INITIAL_GATEWAY_RESPONSE" = "Hello World!" ]; then

  ok "Gateway returned Hello World!"

else

  warn "Gateway may already use a secured config from an earlier run."

fi

ok "TASK 3 completed."

# ============================================================
# TASK 4
# ============================================================

section "[4/6] Securing Access by Using an API Key"

# ------------------------------------------------------------
# Exact Managed Service for THIS API.
# ------------------------------------------------------------

MANAGED_SERVICE=$(
  gcloud api-gateway apis describe "$API_ID" \
    --project="$PROJECT_ID" \
    --format="value(managedService)" \
    2>/dev/null || true
)

[ -n "$MANAGED_SERVICE" ] \
  || fail "Unable to determine Managed Service."

echo "Managed Service:"
echo "$MANAGED_SERVICE"

# ------------------------------------------------------------
# IMPORTANT FIX:
#
# Old script:
#   1. Created unrestricted key
#   2. Then enabled Managed Service
#
# Correct flow:
#   1. Enable Managed Service
#   2. Create/update key restricted to that service
# ------------------------------------------------------------

echo
echo "${CYAN_TEXT}${BOLD_TEXT}Enabling Managed Service...${RESET_FORMAT}"

SERVICE_READY=false

for I in $(seq 1 30); do

  if gcloud services enable "$MANAGED_SERVICE" \
      --project="$PROJECT_ID" \
      --quiet >/dev/null 2>&1; then

    SERVICE_READY=true
    break

  fi

  printf "\rWaiting for Managed Service... [%02d/30]" "$I"
  sleep 10

done

echo

[ "$SERVICE_READY" = "true" ] \
  || fail "Unable to enable Managed Service."

ok "Managed Service enabled."

countdown 20 "Waiting for Service Management propagation..."

# ------------------------------------------------------------
# Find existing awesome key.
# ------------------------------------------------------------

KEY_NAME=$(
  gcloud services api-keys list \
    --project="$PROJECT_ID" \
    --filter='displayName="awesome"' \
    --format="value(name)" \
    2>/dev/null \
    | head -n1
)

if [ -z "$KEY_NAME" ]; then

  echo
  echo "${GREEN_TEXT}${BOLD_TEXT}Creating restricted API key...${RESET_FORMAT}"

  gcloud services api-keys create \
    --display-name="awesome" \
    --api-target="service=${MANAGED_SERVICE}" \
    --project="$PROJECT_ID" \
    --quiet \
    || fail "Unable to create API key."

  # Wait until API key resource appears.

  for I in $(seq 1 24); do

    KEY_NAME=$(
      gcloud services api-keys list \
        --project="$PROJECT_ID" \
        --filter='displayName="awesome"' \
        --format="value(name)" \
        2>/dev/null \
        | head -n1
    )

    [ -n "$KEY_NAME" ] && break

    printf "\rWaiting for API key resource... [%02d/24]" "$I"
    sleep 5

  done

  echo

else

  warn "API key 'awesome' already exists."
  echo "${GREEN_TEXT}${BOLD_TEXT}Fixing API restriction on existing key...${RESET_FORMAT}"

  gcloud services api-keys update "$KEY_NAME" \
    --api-target="service=${MANAGED_SERVICE}" \
    --project="$PROJECT_ID" \
    --quiet \
    || fail "Unable to update API key restriction."

fi

[ -n "$KEY_NAME" ] || fail "API key resource was not found."

# ------------------------------------------------------------
# Read key value.
# ------------------------------------------------------------

API_KEY=""

for I in $(seq 1 24); do

  API_KEY=$(
    gcloud services api-keys get-key-string "$KEY_NAME" \
      --project="$PROJECT_ID" \
      --format="value(keyString)" \
      2>/dev/null || true
  )

  [ -n "$API_KEY" ] && break

  printf "\rWaiting for API key value... [%02d/24]" "$I"
  sleep 5

done

echo

[ -n "$API_KEY" ] || fail "Unable to retrieve API key value."

export API_KEY

ok "API key created/repaired."
ok "Restriction: $MANAGED_SERVICE"
ok "TASK 4 completed."

# ============================================================
# TASK 5
# ============================================================

section "[5/6] Creating and Deploying a New API Config"

# ------------------------------------------------------------
# Find the Qwiklabs User Service Account requested by lab.
# ------------------------------------------------------------

QWIKLABS_SA=$(
  gcloud iam service-accounts list \
    --project="$PROJECT_ID" \
    --filter='displayName="Qwiklabs User Service Account"' \
    --format="value(email)" \
    2>/dev/null \
    | head -n1
)

# The reference script uses this address.
# Use it only if it actually exists.

if [ -z "$QWIKLABS_SA" ]; then

  OLD_STYLE_SA="${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

  if gcloud iam service-accounts describe "$OLD_STYLE_SA" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then

    QWIKLABS_SA="$OLD_STYLE_SA"

  fi

fi

# Wider fallback search.

if [ -z "$QWIKLABS_SA" ]; then

  QWIKLABS_SA=$(
    gcloud iam service-accounts list \
      --project="$PROJECT_ID" \
      --filter='displayName:Qwiklabs' \
      --format="value(email)" \
      2>/dev/null \
      | head -n1
  )

fi

# Last resort.

if [ -z "$QWIKLABS_SA" ]; then

  warn "Qwiklabs User Service Account was not found."
  warn "Using Compute Engine default service account."

  QWIKLABS_SA="$COMPUTE_SA"

fi

echo "Backend Service Account:"
echo "$QWIKLABS_SA"

# Match useful IAM from the reference solution.

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${QWIKLABS_SA}" \
  --role="roles/serviceusage.serviceUsageAdmin" \
  --condition=None \
  --quiet >/dev/null 2>&1 || true

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/serviceusage.serviceUsageAdmin" \
  --condition=None \
  --quiet >/dev/null 2>&1 || true

# ------------------------------------------------------------
# New secured OpenAPI definition.
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
# API configs are immutable.
#
# Use hello-config first.
# If an old/broken hello-config exists, make a fresh config
# while keeping Display Name = "Hello Config".
# ------------------------------------------------------------

SEC_CONFIG_ID="hello-config"

if gcloud api-gateway api-configs describe "$SEC_CONFIG_ID" \
    --api="$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  SEC_CONFIG_ID="hello-config-$(date +%H%M%S)"

fi

echo
echo "New Config ID:"
echo "$SEC_CONFIG_ID"

# ------------------------------------------------------------
# Wait until no previous API config operation is running.
# ------------------------------------------------------------

for I in $(seq 1 36); do

  NON_ACTIVE=$(
    gcloud api-gateway api-configs list \
      --api="$API_ID" \
      --project="$PROJECT_ID" \
      --format="value(state)" \
      2>/dev/null \
      | grep -Ev '^(ACTIVE)?$' \
      | wc -l
  )

  if [ "${NON_ACTIVE:-0}" -eq 0 ]; then
    break
  fi

  printf "\rWaiting for previous API config operation... [%02d/36]" "$I"
  sleep 10

done

echo

echo "${MAGENTA_TEXT}${BOLD_TEXT}Creating secured Hello Config...${RESET_FORMAT}"

gcloud api-gateway api-configs create "$SEC_CONFIG_ID" \
  --project="$PROJECT_ID" \
  --display-name="Hello Config" \
  --api="$API_ID" \
  --openapi-spec="$HOME/openapi2-functions2.yaml" \
  --backend-auth-service-account="$QWIKLABS_SA" \
  --async \
  --quiet \
  || fail "Unable to start secured API config creation."

wait_api_config "$SEC_CONFIG_ID" "$API_ID" \
  || fail "Secured API config failed."

ok "Secured API config is ACTIVE."

# ------------------------------------------------------------
# Update Gateway.
# ------------------------------------------------------------

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}Updating hello-gateway...${RESET_FORMAT}"

gcloud api-gateway gateways update hello-gateway \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --api="$API_ID" \
  --api-config="$SEC_CONFIG_ID" \
  --async \
  --quiet \
  || fail "Unable to start Gateway update."

wait_gateway || fail "Gateway update failed."

# Confirm exact config is attached.

CURRENT_GATEWAY_CONFIG=$(
  gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(apiConfig)" \
    2>/dev/null || true
)

echo
echo "Current Gateway config:"
echo "$CURRENT_GATEWAY_CONFIG"

if [[ "$CURRENT_GATEWAY_CONFIG" != *"/configs/${SEC_CONFIG_ID}" ]]; then
  fail "Gateway is not using the new secured config."
fi

# Keep Managed Service enabled after deploying new service config.

gcloud services enable "$MANAGED_SERVICE" \
  --project="$PROJECT_ID" \
  --quiet >/dev/null 2>&1 || true

countdown 20 "Waiting for secured Gateway propagation..."

ok "TASK 5 completed."

# ============================================================
# TASK 6
# ============================================================

section "[6/6] Testing Calls Using the API Key"

GATEWAY_URL=$(
  gcloud api-gateway gateways describe hello-gateway \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(defaultHostname)" \
    2>/dev/null || true
)

[ -n "$GATEWAY_URL" ] || fail "Unable to determine Gateway URL."

echo "Gateway URL:"
echo "https://${GATEWAY_URL}"

echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Waiting for API key/security propagation...${RESET_FORMAT}"
echo

FINAL_SUCCESS=false

NO_KEY_CODE=""
NO_KEY_BODY=""

WITH_KEY_CODE=""
WITH_KEY_BODY=""

# ------------------------------------------------------------
# Task 6 only succeeds when BOTH are true:
#
# WITHOUT API key:
#   must be rejected
#
# WITH API key:
#   HTTP 200 + Hello World!
# ------------------------------------------------------------

for I in $(seq 1 42); do

  # WITHOUT KEY

  NO_KEY_CODE=$(
    curl -sS \
      -o /tmp/no-key-response.txt \
      -w "%{http_code}" \
      "https://${GATEWAY_URL}/hello" \
      2>/dev/null || true
  )

  NO_KEY_BODY=$(
    cat /tmp/no-key-response.txt \
      2>/dev/null || true
  )

  # WITH KEY

  WITH_KEY_CODE=$(
    curl -sS \
      -o /tmp/with-key-response.txt \
      -w "%{http_code}" \
      "https://${GATEWAY_URL}/hello?key=${API_KEY}" \
      2>/dev/null || true
  )

  WITH_KEY_BODY=$(
    cat /tmp/with-key-response.txt \
      2>/dev/null || true
  )

  printf "\rAttempt %02d/42 | no-key: HTTP %-3s | with-key: HTTP %-3s" \
    "$I" \
    "${NO_KEY_CODE:----}" \
    "${WITH_KEY_CODE:----}"

  if [ "$NO_KEY_CODE" != "200" ] &&
     [ "$WITH_KEY_CODE" = "200" ] &&
     [ "$WITH_KEY_BODY" = "Hello World!" ]; then

    FINAL_SUCCESS=true
    break

  fi

  sleep 10

done

echo
echo

echo "${CYAN_TEXT}${BOLD_TEXT}WITHOUT API KEY${RESET_FORMAT}"
echo "HTTP $NO_KEY_CODE"

if [ -n "$NO_KEY_BODY" ]; then
  echo "$NO_KEY_BODY"
fi

echo
echo "${CYAN_TEXT}${BOLD_TEXT}WITH API KEY${RESET_FORMAT}"
echo "HTTP $WITH_KEY_CODE"

if [ -n "$WITH_KEY_BODY" ]; then
  echo "$WITH_KEY_BODY"
fi

echo

if [ "$FINAL_SUCCESS" != "true" ]; then

  echo "${RED_TEXT}${BOLD_TEXT}Task 6 verification failed.${RESET_FORMAT}"
  echo
  echo "Expected:"
  echo
  echo "  Without key -> rejected / UNAUTHENTICATED"
  echo "  With key    -> HTTP 200 + Hello World!"
  echo
  echo "Last status:"
  echo "  Without key : HTTP $NO_KEY_CODE"
  echo "  With key    : HTTP $WITH_KEY_CODE"
  echo

  exit 1

fi

ok "Request without API key is rejected."
ok "Request with API key returns Hello World!"
ok "TASK 6 completed."

# ============================================================
# FINAL
# ============================================================

echo
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}              LAB COMPLETED SUCCESSFULLY              ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo

echo "Project ID      : $PROJECT_ID"
echo "Project Number  : $PROJECT_NUMBER"
echo "Region          : $REGION"
echo
echo "Function        : helloGET"
echo "Function URL    : $FUNCTION_URL"
echo
echo "API ID          : $API_ID"
echo "Gateway         : hello-gateway"
echo "Gateway URL     : https://${GATEWAY_URL}"
echo
echo "Managed Service : $MANAGED_SERVICE"
echo "API Config      : $SEC_CONFIG_ID"
echo "Backend SA      : $QWIKLABS_SA"
echo "API Key         : ${API_KEY:0:8}...${API_KEY: -4}"

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