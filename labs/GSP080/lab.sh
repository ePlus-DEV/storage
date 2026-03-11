#!/usr/bin/env bash
# =========================================================
#  ePlus.DEV - Google Cloud Run Functions Gen2 Lab Automator
#  Copyright (c) 2026 ePlus.DEV. All rights reserved.
# =========================================================

set -euo pipefail

# -----------------------------
# Colors
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# -----------------------------
# Branding
# -----------------------------
print_banner() {
  echo -e "${CYAN}"
  echo "=========================================================="
  echo "           ePlus.DEV | Cloud Run Function Lab"
  echo "=========================================================="
  echo -e "${NC}"
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
  echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_err() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# -----------------------------
# Config
# -----------------------------
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
FUNCTION_NAME="nodejs-pubsub-function"
ENTRY_POINT="helloPubSub"
RUNTIME="nodejs20"
TOPIC_NAME="cf-demo"
WORKDIR="${HOME}/gcf_hello_world"
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null || true)"
STAGE_BUCKET="${PROJECT_ID}-bucket"
SERVICE_ACCOUNT="cloudfunctionsa@${PROJECT_ID}.iam.gserviceaccount.com"
TEST_MESSAGE="Cloud Function Gen2"

# -----------------------------
# Validate environment
# -----------------------------
print_banner

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  log_err "No active Google Cloud project found."
  log_info "Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

log_info "Project ID     : ${PROJECT_ID}"
log_info "Project Number : ${PROJECT_NUMBER}"
log_info "Region         : ${REGION}"
log_info "Function       : ${FUNCTION_NAME}"
log_info "Topic          : ${TOPIC_NAME}"
log_info "Stage Bucket   : ${STAGE_BUCKET}"
log_info "Service Acc.   : ${SERVICE_ACCOUNT}"

# -----------------------------
# Set default region
# -----------------------------
log_info "Setting default Cloud Run region..."
gcloud config set run/region "${REGION}" >/dev/null
log_ok "Default region set to ${REGION}"

# -----------------------------
# Enable required APIs
# -----------------------------
log_info "Enabling required APIs..."
gcloud services enable \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  eventarc.googleapis.com \
  pubsub.googleapis.com \
  artifactregistry.googleapis.com \
  logging.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com
log_ok "Required APIs enabled"

# -----------------------------
# Ensure stage bucket exists
# -----------------------------
if gcloud storage buckets describe "gs://${STAGE_BUCKET}" >/dev/null 2>&1; then
  log_ok "Stage bucket already exists: gs://${STAGE_BUCKET}"
else
  log_warn "Stage bucket not found. Creating bucket..."
  gcloud storage buckets create "gs://${STAGE_BUCKET}" --location="${REGION}"
  log_ok "Created bucket: gs://${STAGE_BUCKET}"
fi

# -----------------------------
# Ensure Pub/Sub topic exists
# -----------------------------
if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
  log_ok "Pub/Sub topic already exists: ${TOPIC_NAME}"
else
  log_warn "Pub/Sub topic not found. Creating topic..."
  gcloud pubsub topics create "${TOPIC_NAME}"
  log_ok "Created topic: ${TOPIC_NAME}"
fi

# -----------------------------
# Ensure service account exists
# -----------------------------
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" >/dev/null 2>&1; then
  log_ok "Service account already exists: ${SERVICE_ACCOUNT}"
else
  log_warn "Service account not found. Creating..."
  gcloud iam service-accounts create "cloudfunctionsa" \
    --display-name="Cloud Functions Service Account"
  log_ok "Created service account: ${SERVICE_ACCOUNT}"
fi

# -----------------------------
# Grant minimal useful roles
# -----------------------------
log_info "Granting IAM roles to service account..."
for ROLE in \
  roles/run.invoker \
  roles/eventarc.eventReceiver \
  roles/pubsub.subscriber \
  roles/logging.logWriter \
  roles/storage.objectViewer
do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="${ROLE}" >/dev/null || true
done
log_ok "IAM role binding step completed"

# -----------------------------
# Create function source files
# -----------------------------
log_info "Preparing source directory..."
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');

// Register a CloudEvent callback with the Functions Framework that will
// be executed when the Pub/Sub trigger topic receives a message.
functions.cloudEvent('helloPubSub', cloudEvent => {
  // The Pub/Sub message is passed as the CloudEvent's data payload.
  const base64name = cloudEvent.data.message.data;

  const name = base64name
    ? Buffer.from(base64name, 'base64').toString()
    : 'World';

  console.log(`Hello, ${name}!`);
});
EOF

cat > package.json <<'EOF'
{
  "name": "gcf_hello_world",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"No test specified\" && exit 0"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

log_ok "Source files created"

# -----------------------------
# Install dependencies
# -----------------------------
log_info "Installing npm dependencies..."
npm install
log_ok "npm dependencies installed"

# -----------------------------
# Deploy function
# -----------------------------
log_info "Deploying Cloud Run Function Gen2..."
gcloud functions deploy "${FUNCTION_NAME}" \
  --gen2 \
  --runtime="${RUNTIME}" \
  --region="${REGION}" \
  --source="." \
  --entry-point="${ENTRY_POINT}" \
  --trigger-topic="${TOPIC_NAME}" \
  --stage-bucket="${STAGE_BUCKET}" \
  --service-account="${SERVICE_ACCOUNT}" \
  --allow-unauthenticated \
  --quiet

log_ok "Function deployed successfully"

# -----------------------------
# Describe function
# -----------------------------
log_info "Checking function status..."
gcloud functions describe "${FUNCTION_NAME}" \
  --region="${REGION}" \
  --format="yaml(name,state,serviceConfig.uri,buildConfig.entryPoint,eventTrigger.triggerRegion,eventTrigger.pubsubTopic,updateTime)"

# -----------------------------
# Publish test message
# -----------------------------
log_info "Publishing test message to Pub/Sub..."
gcloud pubsub topics publish "${TOPIC_NAME}" --message="${TEST_MESSAGE}"
log_ok "Test message published"

# -----------------------------
# Wait a bit for logs
# -----------------------------
log_warn "Waiting 20 seconds for execution and log ingestion..."
sleep 20

# -----------------------------
# Read logs
# -----------------------------
log_info "Reading function logs..."
gcloud functions logs read "${FUNCTION_NAME}" \
  --region="${REGION}" \
  --limit=20 || true

# -----------------------------
# Final output
# -----------------------------
echo
echo -e "${MAGENTA}==========================================================${NC}"
echo -e "${GREEN}Lab automation completed.${NC}"
echo -e "${CYAN}Expected answer for Task 5:${NC} True"
echo -e "${MAGENTA}==========================================================${NC}"
echo
echo -e "${YELLOW}Copyright (c) 2026 ePlus.DEV. All rights reserved.${NC}"