#!/bin/bash

# ============================================================
# Google Cloud API Gateway Challenge Lab
# Cloud Run Functions + API Gateway + Pub/Sub
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
print_banner() {
  clear
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║        GOOGLE CLOUD API GATEWAY CHALLENGE LAB            ║"
  echo "║                                                          ║"
  echo "║     Cloud Run Functions • API Gateway • Pub/Sub          ║"
  echo "║                                                          ║"
  echo "║                    © ePlus.DEV                           ║"
  echo "╚══════════════════════════════════════════════════════════╝"
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
  local line_number=$1

  echo
  error "Script failed at line ${line_number} with exit code ${exit_code}."
  echo -e "${GRAY}© ePlus.DEV${NC}"
  exit "${exit_code}"
}

trap 'on_error $LINENO' ERR

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------
# Retry a command
# ------------------------------------------------------------
retry_command() {
  local max_attempts="$1"
  local delay="$2"
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

    warning "Attempt ${attempt}/${max_attempts} failed. Retrying..."
    sleep "${delay}"
    ((attempt++))
  done
}

# ------------------------------------------------------------
# Test an HTTP endpoint
# ------------------------------------------------------------
wait_for_http() {
  local url="$1"
  local expected_text="$2"
  local max_attempts="${3:-30}"
  local delay="${4:-10}"

  local response=""
  local attempt=1

  while (( attempt <= max_attempts )); do
    response="$(curl -fsS --max-time 30 "${url}" 2>/dev/null || true)"

    if [[ "${response}" == *"${expected_text}"* ]]; then
      echo
      success "Endpoint responded successfully."
      echo -e "${CYAN}Response:${NC} ${response}"
      return 0
    fi

    warning "Endpoint is not ready yet (${attempt}/${max_attempts})."
    sleep "${delay}"
    ((attempt++))
  done

  error "Endpoint did not return the expected response."
  echo -e "${YELLOW}Last response:${NC} ${response:-No response}"
  return 1
}

print_banner

# ------------------------------------------------------------
# Validate environment
# ------------------------------------------------------------
section "Environment validation"

if ! command_exists gcloud; then
  error "gcloud CLI was not found. Run this script in Google Cloud Shell."
  exit 1
fi

if ! command_exists curl; then
  error "curl was not found."
  exit 1
fi

success "Required commands are available."

# ------------------------------------------------------------
# Automatically detect project configuration
# ------------------------------------------------------------
section "Detecting Google Cloud configuration"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  PROJECT_ID="$(gcloud projects list \
    --format="value(projectId)" \
    --limit=1)"
fi

if [[ -z "${PROJECT_ID}" ]]; then
  error "Unable to detect the Google Cloud project."
  exit 1
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" \
  --format="value(projectNumber)")"

USER_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"

DEFAULT_REGION="$(gcloud compute project-info describe \
  --project="${PROJECT_ID}" \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
  2>/dev/null || true)"

DEFAULT_ZONE="$(gcloud compute project-info describe \
  --project="${PROJECT_ID}" \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
  2>/dev/null || true)"

# The challenge lab specifically requires us-east1.
REGION="us-east1"

# Zone is not used by this lab, but it is detected automatically.
ZONE="${DEFAULT_ZONE:-us-east1-b}"

FUNCTION_NAME="gcfunction"
FUNCTION_ENTRY_POINT="helloHttp"

API_ID="gcfunction-api"
API_CONFIG_ID="gcfunction-api"
GATEWAY_ID="gcfunction-api"

TOPIC_ID="demo-topic"
SUBSCRIPTION_ID="demo-topic-sub"

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

if [[ "${USER_ACCOUNT}" == *".gserviceaccount.com" ]]; then
  USER_PRINCIPAL="serviceAccount:${USER_ACCOUNT}"
else
  USER_PRINCIPAL="user:${USER_ACCOUNT}"
fi

