#!/usr/bin/env bash
set -uo pipefail

# ============================================================
# API Gateway - Secure Traffic to a Backend Service
# © ePlus.DEV
# ============================================================

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
GATEWAY_ID="hello-gateway"
CONFIG1_ID="hello-world-config"
CONFIG2_ID="hello-config"
KEY_DISPLAY_NAME="Hello World API Key"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
  echo -e "${CYAN}==============================================================${NC}"
  echo -e "${CYAN}  API Gateway Lab Automation - © ePlus.DEV${NC}"
  echo -e "${CYAN}==============================================================${NC}"
}

step() {
  echo -e "\n${BLUE}[$1/6] $2${NC}"
}

ok() {
  echo -e "${GREEN}✓ $*${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ $*${NC}"
}

fail() {
  echo -e "${RED}✗ $*${NC}"
  exit 1
}

retry_cmd() {
  local max="$1"
  local delay="$2"
  shift 2

  local i
  for ((i=1; i<=max; i++)); do
    if "$@"; then
      return 0
    fi

    warn "Attempt $i/$max failed. Retrying in ${delay}s..."
    sleep "$delay"
  done

  return 1
}

wait_api_config() {
  local config="$1"
  local api="$2"
  local state
  local i

  for i in {1..60}; do
    state=$(
      gcloud api-gateway api-configs describe "$config" \
        --api="$api" \
        --project="$PROJECT_ID" \
        --format='value(state)' 2>/dev/null || true
    )

    printf "\r  Waiting for API config %-24s state: %-10s (%02d/60)" \
      "$config" "${state:-PENDING}" "$i"

    if [[ "$state" == "ACTIVE" ]]; then
      echo
      return 0
    fi

    if [[ "$state" == "FAILED" ]]; then
      echo
      return 1
    fi

    sleep 10
  done

  echo
  return 1
}

wait_gateway() {
  local state
  local i

  for i in {1..90}; do
    state=$(
      gcloud api-gateway gateways describe "$GATEWAY_ID" \
        --location="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(state)' 2>/dev/null || true
    )

    printf "\r  Waiting for gateway %-18s state: %-10s (%02d/90)" \
      "$GATEWAY_ID" "${state:-PENDING}" "$i"

    if [[ "$state" == "ACTIVE" ]]; then
      echo
      return 0
    fi

    if [[ "$state" == "FAILED" ]]; then
      echo
      return 1
    fi

    sleep 10
  done

  echo
  return 1
}

banner

# ============================================================
# TASK 1
# ============================================================

step 1 "Detecting project and deploying API backend"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || \
  fail "No active Google Cloud project found."

PROJECT_NUMBER=$(
  gcloud projects describe "$PROJECT_ID" \
    --format='value(projectNumber)' 2>/dev/null
) || fail "Cannot read project number."

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud config set project "$PROJECT_ID" --quiet >/dev/null
gcloud config set compute/region "$REGION" --quiet >/dev/null

echo "Project ID     : $PROJECT_ID"
echo "Project number : $PROJECT_NUMBER"
echo "Region         : $REGION"

echo "→ Enabling required APIs"

gcloud services enable \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  compute.googleapis.com \
  apikeys.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet >/dev/null || fail "Could not enable required APIs."

# Wait for Compute Engine default service account if necessary
for _ in {1..12}; do
  if gcloud iam service-accounts describe "$COMPUTE_SA" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then
    break
  fi

  sleep 5
done

# ------------------------------------------------------------
# Create Cloud Function source
# ------------------------------------------------------------

mkdir -p "$HOME/helloGET-src"

cat > "$HOME/helloGET-src/index.js" <<'EOF'
exports.helloGET = (req, res) => {
  res.send('Hello World!');
};
EOF

cat > "$HOME/helloGET-src/package.json" <<'EOF'
{
  "name": "hello-get",
  "version": "1.0.0",
  "main": "index.js",
  "engines": {
    "node": "22"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.4.0"
  }
}
EOF

if gcloud functions describe helloGET \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Cloud Function helloGET already exists."

