#!/usr/bin/env bash
set -euo pipefail

# 0) Basic config
gcloud config set compute/region "${REGION}"
export PROJECT_ID="$(gcloud config get-value project)"

echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Bucket  : $BUCKET_NAME"
echo "Topic   : $TOPIC_NAME"
echo "Func    : $FUNCTION_NAME"

# 1) Enable required APIs
gcloud services enable \
  cloudfunctions.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  pubsub.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com

# 2) Create bucket & topic
gsutil mb -l "${REGION}" -b on "gs://${BUCKET_NAME}" || echo "Bucket exists"
gcloud pubsub topics create "${TOPIC_NAME}" || echo "Topic exists"

# 3) Source code
mkdir -p ~/quicklab && cd ~/quicklab
cat > index.js <<'EOF'
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

# sửa topic cho đúng biến môi trường
sed -i "s/memories-topic-572/${TOPIC_NAME}/g" index.js

cat > package.json <<'EOF'
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

# 4) Deploy Cloud Functions Gen2
gcloud functions deploy "${FUNCTION_NAME}" \
  --gen2 \
  --runtime nodejs22 \
  --entry-point "${FUNCTION_NAME}" \
  --source . \
  --region "${REGION}" \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=${BUCKET_NAME}"

# 5) Test upload
curl -s -o travel.jpg "https://storage.googleapis.com/cloud-training/arc101/travel.jpg"
gsutil cp travel.jpg "gs://${BUCKET_NAME}/travel.jpg"

echo -e "\033[1;36m============================================\033[0m"
echo -e "\033[1;36m   Script completed successfully ✅\033[0m"
echo -e "\033[1;36m   © 2025 ePlus.dev — All Rights Reserved\033[0m"
echo -e "\033[1;36m============================================\033[0m"