echo -e "${CYAN}Project ID:${NC}             ${PROJECT_ID}"
echo -e "${CYAN}Project number:${NC}         ${PROJECT_NUMBER}"
echo -e "${CYAN}Current account:${NC}        ${USER_ACCOUNT}"
echo -e "${CYAN}Detected region:${NC}        ${DEFAULT_REGION:-Not configured}"
echo -e "${CYAN}Required lab region:${NC}    ${REGION}"
echo -e "${CYAN}Detected zone:${NC}          ${ZONE}"
echo -e "${CYAN}Compute service account:${NC} ${COMPUTE_SA}"

if [[ -n "${DEFAULT_REGION}" && "${DEFAULT_REGION}" != "${REGION}" ]]; then
  warning "The detected default region is ${DEFAULT_REGION}."
  warning "The script will use ${REGION} because the lab requires it."
fi

gcloud config set functions/region "${REGION}" >/dev/null
gcloud config set run/region "${REGION}" >/dev/null

success "Cloud configuration detected."

# ------------------------------------------------------------
# Enable APIs
# ------------------------------------------------------------
section "Enabling required Google Cloud APIs"

gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  pubsub.googleapis.com \
  logging.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet

success "Required APIs are enabled."

# ------------------------------------------------------------
# Wait for Compute Engine default service account
# ------------------------------------------------------------
info "Checking the Compute Engine default service account..."

SERVICE_ACCOUNT_READY=false

for attempt in {1..30}; do
  if gcloud iam service-accounts describe "${COMPUTE_SA}" \
    --project="${PROJECT_ID}" >/dev/null 2>&1; then

    SERVICE_ACCOUNT_READY=true
    break
  fi

  warning "Compute Engine service account is not ready (${attempt}/30)."
  sleep 5
done

if [[ "${SERVICE_ACCOUNT_READY}" != "true" ]]; then
  error "Compute Engine default service account was not found:"
  echo "${COMPUTE_SA}"
  exit 1
fi

success "Compute Engine default service account is available."

# ------------------------------------------------------------
# Working directory
# ------------------------------------------------------------
WORK_DIR="${HOME}/gcfunction-api-lab"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

success "Working directory created: ${WORK_DIR}"

# ============================================================
# TASK 1
# ============================================================
section "Task 1: Create the Cloud Run function"

cat > package.json <<'PACKAGE_EOF'
{
  "name": "gcfunction",
  "version": "1.0.0",
  "description": "Google Cloud challenge lab function",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
PACKAGE_EOF

cat > index.js <<'INDEX_EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('helloHttp', (req, res) => {
  res.status(200).send('Hello World!');
});
INDEX_EOF

success "Initial Node.js function source code created."

deploy_function() {
  gcloud functions deploy "${FUNCTION_NAME}" \
    --gen2 \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --runtime="nodejs22" \
    --source="${WORK_DIR}" \
    --entry-point="${FUNCTION_ENTRY_POINT}" \
    --trigger-http \
    --allow-unauthenticated \
    --service-account="${COMPUTE_SA}" \
    --quiet
}

info "Deploying Cloud Run function ${FUNCTION_NAME}..."

retry_command 8 20 deploy_function

FUNCTION_URL="$(gcloud functions describe "${FUNCTION_NAME}" \
  --gen2 \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format="value(serviceConfig.uri)")"

if [[ -z "${FUNCTION_URL}" ]]; then
  error "Unable to retrieve the Cloud Run function URL."
  exit 1
fi

success "Cloud Run function deployed."
echo -e "${CYAN}Function URL:${NC} ${FUNCTION_URL}"

info "Testing the initial Cloud Run function..."

wait_for_http "${FUNCTION_URL}" "Hello World!" 20 10

success "Task 1 completed."

# ============================================================
# TASK 2
# ============================================================
section "Task 2: Create API Gateway"

