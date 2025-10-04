#!/bin/bash
# ==============================================
# 🚀 Google App Engine Hello World Auto Setup
# Author: ePlus.DEV
# Copyright (c) 2025 ePlus.DEV
# ==============================================

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# 🌎 2. Set the region
echo "🌍 Setting region to $REGION..."
gcloud config set compute/region $REGION

# 📡 3. Enable App Engine Admin API
echo "🔧 Enabling App Engine Admin API..."
gcloud services enable appengine.googleapis.com

# 📁 4. Clone the Hello World sample app
echo "📦 Cloning Hello World sample app..."
git clone https://github.com/GoogleCloudPlatform/golang-samples.git

# 🧭 5. Go to the sample directory
cd golang-samples/appengine/go11x/helloworld || { echo "❌ Directory not found"; exit 1; }

# 🔨 6. Install App Engine Go SDK (if required)
echo "🔧 Installing App Engine Go SDK..."
sudo apt-get update -y
sudo apt-get install -y google-cloud-sdk-app-engine-go

# 🚀 7. Deploy the application
echo "🚀 Deploying the app to Google App Engine..."
gcloud app deploy --quiet

# 🌐 8. Open the deployed application
echo "🌐 Opening the deployed app in your browser..."
gcloud app browse

# 📜 9. Done!
echo "🎉 Deployment complete! Check your browser to see 'Hello, World!'"