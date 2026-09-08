#!/bin/bash

# ============================================================
# Pet Theory - Cloud Run PDF Converter Lab
# Automated Lab Script
#
# Copyright © ePlus.DEV
# ============================================================

set -Eeuo pipefail

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------
BLACK=$'\033[0;90m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'

RESET=$'\033[0m'
BOLD=$'\033[1m'

# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------
header() {
  clear
  echo
  echo "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo "${CYAN}${BOLD}║           PET THEORY - CLOUD RUN PDF CONVERTER              ║${RESET}"
  echo "${CYAN}${BOLD}╠══════════════════════════════════════════════════════════════╣${RESET}"
  echo "${MAGENTA}${BOLD}║                     © ePlus.DEV                             ║${RESET}"
  echo "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo
}

section() {
  echo
  echo "${BLUE}${BOLD}==============================================================${RESET}"
  echo "${YELLOW}${BOLD} $1${RESET}"
  echo "${BLUE}${BOLD}==============================================================${RESET}"
}

ok() {
  echo "${GREEN}${BOLD}✓ $1${RESET}"
}

info() {
  echo "${CYAN}➜ $1${RESET}"
}

warn() {
  echo "${YELLOW}⚠ $1${RESET}"
}

fail() {
  echo "${RED}${BOLD}✗ $1${RESET}"
  exit 1
}

retry() {
  local attempts="$1"
  shift

  local count=1

  until "$@"; do
    if (( count >= attempts )); then
      return 1
    fi

    warn "Command failed. Retrying ($count/$attempts)..."
    sleep 5
    ((count++))
  done
}

header

# ============================================================
# PROJECT INFORMATION
# ============================================================

section "Detecting Google Cloud environment"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  fail "Unable to detect PROJECT_ID."
fi

export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"

PROJECT_NUMBER="$(
  gcloud projects describe "$PROJECT_ID" \
    --format="value(projectNumber)" 2>/dev/null || true
)"

if [[ -z "$PROJECT_NUMBER" ]]; then
  fail "Unable to detect PROJECT_NUMBER."
fi

# ------------------------------------------------------------
# AUTO DETECT REGION
# Priority:
# 1. Existing pdf-converter Cloud Run service
# 2. project metadata default region
# 3. gcloud configured compute region
# 4. lab-required fallback us-west1
# ------------------------------------------------------------

REGION=""

REGION="$(
  gcloud run services list \
    --platform=managed \
    --filter="metadata.name=pdf-converter" \
    --format="value(metadata.labels['cloud.googleapis.com/location'])" \
    2>/dev/null | head -n1 || true
)"

if [[ -z "$REGION" ]]; then
  REGION="$(
    gcloud compute project-info describe \
      --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
      2>/dev/null || true
  )"
fi