else

  echo "→ Deploying helloGET"

  retry_cmd 2 15 \
    gcloud functions deploy helloGET \
      --runtime=nodejs22 \
      --trigger-http \
      --allow-unauthenticated \
      --region="$REGION" \
      --source="$HOME/helloGET-src" \
      --entry-point=helloGET \
      --project="$PROJECT_ID" \
      --quiet || fail "helloGET deployment failed."
fi

FUNCTION_URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/helloGET"

ok "Task 1 backend deployed:"
echo "$FUNCTION_URL"

# ============================================================
# TASK 2
# ============================================================

step 2 "Testing API backend"

BACKEND_RESULT=""

for i in {1..12}; do

  BACKEND_RESULT=$(
    curl -fsS "$FUNCTION_URL" 2>/dev/null || true
  )

  if [[ "$BACKEND_RESULT" == "Hello World!" ]]; then
    break
  fi

  echo "  Backend not ready yet ($i/12). Retrying..."
  sleep 5
done

[[ "$BACKEND_RESULT" == "Hello World!" ]] || \
  fail "Backend did not return 'Hello World!'."

ok "Task 2 backend response: $BACKEND_RESULT"

# ============================================================
# TASK 3
# ============================================================

step 3 "Creating API, API config and gateway"

# Reuse API if script was already run
API_ID=$(
  gcloud api-gateway apis list \
    --project="$PROJECT_ID" \
    --filter='displayName="Hello World API"' \
    --format='value(name.basename())' \
    2>/dev/null | head -n1
)

if [[ -z "$API_ID" ]]; then

  API_ID="hello-world-$(tr -dc 'a-z' </dev/urandom | head -c 8)"

  gcloud api-gateway apis create "$API_ID" \
    --display-name="Hello World API" \
    --project="$PROJECT_ID" \
    --quiet || fail "Could not create API."

  ok "Created API: $API_ID"

else

  ok "Using existing API: $API_ID"

fi

# ------------------------------------------------------------
# First OpenAPI config - no API key
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

# ------------------------------------------------------------
# Gateway may already exist after a partial run
# ------------------------------------------------------------

if gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Gateway $GATEWAY_ID already exists."

else

  if ! gcloud api-gateway api-configs describe "$CONFIG1_ID" \
      --api="$API_ID" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then

    echo "→ Creating initial API config"

    gcloud api-gateway api-configs create "$CONFIG1_ID" \
      --api="$API_ID" \
      --openapi-spec="$HOME/openapi2-functions.yaml" \
      --backend-auth-service-account="$COMPUTE_SA" \
      --display-name="Hello World Config" \
      --project="$PROJECT_ID" \
      --async \
      --quiet >/dev/null || \
      fail "Could not start initial API config creation."

  fi

  wait_api_config "$CONFIG1_ID" "$API_ID" || \
    fail "Initial API config did not become ACTIVE."

  echo "→ Creating gateway"

  gcloud api-gateway gateways create "$GATEWAY_ID" \
    --api="$API_ID" \
    --api-config="$CONFIG1_ID" \
    --location="$REGION" \
    --display-name="Hello Gateway" \
    --project="$PROJECT_ID" \
    --async \
    --quiet >/dev/null || \
    fail "Could not start gateway creation."

  wait_gateway || \
    fail "Gateway did not become ACTIVE."

fi

GATEWAY_URL=$(
  gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(defaultHostname)'
)

[[ -n "$GATEWAY_URL" ]] || \
  fail "Could not determine gateway hostname."

echo
echo "Gateway URL:"
echo "https://$GATEWAY_URL"

INITIAL_RESULT=$(
  curl -sS "https://${GATEWAY_URL}/hello" 2>/dev/null || true
)

if [[ "$INITIAL_RESULT" == *"Hello World!"* ]]; then

  ok "Task 3 gateway is working: Hello World!"

else

  warn "Gateway may already be protected from a previous run."
  warn "Continuing with security tasks."

fi

# ============================================================
# TASK 4
# ============================================================

step 4 "Enabling managed service and creating restricted API key"

