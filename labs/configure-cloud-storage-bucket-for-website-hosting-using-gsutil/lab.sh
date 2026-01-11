#!/bin/bash
set -e

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  echo "❌ No active project. Run: gcloud config set project <PROJECT_ID>"
  exit 1
fi

echo "✅ Project: $PROJECT_ID"

# Auto find bucket chứa qwiklabs-gcp-* -bucket (phù hợp lab dạng bạn đưa)
BUCKET="$(gcloud storage buckets list --format="value(name)" | grep -E '^qwiklabs-gcp-.*-bucket$' | head -n 1)"

if [ -z "$BUCKET" ]; then
  echo "❌ Cannot auto-detect bucket qwiklabs-gcp-*-bucket"
  echo "👉 Buckets found:"
  gcloud storage buckets list --format="value(name)"
  exit 1
fi

echo "✅ Bucket detected: $BUCKET"

echo "🔧 Configure website hosting..."
gcloud storage buckets update "gs://$BUCKET" \
  --web-main-page-suffix="index.html" \
  --web-error-page="error.html"

echo "🌍 Make bucket public (allUsers objectViewer)..."
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="allUsers" \
  --role="roles/storage.objectViewer" >/dev/null

echo "📦 Objects:"
gcloud storage ls "gs://$BUCKET" || true

echo ""
echo "✅ DONE!"
echo "Website URLs:"
echo "  https://storage.googleapis.com/$BUCKET/index.html"
echo "  https://storage.googleapis.com/$BUCKET/error.html"
echo "Test 404:"
echo "  https://storage.googleapis.com/$BUCKET/does-not-exist"