if [[ -z "$REGION" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"

  if [[ "$REGION" == "(unset)" ]]; then
    REGION=""
  fi
fi

# This specific lab explicitly uses us-west1.
if [[ -z "$REGION" ]]; then
  REGION="us-west1"
  warn "No project default region found."
  info "Using lab-required fallback region: $REGION"
fi

# ------------------------------------------------------------
# AUTO DETECT ZONE
# Zone is not actually required by this Cloud Run lab,
# but we detect it as requested.
# ------------------------------------------------------------

ZONE="$(
  gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
    2>/dev/null || true
)"

if [[ -z "$ZONE" ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"

  if [[ "$ZONE" == "(unset)" ]]; then
    ZONE=""
  fi
fi

if [[ -z "$ZONE" ]]; then
  ZONE="${REGION}-a"
  warn "No default zone exists. Using display fallback: $ZONE"
fi

UPLOAD_BUCKET="${PROJECT_ID}-upload"
PROCESSED_BUCKET="${PROJECT_ID}-processed"

SERVICE_NAME="pdf-converter"
TOPIC_NAME="new-doc"
SUBSCRIPTION_NAME="pdf-conv-sub"
INVOKER_SA_NAME="pubsub-cloud-run-invoker"
INVOKER_SA="${INVOKER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo
echo "${WHITE}${BOLD}Project information${RESET}"
echo "  Project ID     : ${GREEN}${PROJECT_ID}${RESET}"
echo "  Project Number : ${GREEN}${PROJECT_NUMBER}${RESET}"
echo "  Region         : ${GREEN}${REGION}${RESET}"
echo "  Zone           : ${GREEN}${ZONE}${RESET}"
echo "  Upload bucket  : ${GREEN}${UPLOAD_BUCKET}${RESET}"
echo "  PDF bucket     : ${GREEN}${PROCESSED_BUCKET}${RESET}"
echo

# Keep gcloud defaults consistent with detected values.
gcloud config set compute/region "$REGION" >/dev/null 2>&1 || true
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1 || true

# ============================================================
# TASK 2
# ============================================================

section "Task 2 - Enable required APIs"

APIS=(
  run.googleapis.com
  cloudbuild.googleapis.com
  pubsub.googleapis.com
  storage.googleapis.com
  artifactregistry.googleapis.com
  containerregistry.googleapis.com
  iam.googleapis.com
)

gcloud services enable "${APIS[@]}" \
  --project="$PROJECT_ID" \
  --quiet

ok "Required APIs enabled"

# Give service agents a moment to initialize.
sleep 5

# ============================================================
# TASK 3 - SOURCE CODE
# ============================================================

section "Task 3 - Clone Pet Theory repository"

cd "$HOME"

if [[ -d pet-theory ]]; then
  info "Existing pet-theory directory found."
  info "Refreshing repository..."

  cd pet-theory
  git reset --hard HEAD >/dev/null 2>&1 || true
  git clean -fd >/dev/null 2>&1 || true
  git pull --ff-only >/dev/null 2>&1 || true
else
  git clone https://github.com/rosera/pet-theory.git
  cd pet-theory
fi

cd lab03

ok "Repository ready: $(pwd)"

# ------------------------------------------------------------
# package.json
# ------------------------------------------------------------

section "Configuring Node.js application"

# Use npm pkg so we preserve the package.json supplied by Google.
npm pkg set scripts.start="node index.js"

npm install express body-parser @google-cloud/storage

# child_process is a Node.js built-in module.
# No third-party package is required for modern Node.js.

ok "Node.js dependencies installed"

echo
info "package.json start command:"
npm pkg get scripts.start

# ============================================================
# FIRST BUILD
# Required by Task 3
# ============================================================

section "Task 3 - Build simple REST API"

retry 3 gcloud builds submit \
  --tag "gcr.io/${PROJECT_ID}/pdf-converter" \
  --project="$PROJECT_ID" \
  --quiet

ok "First Cloud Build completed"

# ------------------------------------------------------------
# FIRST DEPLOY
# ------------------------------------------------------------

section "Task 3 - Deploy first Cloud Run revision"

retry 3 gcloud run deploy "$SERVICE_NAME" \
  --image "gcr.io/${PROJECT_ID}/pdf-converter" \
  --platform managed \
  --region "$REGION" \
  --project "$PROJECT_ID" \
  --no-allow-unauthenticated \
  --max-instances=1 \
  --quiet

SERVICE_URL="$(
  gcloud run services describe "$SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)"
)"

[[ -n "$SERVICE_URL" ]] || fail "Cloud Run SERVICE_URL could not be detected."

ok "Cloud Run service deployed"
echo
echo "${CYAN}Service URL:${RESET}"
echo "${GREEN}${SERVICE_URL}${RESET}"

# ------------------------------------------------------------
# TEST FIRST SERVICE
# ------------------------------------------------------------

section "Testing authenticated Cloud Run request"

HTTP_RESPONSE="$(
  curl -sS \
    -X POST \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    "$SERVICE_URL" || true
)"

echo "$HTTP_RESPONSE"

if echo "$HTTP_RESPONSE" | grep -q "OK"; then
  ok "Authenticated Cloud Run invocation succeeded"
else
  warn "Service responded, but response did not contain OK."
fi

# ============================================================
# TASK 4 - STORAGE BUCKETS
# ============================================================

section "Task 4 - Create Cloud Storage buckets"

if gcloud storage buckets describe "gs://${UPLOAD_BUCKET}" >/dev/null 2>&1; then
  info "Bucket already exists: gs://${UPLOAD_BUCKET}"
else
  gcloud storage buckets create \
    "gs://${UPLOAD_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="$REGION"
fi

if gcloud storage buckets describe "gs://${PROCESSED_BUCKET}" >/dev/null 2>&1; then
  info "Bucket already exists: gs://${PROCESSED_BUCKET}"
else
  gcloud storage buckets create \
    "gs://${PROCESSED_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="$REGION"
fi

ok "Storage buckets ready"

# ============================================================
# STORAGE NOTIFICATION
# ============================================================

section "Task 4 - Configure Cloud Storage Pub/Sub notification"

# Check whether a notification for new-doc already exists.
NOTIFICATION_FOUND="$(
  gcloud storage buckets notifications list \
    "gs://${UPLOAD_BUCKET}" \
    --format="value(topic)" 2>/dev/null \
    | grep "/topics/${TOPIC_NAME}$" \
    | head -n1 || true
)"