# Allow API Gateway's selected service account to invoke the backend.
info "Granting Cloud Run Invoker to the Compute Engine service account..."

gcloud run services add-iam-policy-binding "${FUNCTION_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/run.invoker" \
  --quiet >/dev/null

success "Cloud Run Invoker permission granted."

# Allow the active student account to use the Compute Engine service account.
info "Granting Service Account User permission to the active account..."

if gcloud iam service-accounts add-iam-policy-binding "${COMPUTE_SA}" \
  --project="${PROJECT_ID}" \
  --member="${USER_PRINCIPAL}" \
  --role="roles/iam.serviceAccountUser" \
  --quiet >/dev/null 2>&1; then

  success "Service Account User permission granted."
else
  warning "Unable to modify the service account IAM policy."
  warning "The current lab account may already have the required permission."
fi

# Create the OpenAPI specification dynamically.
cat > openapispec.yaml <<OPENAPI_EOF
swagger: '2.0'
info:
  title: gcfunction API
  description: Sample API on API Gateway with a Google Cloud Run functions backend
  version: 1.0.0
schemes:
- https
produces:
- application/json
x-google-backend:
  address: ${FUNCTION_URL}
paths:
  /gcfunction:
    get:
      summary: gcfunction
      operationId: gcfunction
      responses:
        '200':
          description: A successful response
          schema:
            type: string
OPENAPI_EOF

success "openapispec.yaml created."

echo
echo -e "${GRAY}---------------- openapispec.yaml ----------------${NC}"
cat openapispec.yaml
echo -e "${GRAY}--------------------------------------------------${NC}"
echo

# Create API.
if gcloud api-gateway apis describe "${API_ID}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then

  success "API ${API_ID} already exists."
else
  info "Creating API ${API_ID}..."

  gcloud api-gateway apis create "${API_ID}" \
    --project="${PROJECT_ID}" \
    --display-name="gcfunction API" \
    --quiet

  success "API ${API_ID} created."
fi

create_api_config() {
  gcloud api-gateway api-configs create "${API_CONFIG_ID}" \
    --project="${PROJECT_ID}" \
    --api="${API_ID}" \
    --openapi-spec="${WORK_DIR}/openapispec.yaml" \
    --backend-auth-service-account="${COMPUTE_SA}" \
    --display-name="gcfunction API" \
    --quiet
}

# Create API configuration.
if gcloud api-gateway api-configs describe "${API_CONFIG_ID}" \
  --project="${PROJECT_ID}" \
  --api="${API_ID}" >/dev/null 2>&1; then

  API_CONFIG_STATE="$(gcloud api-gateway api-configs describe \
    "${API_CONFIG_ID}" \
    --project="${PROJECT_ID}" \
    --api="${API_ID}" \
    --format="value(state)" 2>/dev/null || true)"

  if [[ "${API_CONFIG_STATE}" == "ACTIVE" ]]; then
    success "API configuration ${API_CONFIG_ID} already exists and is active."
  elif [[ "${API_CONFIG_STATE}" == "FAILED" ]]; then
    warning "Existing API configuration is in FAILED state."
    info "Deleting the failed API configuration..."

    gcloud api-gateway api-configs delete "${API_CONFIG_ID}" \
      --project="${PROJECT_ID}" \
      --api="${API_ID}" \
      --quiet

    retry_command 5 20 create_api_config
  else
    info "Existing API configuration state: ${API_CONFIG_STATE:-Unknown}"
  fi
else
  info "Creating API configuration ${API_CONFIG_ID}..."
  retry_command 5 20 create_api_config
fi

success "API configuration is available."

create_gateway() {
  gcloud api-gateway gateways create "${GATEWAY_ID}" \
    --project="${PROJECT_ID}" \
    --api="${API_ID}" \
    --api-config="${API_CONFIG_ID}" \
    --location="${REGION}" \
    --display-name="gcfunction API" \
    --quiet
}

