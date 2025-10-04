#!/bin/bash
# ==========================================
# 🚀 Google App Engine Hello World Deployment Script
# 📜 Copyright (c) 2025 ePlus.DEV - All Rights Reserved
# ==========================================

# 🎨 Terminal colors
GREEN="\e[32m"
BLUE="\e[36m"
YELLOW="\e[33m"
RED="\e[31m"
BOLD="\e[1m"
RESET="\e[0m"

echo -e "${BOLD}${BLUE}"
echo "============================================================"
echo " 🚀 GOOGLE APP ENGINE HELLO WORLD DEPLOY SCRIPT"
echo " 📜 Copyright (c) 2025 ePlus.DEV - All Rights Reserved"
echo "============================================================"
echo -e "${RESET}"

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# 🛠️ Task 1: Enable App Engine Admin API
echo -e "${YELLOW}🔧 Enabling App Engine Admin API...${RESET}"
gcloud services enable appengine.googleapis.com

# 📁 Task 2: Download the Hello World sample
echo -e "${YELLOW}📦 Cloning Hello World sample repository...${RESET}"
git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git

# 📂 Move into sample folder
cd python-docs-samples/appengine/standard_python3/hello_world || exit

# 🐍 Setup Python virtual environment
echo -e "${YELLOW}🐍 Setting up Python virtual environment...${RESET}"
sudo apt update -y
sudo apt install -y python3-venv
python3 -m venv myenv
source myenv/bin/activate

# 📦 Install Flask
echo -e "${YELLOW}📦 Installing Flask...${RESET}"
pip install Flask

# 🧪 Task 3: Test the Hello World app locally (optional)
echo -e "${BLUE}⚙️  Running original Hello World app locally for 5s...${RESET}"
flask --app main run &
sleep 5
kill $!

# ✏️ Task 4: Modify main.py automatically
echo -e "${YELLOW}✏️ Updating message to 'Hello, Cruel World!'...${RESET}"
sed -i 's/Hello World!/Hello, Cruel World!/g' main.py

# 🧪 Test updated version locally (optional)
echo -e "${BLUE}🔁 Running updated Hello World app locally for 5s...${RESET}"
flask --app main run &
sleep 5
kill $!

# ☁️ Check if App Engine is initialized
echo -e "${YELLOW}☁️ Checking if App Engine application exists...${RESET}"
if ! gcloud app describe >/dev/null 2>&1; then
  echo -e "${BLUE}🌐 Creating new App Engine application in region $REGION...${RESET}"
  gcloud app create --region=$REGION
else
  echo -e "${GREEN}✅ App Engine application already exists.${RESET}"
fi

# ☁️ Task 5: Deploy to App Engine
echo -e "${GREEN}🚀 Deploying the app to Google App Engine...${RESET}"
gcloud app deploy --quiet

# 🌐 Task 6: Open deployed app
echo -e "${BLUE}🌐 Opening deployed app in your browser...${RESET}"
gcloud app browse

echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo " ✅ Deployment completed successfully!"
echo " 🎉 Visit your app URL to see: Hello, Cruel World!"
echo " 📜 Script by ePlus.DEV — All Rights Reserved 2025"
echo "============================================================"
echo -e "${RESET}"