MANAGED_SERVICE=$(
  gcloud api-gateway apis describe "$API_ID" \
    --project="$PROJECT_ID" \
    --format='value(managedService)'
)

[[ -n "$MANAGED_SERVICE" ]] || \
  fail "Managed Service name not found."

echo "Managed Service : $MANAGED_SERVICE"

echo "→ Enabling API key support"

retry_cmd 12 10 \
  gcloud services enable "$MANAGED_SERVICE" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null || \
  fail "Could not enable API key support."

# ------------------------------------------------------------
# Find existing API key
# ------------------------------------------------------------

KEY_RESOURCE=$(
  gcloud services api-keys list \
    --project="$PROJECT_ID" \
    --filter="displayName=\"$KEY_DISPLAY_NAME\"" \
    --format='value(name)' \
    2>/dev/null | head -n1
)

if [[ -z "$KEY_RESOURCE" ]]; then

  echo "→ Creating API key restricted to API Gateway"

  retry_cmd 6 10 \
    gcloud services api-keys create \
      --display-name="$KEY_DISPLAY_NAME" \
      --api-target="service=$MANAGED_SERVICE" \
      --project="$PROJECT_ID" \
      --quiet >/dev/null || \
    fail "Could not create API key."

  # Wait until API key becomes visible
  for _ in {1..12}; do

    KEY_RESOURCE=$(
      gcloud services api-keys list \
        --project="$PROJECT_ID" \
        --filter="displayName=\"$KEY_DISPLAY_NAME\"" \
        --format='value(name)' \
        2>/dev/null | head -n1
    )

    [[ -n "$KEY_RESOURCE" ]] && break

    sleep 5
  done

else

  echo "→ Reusing existing API key"

  gcloud services api-keys update "$KEY_RESOURCE" \
    --api-target="service=$MANAGED_SERVICE" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null || \
    fail "Could not update API key restriction."

fi

[[ -n "$KEY_RESOURCE" ]] || \
  fail "API key resource was not found."

API_KEY=$(
  gcloud services api-keys get-key-string "$KEY_RESOURCE" \
    --project="$PROJECT_ID" \
    --format='value(keyString)' \
    2>/dev/null
)

[[ -n "$API_KEY" ]] || \
  fail "Could not retrieve API key string."

ok "Task 4 API key created and restricted."

# ============================================================
# TASK 5
# ============================================================

step 5 "Creating secured API config and updating gateway"

# ------------------------------------------------------------
# OpenAPI config requiring ?key=
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
# Lab explicitly asks for:
# "Qwiklabs User Service Account"
# Find it automatically.
# ------------------------------------------------------------

QWIKLABS_SA=$(
  gcloud iam service-accounts list \
    --project="$PROJECT_ID" \
    --filter='displayName="Qwiklabs User Service Account"' \
    --format='value(email)' \
    2>/dev/null | head -n1
)

if [[ -z "$QWIKLABS_SA" ]]; then

  QWIKLABS_SA=$(
    gcloud iam service-accounts list \
      --project="$PROJECT_ID" \
      --filter='displayName~"Qwiklabs"' \
      --format='value(email)' \
      2>/dev/null | head -n1
  )

fi

if [[ -z "$QWIKLABS_SA" ]]; then

  warn "Qwiklabs User Service Account not found."
  warn "Falling back to Compute Engine default service account."

  QWIKLABS_SA="$COMPUTE_SA"

fi

echo "Backend SA      : $QWIKLABS_SA"

# API configs are immutable.
# Avoid conflict on reruns.

if gcloud api-gateway api-configs describe "$CONFIG2_ID" \
    --api="$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  CURRENT_CFG=$(
    gcloud api-gateway gateways describe "$GATEWAY_ID" \
      --location="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(apiConfig)' \
      2>/dev/null || true
  )

  if [[ "$CURRENT_CFG" == */configs/${CONFIG2_ID} ]]; then

    ok "Secured config $CONFIG2_ID is already attached."

  else

    CONFIG2_ID="hello-config-$(date +%H%M%S)"

  fi

fi

# ------------------------------------------------------------
# Create secured API config
# ------------------------------------------------------------