if [[ -n "$NOTIFICATION_FOUND" ]]; then
  info "Storage notification for ${TOPIC_NAME} already exists."
else
  gcloud storage buckets notifications create \
    "gs://${UPLOAD_BUCKET}" \
    --topic="$TOPIC_NAME" \
    --payload-format=json \
    --event-types=OBJECT_FINALIZE

  ok "Storage OBJECT_FINALIZE notification created"
fi

# Ensure Pub/Sub topic exists even if a previous notification was partially created.
if ! gcloud pubsub topics describe "$TOPIC_NAME" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  gcloud pubsub topics create "$TOPIC_NAME" \
    --project="$PROJECT_ID"
fi

# ============================================================
# SERVICE ACCOUNT
# ============================================================

section "Task 4 - Configure Pub/Sub Cloud Run invoker"

if gcloud iam service-accounts describe "$INVOKER_SA" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  info "Service account already exists: $INVOKER_SA"
else
  gcloud iam service-accounts create "$INVOKER_SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="PubSub Cloud Run Invoker"
fi

gcloud run services add-iam-policy-binding "$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --member="serviceAccount:${INVOKER_SA}" \
  --role="roles/run.invoker" \
  --quiet

ok "Invoker permission configured"

# ============================================================
# PUB/SUB SERVICE IDENTITY
# ============================================================

section "Task 4 - Configure Pub/Sub service identity"

gcloud beta services identity create \
  --service=pubsub.googleapis.com \
  --project="$PROJECT_ID" \
  >/dev/null

PUBSUB_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PUBSUB_SERVICE_AGENT}" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --quiet

ok "Pub/Sub Token Creator permission configured"

# ============================================================
# PUSH SUBSCRIPTION
# ============================================================

section "Task 4 - Create Pub/Sub push subscription"

if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  info "Existing subscription found."
  info "Recreating it to guarantee the correct push configuration..."

  gcloud pubsub subscriptions delete "$SUBSCRIPTION_NAME" \
    --project="$PROJECT_ID" \
    --quiet
fi

gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
  --project="$PROJECT_ID" \
  --topic="$TOPIC_NAME" \
  --push-endpoint="$SERVICE_URL" \
  --push-auth-service-account="$INVOKER_SA"

ok "Pub/Sub push subscription created"

# ============================================================
# TASK 5
# Test initial event delivery
# ============================================================

section "Task 5 - Test upload event"

info "Copying Google-provided test files..."