# Create gateway.
if gcloud api-gateway gateways describe "${GATEWAY_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" >/dev/null 2>&1; then

  success "Gateway ${GATEWAY_ID} already exists."
else
  info "Creating API Gateway ${GATEWAY_ID}..."
  retry_command 3 30 create_gateway
fi

# Wait until the gateway becomes active.
info "Checking API Gateway deployment status..."

GATEWAY_ACTIVE=false

for attempt in {1..60}; do
  GATEWAY_STATE="$(gcloud api-gateway gateways describe "${GATEWAY_ID}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --format="value(state)" 2>/dev/null || true)"

  case "${GATEWAY_STATE}" in
    ACTIVE)
      GATEWAY_ACTIVE=true
      success "API Gateway is active."
      break
      ;;
    FAILED)
      error "API Gateway deployment failed."
      exit 1
      ;;
    *)
      warning "Gateway state: ${GATEWAY_STATE:-Creating} (${attempt}/60)"
      sleep 10
      ;;
  esac
done

if [[ "${GATEWAY_ACTIVE}" != "true" ]]; then
  error "API Gateway did not reach ACTIVE state."
  exit 1
fi

GATEWAY_HOST="$(gcloud api-gateway gateways describe "${GATEWAY_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --format="value(defaultHostname)")"

if [[ -z "${GATEWAY_HOST}" ]]; then
  error "Unable to retrieve the API Gateway hostname."
  exit 1
fi

GATEWAY_URL="https://${GATEWAY_HOST}/gcfunction"

echo -e "${CYAN}Gateway hostname:${NC} ${GATEWAY_HOST}"
echo -e "${CYAN}Gateway endpoint:${NC} ${GATEWAY_URL}"

info "Testing the API Gateway endpoint..."

wait_for_http "${GATEWAY_URL}" "Hello World!" 30 10

success "Task 2 completed."

# ============================================================
# TASK 3
# ============================================================
section "Task 3: Create Pub/Sub and publish messages"

# Create Pub/Sub topic.
if gcloud pubsub topics describe "${TOPIC_ID}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then

  success "Pub/Sub topic ${TOPIC_ID} already exists."
else
  info "Creating Pub/Sub topic ${TOPIC_ID}..."

  gcloud pubsub topics create "${TOPIC_ID}" \
    --project="${PROJECT_ID}" \
    --quiet

  success "Pub/Sub topic ${TOPIC_ID} created."
fi

# Create the equivalent of the default subscription.
if gcloud pubsub subscriptions describe "${SUBSCRIPTION_ID}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then

  success "Subscription ${SUBSCRIPTION_ID} already exists."
else
  info "Creating default subscription ${SUBSCRIPTION_ID}..."

  gcloud pubsub subscriptions create "${SUBSCRIPTION_ID}" \
    --project="${PROJECT_ID}" \
    --topic="${TOPIC_ID}" \
    --quiet

  success "Default subscription ${SUBSCRIPTION_ID} created."
fi

# Grant the function runtime service account Pub/Sub Publisher.
info "Granting Pub/Sub Publisher permission..."

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/pubsub.publisher" \
  --condition=None \
  --quiet >/dev/null

success "Pub/Sub Publisher permission granted."

# Update package.json exactly as required.
cat > package.json <<'PACKAGE_EOF'
{
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^3.4.1"
  }
}
PACKAGE_EOF

# Update function implementation.
cat > index.js <<'INDEX_EOF'
const {PubSub} = require('@google-cloud/pubsub');
const functions = require('@google-cloud/functions-framework');

const pubsub = new PubSub();
const topic = pubsub.topic('demo-topic');

functions.http('helloHttp', async (req, res) => {
  try {
    await topic.publishMessage({
      data: Buffer.from('Hello from Cloud Run functions!')
    });

    res.status(200).send('Message sent to Topic demo-topic!');
  } catch (error) {
    console.error('Failed to publish message:', error);
    res.status(500).send(`Failed to publish message: ${error.message}`);
  }
});
INDEX_EOF

