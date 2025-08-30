# ==== Challenge Lab – Commands Only ====
# Region & project
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud config get-value project)
gcloud config set project "$PROJECT_ID"
gcloud config set functions/region "$REGION"
gcloud config set run/region "$REGION"

# Enable required APIs
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com

# ---------- Task 1: Create the bucket ----------
export BUCKET="$PROJECT_ID"
gsutil mb -l "$REGION" "gs://$BUCKET"

# (IAM for GCS -> Pub/Sub so Storage events can reach Eventarc)
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
export GCS_SA="$(gsutil kms serviceaccount -p "$PROJECT_NUMBER")"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$GCS_SA" \
  --role roles/pubsub.publisher


# ---------- Task 2: Cloud Storage function (cs-logger) ----------
mkdir -p ~/cs-logger && cd ~/cs-logger

cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');

functions.cloudEvent('cs-logger', (cloudevent) => {
  console.log('A new event in your Cloud Storage bucket has been logged!');
  console.log(cloudevent);
});
EOF

cat > package.json <<'EOF'
{
  "name": "nodejs-functions-gen2-codelab",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^2.0.0"
  }
}
EOF

gcloud functions deploy cs-logger \
  --gen2 \
  --runtime nodejs20 \
  --entry-point cs-logger \
  --source . \
  --region "$REGION" \
  --trigger-bucket "$BUCKET" \
  --trigger-location "$REGION" \
  --max-instances 2

# Test: upload a file then read logs
echo "hello" > /tmp/test.txt
gsutil cp /tmp/test.txt "gs://$BUCKET/test.txt"
gcloud functions logs read cs-logger --region "$REGION" --gen2 --limit 50 --format "value(log)"


# ---------- Task 3: HTTP function (http-responder) ----------
mkdir -p ~/http-responder && cd ~/http-responder

cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('http-responder', (req, res) => {
  res.status(200).send('HTTP function (2nd gen) has been called!');
});
EOF

cat > package.json <<'EOF'
{
  "name": "nodejs-functions-gen2-codelab",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^2.0.0"
  }
}
EOF

gcloud functions deploy http-responder \
  --gen2 \
  --runtime nodejs20 \
  --entry-point http-responder \
  --source . \
  --region "$REGION" \
  --trigger-http \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 2

# Test HTTP
URL=$(gcloud functions describe http-responder --region "$REGION" --gen2 --format="value(serviceConfig.uri)")
curl -sS "$URL"