gcloud storage cp \
  "gs://spls/gsp644/*" \
  "gs://${UPLOAD_BUCKET}"

info "Allowing Pub/Sub events to reach Cloud Run..."
sleep 10

echo
info "Recent Cloud Run logs:"
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}" \
  --project="$PROJECT_ID" \
  --limit=10 \
  --format="value(textPayload)" \
  2>/dev/null || true

echo
info "Cleaning upload bucket before PDF converter deployment..."

gcloud storage rm "gs://${UPLOAD_BUCKET}/*" 2>/dev/null || true

ok "Initial Pub/Sub trigger test completed"

# ============================================================
# TASK 6 - FULL PDF CONVERTER
# ============================================================

section "Task 6 - Update Dockerfile with LibreOffice"

cat > Dockerfile <<'DOCKERFILE'
FROM node:22-slim

RUN apt-get update -y \
    && apt-get install -y libreoffice \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

COPY package.json package*.json ./

RUN npm install --only=production

COPY . .

CMD [ "npm", "start" ]
DOCKERFILE

ok "Dockerfile updated"

# ============================================================
# FULL INDEX.JS
#
# Important fix:
# Google lab example uses fs.promises but misses:
# const fs = require("fs");
# ============================================================

section "Task 6 - Install complete PDF converter code"

cat > index.js <<'NODEJS'
const fs = require("fs");
const { promisify } = require("util");
const { Storage } = require("@google-cloud/storage");
const exec = promisify(require("child_process").exec);
const storage = new Storage();

const express = require("express");
const bodyParser = require("body-parser");

const app = express();

app.use(bodyParser.json());

const port = process.env.PORT || 8080;

app.listen(port, () => {
  console.log("Listening on port", port);
});

app.post("/", async (req, res) => {
  try {
    /*
     * Manual authenticated curl requests used by this lab don't contain
     * a Pub/Sub message, so return OK instead of throwing an error.
     */
    if (!req.body || !req.body.message || !req.body.message.data) {
      console.log("No Pub/Sub payload received.");
      res.set("Content-Type", "text/plain");
      res.send("\n\nOK\n\n");
      return;
    }

    const file = decodeBase64Json(req.body.message.data);

    console.log(`file: ${JSON.stringify(file)}`);

    await downloadFile(file.bucket, file.name);

    const pdfFileName = await convertFile(file.name);

    await uploadFile(process.env.PDF_BUCKET, pdfFileName);

    await deleteFile(file.bucket, file.name);
  } catch (ex) {
    console.log(`Error: ${ex}`);
  }

  res.set("Content-Type", "text/plain");
  res.send("\n\nOK\n\n");
});

function decodeBase64Json(data) {
  return JSON.parse(Buffer.from(data, "base64").toString());
}

// Helper function to check file existence.
async function fileExists(filePath) {
  try {
    await fs.promises.access(filePath);
    return true;
  } catch (err) {
    return false;
  }
}

async function downloadFile(bucketName, fileName) {
  const localPath = `/tmp/${fileName}`;

  const existsLocally = await fileExists(localPath);

  if (existsLocally) {
    console.log(`File exists locally. Deleting: ${fileName}`);

    await fs.promises.unlink(localPath);

    console.log("File deleted.");
  } else {
    console.log(`File does not exist locally: ${fileName}`);
  }

  const options = {
    destination: localPath,
  };

  await storage
    .bucket(bucketName)
    .file(fileName)
    .download(options);

  console.log(`File downloaded: ${fileName}`);
}

async function convertFile(fileName) {
  const cmd =
    "libreoffice --headless --convert-to pdf --outdir /tmp " +
    `"/tmp/${fileName}"`;

  console.log(cmd);

  const { stdout, stderr } = await exec(cmd);

  if (stderr) {
    console.log(`LibreOffice stderr: ${stderr}`);
  }

  console.log(`Conversion Success: ${stdout}`);

  const pdfFileName = fileName.replace(/\.\w+$/, ".pdf");

  return pdfFileName;
}

