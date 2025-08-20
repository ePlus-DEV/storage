#!/usr/bin/env bash
set -euo pipefail

# =========================
# ePlus.dev — Memories Challenge (Full Auto)
# =========================

# ---- Pretty colors ----
BOLD="\033[1m"; RESET="\033[0m"
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
BLUE="\033[34m"; MAGENTA="\033[35m"; CYAN="\033[36m"

echo -e "${MAGENTA}${BOLD}
┌─────────────────────────────────────────────────────────┐
│           ePlus.dev — Memories Challenge Setup          │
└─────────────────────────────────────────────────────────┘${RESET}"

# ---- Vars (edit here if lab gives different names) ----
REGION="us-east1"
BUCKET="memories-bucket-qwiklabs-gcp-00-3497a63f19ff"
TOPIC="memories-topic-572"
FUNCTION="memories-thumbnail-generator"
RUNTIME="nodejs22"

# ---- Pre-flight checks ----
command -v gcloud >/dev/null || { echo -e "${RED}gcloud not found. Install Cloud SDK.${RESET}"; exit 1; }
command -v gsutil >/dev/null || { echo -e "${RED}gsutil not found. Install Cloud SDK (components).${RESET}"; exit 1; }
command -v curl   >/dev/null || { echo -e "${RED}curl not found. Please install curl.${RESET}"; exit 1; }

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo -e "${YELLOW}No project set. Run:${RESET} ${BOLD}gcloud config set project <PROJECT_ID>${RESET}"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

echo -e "${BLUE}Project:${RESET} ${BOLD}${PROJECT_ID}${RESET}"
echo -e "${BLUE}Region :${RESET} ${BOLD}${REGION}${RESET}"
echo -e "${BLUE}Bucket :${RESET} ${BOLD}${BUCKET}${RESET}"
echo -e "${BLUE}Topic  :${RESET} ${BOLD}${TOPIC}${RESET}"
echo -e "${BLUE}Func   :${RESET} ${BOLD}${FUNCTION}${RESET}"
echo

# =========================
# 0) Enable required APIs
# =========================
echo -e "${BOLD}🔧 Enabling required APIs...${RESET}"
gcloud services enable \
  cloudfunctions.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  pubsub.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  sts.googleapis.com \
  storage.googleapis.com
echo -e "${GREEN}✅ APIs enabled.${RESET}"
echo

# =========================
# 1) Force-create service identities (prevents 'gcf-admin-robot not found')
# =========================
echo -e "${BOLD}👤 Ensuring service identities exist...${RESET}"
gcloud beta services identity create --service=cloudfunctions.googleapis.com --project="$PROJECT_ID" || true
gcloud beta services identity create --service=eventarc.googleapis.com        --project="$PROJECT_ID" || true
gcloud beta services identity create --service=pubsub.googleapis.com          --project="$PROJECT_ID" || true
echo -e "${GREEN}✅ Service identities ensured.${RESET}"
echo

# =========================
# 2) Grant required IAM roles
# =========================
echo -e "${BOLD}🔐 Granting IAM roles to service agents...${RESET}"

# Eventarc service agent
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.serviceAgent" >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.eventReceiver" >/dev/null

# Cloud Functions admin robot (token creator)
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcf-admin-robot.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" >/dev/null

# Runtime service account (default compute) needs Pub/Sub + Storage perms
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud pubsub topics add-iam-policy-binding "$TOPIC" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/pubsub.publisher" >/dev/null || true

gsutil iam ch "serviceAccount:${RUNTIME_SA}:roles/storage.objectAdmin" "gs://${BUCKET}" >/dev/null 2>&1 || true

echo -e "${YELLOW}⏳ Waiting 60s for IAM propagation...${RESET}"
sleep 60
echo -e "${GREEN}✅ IAM roles granted.${RESET}"
echo

# =========================
# 3) Task 1 – Create bucket
# =========================
echo -e "${BOLD}🪣 Creating bucket (${BUCKET}) in ${REGION}...${RESET}"
gsutil mb -l "${REGION}" -b on "gs://${BUCKET}" || echo "Bucket may already exist."
echo -e "${GREEN}✅ Bucket ready.${RESET}"
echo

# =========================
# 4) Task 2 – Create Pub/Sub topic
# =========================
echo -e "${BOLD}📣 Creating Pub/Sub topic (${TOPIC})...${RESET}"
gcloud pubsub topics create "${TOPIC}" >/dev/null || echo "Topic may already exist."
echo -e "${GREEN}✅ Topic ready.${RESET}"
echo