success "Cloud Run function source updated with Pub/Sub publishing."

info "Redeploying Cloud Run function..."

retry_command 8 20 deploy_function

success "Cloud Run function redeployed."

# Refresh the URL after deployment.
FUNCTION_URL="$(gcloud functions describe "${FUNCTION_NAME}" \
  --gen2 \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format="value(serviceConfig.uri)")"

# Reapply required invocation permissions after deployment.
gcloud run services add-iam-policy-binding "${FUNCTION_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/run.invoker" \
  --quiet >/dev/null

info "Invoking the Cloud Run function through API Gateway..."

wait_for_http \
  "${GATEWAY_URL}" \
  "Message sent to Topic demo-topic!" \
  30 \
  10

# Publish additional messages to make grader detection easier.
info "Publishing additional messages through API Gateway..."

for invocation in 1 2 3; do
  RESPONSE="$(curl -fsS --max-time 30 "${GATEWAY_URL}" 2>/dev/null || true)"

  if [[ "${RESPONSE}" == *"Message sent to Topic demo-topic!"* ]]; then
    success "Invocation ${invocation}: ${RESPONSE}"
  else
    warning "Invocation ${invocation} returned: ${RESPONSE:-No response}"
  fi

  sleep 2
done

success "Task 3 completed."

# ============================================================
# Final verification
# ============================================================
section "Final resource verification"

echo -e "${CYAN}Cloud Run function${NC}"
gcloud functions describe "${FUNCTION_NAME}" \
  --gen2 \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format="table(
    name.basename():label=FUNCTION,
    environment:label=GENERATION,
    buildConfig.runtime:label=RUNTIME,
    serviceConfig.serviceAccountEmail:label=SERVICE_ACCOUNT,
    serviceConfig.uri:label=URL
  )"

echo
echo -e "${CYAN}API Gateway${NC}"
gcloud api-gateway gateways describe "${GATEWAY_ID}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    state:label=STATE,
    defaultHostname:label=HOSTNAME
  )"

echo
echo -e "${CYAN}API configuration${NC}"
gcloud api-gateway api-configs describe "${API_CONFIG_ID}" \
  --project="${PROJECT_ID}" \
  --api="${API_ID}" \
  --format="table(
    displayName:label=DISPLAY_NAME,
    state:label=STATE,
    serviceConfigId:label=SERVICE_CONFIG
  )"

echo
echo -e "${CYAN}Pub/Sub topic${NC}"
gcloud pubsub topics describe "${TOPIC_ID}" \
  --project="${PROJECT_ID}" \
  --format="value(name)"

echo
echo -e "${CYAN}Pub/Sub subscription${NC}"
gcloud pubsub subscriptions describe "${SUBSCRIPTION_ID}" \
  --project="${PROJECT_ID}" \
  --format="table(
    name.basename():label=SUBSCRIPTION,
    topic.basename():label=TOPIC
  )"

# ------------------------------------------------------------
# Completion banner
# ------------------------------------------------------------
echo
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 ALL TASKS COMPLETED                      ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║ %-56s ║\n" "Project: ${PROJECT_ID}"
printf "║ %-56s ║\n" "Region: ${REGION}"
printf "║ %-56s ║\n" "Function: ${FUNCTION_NAME}"
printf "║ %-56s ║\n" "API Gateway: ${GATEWAY_ID}"
printf "║ %-56s ║\n" "Pub/Sub topic: ${TOPIC_ID}"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                    © ePlus.DEV                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${WHITE}API Gateway URL:${NC}"
echo -e "${CYAN}${GATEWAY_URL}${NC}"
echo

echo -e "${YELLOW}Do not pull or acknowledge messages before grading.${NC}"
echo -e "${GREEN}You can now click Check my progress for all three tasks.${NC}"