async function deleteFile(bucketName, fileName) {
  await storage
    .bucket(bucketName)
    .file(fileName)
    .delete();

  console.log(`Original file deleted from bucket: ${fileName}`);
}

async function uploadFile(bucketName, fileName) {
  await storage
    .bucket(bucketName)
    .upload(`/tmp/${fileName}`);

  console.log(`PDF uploaded: gs://${bucketName}/${fileName}`);
}
NODEJS

ok "index.js updated"

# Syntax check before spending time on Cloud Build.
node --check index.js

ok "Node.js syntax check passed"

# ============================================================
# SECOND BUILD
# ============================================================

section "Task 6 - Build LibreOffice PDF converter"

info "This build contains LibreOffice and is larger than the first build."

retry 3 gcloud builds submit \
  --tag "gcr.io/${PROJECT_ID}/pdf-converter" \
  --project="$PROJECT_ID" \
  --quiet

ok "Second Cloud Build completed"

# ============================================================
# SECOND DEPLOY
# ============================================================

section "Task 6 - Deploy new Cloud Run revision"

retry 3 gcloud run deploy "$SERVICE_NAME" \
  --image "gcr.io/${PROJECT_ID}/pdf-converter" \
  --platform managed \
  --region "$REGION" \
  --project="$PROJECT_ID" \
  --memory=2Gi \
  --no-allow-unauthenticated \
  --max-instances=1 \
  --set-env-vars="PDF_BUCKET=${PROCESSED_BUCKET}" \
  --quiet

SERVICE_URL="$(
  gcloud run services describe "$SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)"
)"

ok "Latest Cloud Run revision deployed"

# ============================================================
# RECHECK SUBSCRIPTION
# Cloud Run service URL normally remains stable, but explicitly
# recreate push subscription so the final config is guaranteed.
# ============================================================

section "Refreshing Pub/Sub push endpoint"

gcloud pubsub subscriptions delete "$SUBSCRIPTION_NAME" \
  --project="$PROJECT_ID" \
  --quiet \
  >/dev/null 2>&1 || true

gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
  --project="$PROJECT_ID" \
  --topic="$TOPIC_NAME" \
  --push-endpoint="$SERVICE_URL" \
  --push-auth-service-account="$INVOKER_SA"

ok "Push endpoint refreshed"

# ============================================================
# TASK 7 TEST SERVICE
# ============================================================

section "Task 7 - Test updated PDF converter"

HTTP_RESPONSE="$(
  curl -sS \
    -X POST \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    "$SERVICE_URL" || true
)"

echo "$HTTP_RESPONSE"

if echo "$HTTP_RESPONSE" | grep -q "OK"; then
  ok "PDF converter service returned OK"
else
  warn "Cloud Run request did not return expected OK."
fi

# ============================================================
# CREATE GOOGLE LAB COPY SCRIPT
# ============================================================

section "Task 7 - Create test upload script"

cat > copy_files.sh <<COPY_SCRIPT
#!/bin/bash

SOURCE_BUCKET="gs://spls/gsp644"
DESTINATION_BUCKET="gs://${UPLOAD_BUCKET}"
DELAY=5

files=\$(gcloud storage ls "\$SOURCE_BUCKET")

for file in \$files; do
  source_file_path="\$file"

  gcloud storage cp "\$source_file_path" "\$DESTINATION_BUCKET"

  if [ \$? -eq 0 ]; then
    echo "Copied: \$source_file_path to \$DESTINATION_BUCKET"
  else
    echo "Failed to copy: \$source_file_path"
  fi

  sleep \$DELAY
done

echo "All files copied!"
COPY_SCRIPT

chmod +x copy_files.sh

ok "copy_files.sh created"

# ============================================================
# RUN TEST CONVERSIONS
# ============================================================

