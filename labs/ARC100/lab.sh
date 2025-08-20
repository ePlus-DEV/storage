#!/usr/bin/env bash
set -euo pipefail

# ===== Lab variables (edit only if your lab gives different names) =====
REGION="us-east1"
BUCKET="memories-bucket-qwiklabs-gcp-00-3497a63f19ff"
TOPIC="memories-topic-572"
FUNCTION="memories-thumbnail-generator"
RUNTIME="nodejs22"

echo "Project: $(gcloud config get-value project)"
echo "Region : ${REGION}"
echo "Bucket : ${BUCKET}"
echo "Topic  : ${TOPIC}"
echo "Func   : ${FUNCTION}"
echo

# 0) Enable required APIs
gcloud services enable \
  cloudfunctions.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  pubsub.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com

# 1) Task 1 – Create bucket (us-east1)
gsutil mb -l ${REGION} -b on gs://${BUCKET} || echo "Bucket may already exist"

# 2) Task 2 – Create Pub/Sub topic
gcloud pubsub topics create ${TOPIC} || echo "Topic may already exist"

# 3) Task 3 – Prepare function source (Gen2, Node.js 22, Cloud Storage trigger)
WORKDIR="$(mktemp -d)"
cat > "${WORKDIR}/index.js" <<'EOF'
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

cat > "${WORKDIR}/package.json" <<'EOF'
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

# Deploy Cloud Functions Gen2 with Cloud Storage trigger (object finalize on the target bucket)
gcloud functions deploy "${FUNCTION}" \
  --region="${REGION}" \
  --runtime="${RUNTIME}" \
  --gen2 \
  --entry-point="${FUNCTION}" \
  --source="${WORKDIR}" \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=${BUCKET}"

echo "Function deployed. If the UI requested role/API grants, wait ~1–3 minutes for propagation."

# 4) Task 4 – Test: upload an image and verify thumbnail
TMPIMG="$(mktemp).jpg"
curl -s -o "${TMPIMG}" "https://storage.googleapis.com/cloud-training/arc101/travel.jpg"
gsutil cp "${TMPIMG}" "gs://${BUCKET}/travel.jpg"

echo "Uploaded sample image. Wait a moment, then list thumbnails:"
sleep 10
gsutil ls "gs://${BUCKET}/*thumbnail* " || true

echo "To view logs:"
echo "  gcloud functions logs read ${FUNCTION} --region=${REGION} --limit=100"