if ! gcloud api-gateway api-configs describe "$CONFIG2_ID" \
    --api="$API_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  echo "→ Creating secured API config: $CONFIG2_ID"

  gcloud api-gateway api-configs create "$CONFIG2_ID" \
    --api="$API_ID" \
    --openapi-spec="$HOME/openapi2-functions2.yaml" \
    --backend-auth-service-account="$QWIKLABS_SA" \
    --display-name="Hello Config" \
    --project="$PROJECT_ID" \
    --async \
    --quiet >/dev/null || \
    fail "Could not start secured API config creation."

  wait_api_config "$CONFIG2_ID" "$API_ID" || \
    fail "Secured API config did not become ACTIVE."

fi

CURRENT_CFG=$(
  gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(apiConfig)' \
    2>/dev/null || true
)

# ------------------------------------------------------------
# Update existing gateway
# ------------------------------------------------------------

if [[ "$CURRENT_CFG" != */configs/${CONFIG2_ID} ]]; then

  echo "→ Updating gateway to secured config"

  gcloud api-gateway gateways update "$GATEWAY_ID" \
    --api="$API_ID" \
    --api-config="$CONFIG2_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --async \
    --quiet >/dev/null || \
    fail "Could not start gateway update."

  wait_gateway || \
    fail "Gateway update did not become ACTIVE."

fi

ok "Task 5 secured API config deployed."

# ============================================================
# TASK 6
# ============================================================

step 6 "Testing calls with and without API key"

GATEWAY_URL=$(
  gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(defaultHostname)'
)

# ------------------------------------------------------------
# Call without API key
# Expected: UNAUTHENTICATED / HTTP 401 or 403
# ------------------------------------------------------------

NO_KEY_CODE=$(
  curl -sS \
    -o /tmp/no-key.out \
    -w '%{http_code}' \
    "https://${GATEWAY_URL}/hello" \
    2>/dev/null || true
)

echo
echo "Without API key : HTTP ${NO_KEY_CODE:-unknown}"

# ------------------------------------------------------------
# Call with API key
# ------------------------------------------------------------

WITH_KEY_RESULT=""

for i in {1..18}; do

  WITH_KEY_RESULT=$(
    curl -fsS \
      "https://${GATEWAY_URL}/hello?key=${API_KEY}" \
      2>/dev/null || true
  )

  if [[ "$WITH_KEY_RESULT" == "Hello World!" ]]; then
    break
  fi

  echo "  Waiting for API-key/config propagation ($i/18)..."
  sleep 10

done

if [[ "$WITH_KEY_RESULT" != "Hello World!" ]]; then

  echo
  echo "Response with key:"
  echo "${WITH_KEY_RESULT:-<empty>}"

  fail "API key call did not return 'Hello World!'."

fi

ok "Task 6 API key call returned: Hello World!"

# ============================================================
# DONE
# ============================================================

echo
echo -e "${GREEN}==============================================================${NC}"
echo -e "${GREEN}  API GATEWAY LAB COMPLETE${NC}"
echo -e "${GREEN}==============================================================${NC}"

echo
echo "Project ID      : $PROJECT_ID"
echo "API ID          : $API_ID"
echo "Gateway         : $GATEWAY_ID"
echo "Gateway URL     : https://$GATEWAY_URL"
echo "Managed Service : $MANAGED_SERVICE"
echo "API Key         : ${API_KEY:0:8}...${API_KEY: -4}"

echo
echo -e "${GREEN}✓ TASK 1 - Deploying an API Backend${NC}"
echo -e "${GREEN}✓ TASK 2 - Test the API Backend${NC}"
echo -e "${GREEN}✓ TASK 3 - Creating a Gateway${NC}"
echo -e "${GREEN}✓ TASK 4 - Securing Access by Using an API Key${NC}"
echo -e "${GREEN}✓ TASK 5 - Create and deploy new API config${NC}"
echo -e "${GREEN}✓ TASK 6 - Testing Calls Using Your API Key${NC}"

echo
echo "→ Click Check my progress for Tasks 1 → 6."
echo
echo "© ePlus.DEV"