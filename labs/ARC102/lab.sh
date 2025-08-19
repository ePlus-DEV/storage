#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Copyright (c) 2025 ePlus.DEV${NC}"
echo -e "${CYAN}=====================================${NC}\n"

echo "Please export the values."

# Prompt user to input values
read -p "Enter BUCKET_NAME: " BUCKET_NAME
read -p "Enter TOPIC_NAME: " TOPIC_NAME
read -p "Enter FUNCTION_NAME: " FUNCTION_NAME
read -p "Enter REGION (e.g. us-east4): " REGION

gcloud config set compute/region "$REGION" >/dev/null
export PROJECT_ID="$(gcloud config get-value project -q)"

# --- Enable required APIs ---
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  storage.googleapis.com

# --- Create bucket ---
gsutil mb -l "$REGION" "gs://${BUCKET_NAME}"

# --- Create Pub/Sub topic ---
gcloud pubsub topics create "$TOPIC_NAME"

# --- Resolve identities ---
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
EVENTARC_SA="service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com"
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# --- IAM for Eventarc ---
gsutil iam ch "serviceAccount:${EVENTARC_SA}:roles/storage.admin" "gs://${BUCKET_NAME}"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${EVENTARC_SA}" \
  --role="roles/eventarc.eventReceiver"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${EVENTARC_SA}" \
  --role="roles/pubsub.publisher"

# --- IAM for Function runtime (publish to topic) ---
gcloud pubsub topics add-iam-policy-binding "$TOPIC_NAME" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/pubsub.publisher"

# --- Prepare function source ---
mkdir -p ~/quicklab && cd ~/quicklab

cat > index.js <<'EOF_END'
/**
 * Thumbnail Generator Function
 * Copyright (c) 2025 ePlus.DEV
 */
"use strict";
const { Storage } = require('@google-cloud/storage');
const { PubSub } = require('@google-cloud/pubsub');
const imagemagick = require("imagemagick-stream");

const gcs = new Storage();
const pubsub = new PubSub();

exports.thumbnail = async (event, context) => {
  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64";
  const topicName = process.env.TOPIC_NAME;

  if (!fileName || !bucketName) {
    console.log("Missing event.name or event.bucket");
    return;
  }

  if (fileName.includes("64x64_thumbnail")) {
    console.log(`gs://${bucketName}/${fileName} already has a thumbnail`);
    return;
  }

  const ext = (fileName.split('.').pop() || "").toLowerCase();
  if (ext !== "png" && ext !== "jpg" && ext !== "jpeg") {
    console.log(`gs://${bucketName}/${fileName} is not a supported image type`);
    return;
  }

  console.log(`Processing Original: gs://${bucketName}/${fileName}`);
  const bucket = gcs.bucket(bucketName);
  const src = bucket.file(fileName);

  const filenameWithoutExt = fileName.slice(0, fileName.length - ext.length);
  const newFilename = `${filenameWithoutExt}${size}_thumbnail.${ext}`;
  const dst = bucket.file(newFilename);

  const srcStream = src.createReadStream();
  const dstStream = dst.createWriteStream();
  const resize = imagemagick().resize(size).quality(90);

  await new Promise((resolve, reject) => {
    srcStream.pipe(resize).pipe(dstStream)
      .on("error", reject)
      .on("finish", resolve);
  });

  await dst.setMetadata({ contentType: `image/${ext === "jpg" ? "jpeg" : ext}` });

  try {
    const messageId = await pubsub.topic(topicName)
      .publishMessage({ data: Buffer.from(newFilename) });
    console.log(`Message ${messageId} published to ${topicName}.`);
  } catch (err) {
    console.error("Failed to publish Pub/Sub message:", err);
  }

  console.log(`Success: ${fileName} → ${newFilename}`);
};
EOF_END

cat > package.json <<'EOF_END'
{
  "name": "thumbnails",
  "version": "1.0.0",
  "description": "Create thumbnail of uploaded image",
  "author": "ePlus.DEV",
  "license": "Copyright (c) 2025 ePlus.DEV",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "@google-cloud/pubsub": "^7.0.0",
    "@google-cloud/storage": "^7.12.0",
    "imagemagick-stream": "4.1.1"
  },
  "engines": {
    "node": ">=18"
  }
}
EOF_END

# --- Deploy function ---
gcloud functions deploy "$FUNCTION_NAME" \
  --gen2 \
  --runtime=nodejs20 \
  --entry-point=thumbnail \
  --source=. \
  --region="$REGION" \
  --trigger-bucket="$BUCKET_NAME" \
  --set-env-vars="TOPIC_NAME=${TOPIC_NAME}" \
  --max-instances=5 \
  --quiet

# --- Quick test ---
wget -q https://storage.googleapis.com/cloud-training/arc102/wildlife.jpg -O wildlife.jpg
gsutil cp wildlife.jpg "gs://${BUCKET_NAME}"

echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Congratulations For Completing!!! - ePlus.DEV{NC}"
echo -e "${CYAN}=====================================${NC}\n"