#!/bin/bash
set -euo pipefail

# Auto get active project ID
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "❌ Project ID not found (gcloud project is not set)."
  echo "👉 Run: gcloud config set project <PROJECT_ID>"
  exit 1
fi

echo "✅ Project ID: $PROJECT_ID"

BUCKET="qwiklabs-gcp-04-8d65fa4b2736-bucket"

echo "✅ Bucket: $BUCKET"
echo "----------------------------------------"

echo "1) Configuring static website hosting..."
gcloud storage buckets update "gs://$BUCKET" \
  --web-main-page-suffix="index.html" \
  --web-error-page="error.html"

echo "2) Making the bucket publicly accessible..."
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="allUsers" \
  --role="roles/storage.objectViewer" >/dev/null

echo "3) Verifying website configuration..."
gcloud storage buckets describe "gs://$BUCKET" \
  --format="value(website.mainPageSuffix,website.notFoundPage)" | cat

echo
echo "✅ DONE!"
echo "Website URL:"
echo "https://storage.googleapis.com/$BUCKET/index.html"