section "Task 7 - Upload files for PDF conversion"

# Clean processed bucket so final verification is clear.
gcloud storage rm "gs://${PROCESSED_BUCKET}/*" \
  >/dev/null 2>&1 || true

bash copy_files.sh

# ============================================================
# WAIT FOR CONVERSION
# ============================================================

section "Waiting for PDF conversion"

for i in {1..18}; do

  PDF_COUNT="$(
    gcloud storage ls "gs://${PROCESSED_BUCKET}/" \
      2>/dev/null \
      | grep -ci '\.pdf$' || true
  )"

  UPLOAD_COUNT="$(
    gcloud storage ls "gs://${UPLOAD_BUCKET}/" \
      2>/dev/null \
      | wc -l || true
  )"

  echo -ne "\r${CYAN}PDF files: ${PDF_COUNT} | Remaining uploads: ${UPLOAD_COUNT} | Check ${i}/18${RESET}   "

  if [[ "$PDF_COUNT" -gt 0 && "$UPLOAD_COUNT" -eq 0 ]]; then
    break
  fi

  sleep 5
done

echo
echo

# ============================================================
# FINAL VERIFICATION
# ============================================================

section "Final verification"

echo "${WHITE}${BOLD}Cloud Run:${RESET}"

gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format="table(
    metadata.name:label=SERVICE,
    status.latestReadyRevisionName:label=REVISION,
    status.url:label=URL
  )"

echo
echo "${WHITE}${BOLD}Pub/Sub subscription:${RESET}"

gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" \
  --project="$PROJECT_ID" \
  --format="yaml(
    name,
    topic,
    pushConfig.pushEndpoint,
    pushConfig.oidcToken.serviceAccountEmail
  )"

echo
echo "${WHITE}${BOLD}Upload bucket:${RESET}"
gcloud storage ls "gs://${UPLOAD_BUCKET}/" 2>/dev/null || \
  echo "(empty - expected after successful conversion)"

echo
echo "${WHITE}${BOLD}Processed PDF files:${RESET}"
gcloud storage ls "gs://${PROCESSED_BUCKET}/" 2>/dev/null || true

echo
echo "${WHITE}${BOLD}Recent converter logs:${RESET}"

gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}" \
  --project="$PROJECT_ID" \
  --limit=20 \
  --format="value(timestamp,textPayload)" \
  2>/dev/null || true

# ============================================================
# SUMMARY
# ============================================================

echo
echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo "${GREEN}${BOLD}║                   LAB SCRIPT COMPLETED                     ║${RESET}"
echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

echo
echo "${CYAN}${BOLD}Project:${RESET}"
echo "  ${PROJECT_ID}"

echo
echo "${CYAN}${BOLD}Region:${RESET}"
echo "  ${REGION}"

echo
echo "${CYAN}${BOLD}Cloud Run service:${RESET}"
echo "  ${SERVICE_URL}"

echo
echo "${CYAN}${BOLD}Upload bucket:${RESET}"
echo "  gs://${UPLOAD_BUCKET}"

echo
echo "${CYAN}${BOLD}Processed bucket:${RESET}"
echo "  gs://${PROCESSED_BUCKET}"

echo
echo "${CYAN}${BOLD}Google Cloud Console links:${RESET}"
echo
echo "Cloud Run:"
echo "https://console.cloud.google.com/run/detail/${REGION}/${SERVICE_NAME}?project=${PROJECT_ID}"
echo
echo "Cloud Storage:"
echo "https://console.cloud.google.com/storage/browser?project=${PROJECT_ID}"
echo
echo "Cloud Logging:"
echo "https://console.cloud.google.com/logs/query?project=${PROJECT_ID}"
echo
echo "Cloud Build:"
echo "https://console.cloud.google.com/cloud-build/builds?project=${PROJECT_ID}"

echo
echo "${MAGENTA}${BOLD}                 © ePlus.DEV${RESET}"
echo