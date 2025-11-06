#!/bin/bash
set -e

# ----------------------------------------------------------
# Cloud Run Functions: Qwik Start - Command Line
# © 2025 ePlus.DEV — All Rights Reserved
# ----------------------------------------------------------

# ====== TERMINAL COLORS ======
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RESET="\033[0m"

echo -e "${CYAN}🚀 Starting Cloud Run Functions Gen2 with Pub/Sub setup...${RESET}"

# ====== AUTO-DETECT PROJECT_ID & REGION ======
PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}❌ Could not determine PROJECT_ID. Make sure you're authenticated (gcloud auth login) and have a project selected.${RESET}"
  exit 1
fi

if [[ -z "$REGION" ]]; then
  echo -e "${YELLOW}⚠️ Default region not found in project metadata. Falling back to: us-east1${RESET}"
  REGION="us-east1"
fi

echo -e "${GREEN}✅ Project: ${PROJECT_ID}${RESET}"
echo -e "${GREEN}✅ Region: ${REGION}${RESET}"

gcloud config set run/region "$REGION" >/dev/null 2>&1

# ====== CONFIG VARIABLES ======
FUNCTION_NAME="nodejs-pubsub-function"
TOPIC="cf-demo"
BUCKET="${PROJECT_ID}-bucket"
SERVICE_ACCOUNT="cloudfunctionsa@${PROJECT_ID}.iam.gserviceaccount.com"

echo -e "${BLUE}🧭 Using:
  Function: ${FUNCTION_NAME}
  Topic:    ${TOPIC}
  Bucket:   ${BUCKET}
  SA:       ${SERVICE_ACCOUNT}${RESET}
"

# ====== ENSURE PUB/SUB TOPIC EXISTS ======
echo -e "${BLUE}🔎 Ensuring Pub/Sub topic exists...${RESET}"
if ! gcloud pubsub topics describe "$TOPIC" >/dev/null 2>&1; then
  echo -e "${YELLOW}• Topic '${TOPIC}' not found. Creating it...${RESET}"
  gcloud pubsub topics create "$TOPIC" >/dev/null
else
  echo -e "${GREEN}• Topic '${TOPIC}' already exists.${RESET}"
fi

# ====== ENSURE STAGING BUCKET EXISTS (OPTIONAL BUT HELPFUL) ======
echo -e "${BLUE}🔎 Ensuring staging bucket exists...${RESET}"
if ! gsutil ls -b "gs://${BUCKET}" >/dev/null 2>&1; then
  echo -e "${YELLOW}• Bucket 'gs://${BUCKET}' not found. Creating it in ${REGION}...${RESET}"
  gsutil mb -l "$REGION" "gs://${BUCKET}"
else
  echo -e "${GREEN}• Bucket 'gs://${BUCKET}' already exists.${RESET}"
fi

# ====== CREATE SOURCE DIRECTORY ======
echo -e "${BLUE}📂 Creating source directory...${RESET}"
mkdir -p gcf_hello_world
cd gcf_hello_world

# ====== CREATE index.js ======
echo -e "${BLUE}✏️  Writing index.js...${RESET}"
cat << 'EOF' > index.js
const functions = require('@google-cloud/functions-framework');

// CloudEvent function triggered by Pub/Sub
functions.cloudEvent('helloPubSub', cloudEvent => {
  const base64name = cloudEvent.data?.message?.data;
  const name = base64name
    ? Buffer.from(base64name, 'base64').toString()
    : 'World';

  console.log(`Hello, ${name}!`);
});
EOF

# ====== CREATE package.json ======
echo -e "${BLUE}📦 Writing package.json...${RESET}"
cat << 'EOF' > package.json
{
  "name": "gcf_hello_world",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

# ====== INSTALL DEPENDENCIES ======
echo -e "${CYAN}📥 Installing npm dependencies...${RESET}"
npm install

# ====== DEPLOY FUNCTION ======
echo -e "${CYAN}☁️  Deploying Cloud Functions Gen2 service...${RESET}"
gcloud functions deploy "$FUNCTION_NAME" \
  --gen2 \
  --runtime=nodejs20 \
  --region="$REGION" \
  --source=. \
  --entry-point=helloPubSub \
  --trigger-topic="$TOPIC" \
  --stage-bucket="$BUCKET" \
  --service-account="$SERVICE_ACCOUNT" \
  --allow-unauthenticated

echo -e "${GREEN}✅ Deployment completed.${RESET}"

# ====== TEST FUNCTION ======
echo -e "${BLUE}📨 Publishing a test message to Pub/Sub...${RESET}"
gcloud pubsub topics publish "$TOPIC" --message="Cloud Function Gen2"

# ====== VIEW LOGS ======
echo -e "${YELLOW}📜 Fetching logs (if none appear yet, try again in 1–3 minutes)...${RESET}"
gcloud functions logs read "$FUNCTION_NAME" --region="$REGION"

echo -e "${GREEN}🎉 DONE! Your Cloud Run Functions Gen2 service is deployed, triggered via Pub/Sub, and logs were fetched.${RESET}"
echo -e "${RED}🎉 Copyright by ePlus.DEV.${RESET}"