# =========================
# 5) Task 3 – Prepare function source (Node.js 22)
# =========================
echo -e "${BOLD}🧩 Preparing Cloud Functions Gen2 source...${RESET}"
SRC_DIR="$(mktemp -d)"
cat > "${SRC_DIR}/index.js" <<'EOF'
const functions = require('@google-cloud/functions-framework');
const { Storage } = require('@google-cloud/storage');
const { PubSub } = require('@google-cloud/pubsub');
const sharp = require('sharp');

functions.cloudEvent('memories-thumbnail-generator', async cloudEvent => {
  const event = cloudEvent.data;

  console.log(`Event: ${JSON.stringify(event)}`);
  console.log(`Hello ${event.bucket}`);

  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64";
  const bucket = new Storage().bucket(bucketName);
  const topicName = "memories-topic-572";
  const pubsub = new PubSub();

  if (fileName.search("64x64_thumbnail") === -1) {
    const filename_split = fileName.split('.');
    const filename_ext = filename_split[filename_split.length - 1].toLowerCase();
    const filename_without_ext = fileName.substring(0, fileName.length - filename_ext.length - 1);

    if (filename_ext === 'png' || filename_ext === 'jpg' || filename_ext === 'jpeg') {
      console.log(`Processing Original: gs://${bucketName}/${fileName}`);
      const gcsObject = bucket.file(fileName);
      const newFilename = `${filename_without_ext}_64x64_thumbnail.${filename_ext}`;
      const gcsNewObject = bucket.file(newFilename);

      try {
        const [buffer] = await gcsObject.download();
        const resizedBuffer = await sharp(buffer)
          .resize(64, 64, { fit: 'inside', withoutEnlargement: true })
          .toFormat(filename_ext)
          .toBuffer();

        await gcsNewObject.save(resizedBuffer, {
          metadata: { contentType: `image/${filename_ext}` },
        });

        console.log(`Success: ${fileName} → ${newFilename}`);

        await pubsub
          .topic(topicName)
          .publishMessage({ data: Buffer.from(newFilename) });

        console.log(`Message published to ${topicName}`);
      } catch (err) {
        console.error(`Error: ${err}`);
      }
    } else {
      console.log(`gs://${bucketName}/${fileName} is not an image I can handle`);
    }
  } else {
    console.log(`gs://${bucketName}/${fileName} already has a thumbnail`);
  }
});
EOF

cat > "${SRC_DIR}/package.json" <<'EOF'
{
  "name": "thumbnails",
  "version": "1.0.0",
  "description": "Create Thumbnail of uploaded image",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^2.0.0",
    "@google-cloud/storage": "^6.11.0",
    "sharp": "^0.32.1"
  },
  "devDependencies": {},
  "engines": { "node": ">=4.3.2" }
}
EOF
echo -e "${GREEN}✅ Source prepared.${RESET}"
echo

# =========================
# 6) Task 3 – Deploy function (Gen2 + Cloud Storage trigger)
# =========================
echo -e "${BOLD}🚀 Deploying function (${FUNCTION})...${RESET}"
gcloud functions deploy "${FUNCTION}" \
  --region="${REGION}" \
  --runtime="${RUNTIME}" \
  --gen2 \
  --entry-point="${FUNCTION}" \
  --source="${SRC_DIR}" \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=${BUCKET}"

echo -e "${GREEN}✅ Function deployed. (Eventarc trigger created)${RESET}"
echo

# =========================
# 7) Task 4 – Test: upload image and verify thumbnail
# =========================
echo -e "${BOLD}🧪 Uploading sample image & checking thumbnail...${RESET}"
TMPIMG="$(mktemp).jpg"
curl -s -o "${TMPIMG}" "https://storage.googleapis.com/cloud-training/arc101/travel.jpg"
gsutil cp "${TMPIMG}" "gs://${BUCKET}/travel.jpg"

echo -e "${YELLOW}⏳ Waiting 15s for the function to process...${RESET}"
sleep 15

echo -e "${BLUE}Listing thumbnails in bucket:${RESET}"
gsutil ls "gs://${BUCKET}/*thumbnail*" || echo "No thumbnail found yet — try again in a few seconds."

echo -e "${BLUE}Recent function logs:${RESET}"
gcloud functions logs read "${FUNCTION}" --region="${REGION}" --limit=100 || true
echo

# ----- Footer -----
YEAR="$(date +%Y)"
echo -e "${MAGENTA}${BOLD}
┌─────────────────────────────────────────────────────────┐
│  © ${YEAR} ePlus.dev — All rights reserved              │
└─────────────────────────────────────────────────────────┘${RESET}"
