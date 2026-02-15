#!/bin/bash

echo "🚀 Starting deployment..."
echo "😼 Agaye code lekar notepad me paste karne wale sirgk : D"
echo "-----------------------------------"

PROJECT_ID=$(gcloud config get-value project)
OLD_BUCKET=${PROJECT_ID}-bucket
NEW_BUCKET=${PROJECT_ID}-new

echo "📌 Project detected: $PROJECT_ID"
echo "📦 Old bucket: $OLD_BUCKET"
echo "🆕 New bucket: $NEW_BUCKET"
echo "-----------------------------------"

echo "🪣 Creating new Cloud Storage bucket..."
gsutil mb gs://$NEW_BUCKET

echo "🌐 Enabling website configuration (index & error pages)..."
gsutil web set -m index.html -e error.html gs://$NEW_BUCKET

echo "🔓 Making bucket public..."
gsutil iam ch allUsers:roles/storage.admin gs://$NEW_BUCKET

echo "🔄 Syncing data from old bucket to new bucket..."
gsutil -m rsync -r gs://$OLD_BUCKET gs://$NEW_BUCKET

echo "⚙️ Creating backend bucket with CDN enabled..."
gcloud compute backend-buckets create backend-new \
  --gcs-bucket-name=$NEW_BUCKET \
  --enable-cdn

echo "🗺️ Creating URL map..."
gcloud compute url-maps create website-map \
  --default-backend-bucket=backend-new

echo "🎯 Creating HTTP proxy..."
gcloud compute target-http-proxies create website-proxy \
  --url-map=website-map

echo "🌍 Creating global forwarding rule on port 80..."
gcloud compute forwarding-rules create website-rule \
  --global \
  --target-http-proxy=website-proxy \
  --ports=80

echo "-----------------------------------"
echo "✅ Deployment completed successfully!"
echo "😎 Copy cat strikes again : D"