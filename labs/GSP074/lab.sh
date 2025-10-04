#!/bin/bash
# =============================================================
# ✨ Author: ePlus.DEV
# 🧑‍💻 Copyright (c) 2025 ePlus.DEV - All Rights Reserved
# =============================================================

# 🌈 Color definitions
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${CYAN}"
echo "============================================================="
echo "🚀 Google App Engine Hello World Deployment (Go Runtime)"
echo "📦 Script by ePlus.DEV | © 2025 All Rights Reserved"
echo "============================================================="
echo -e "${RESET}"

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")


gcloud config set compute/region $REGION


gsutil mb gs://$DEVSHELL_PROJECT_ID

curl https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Ada_Lovelace_portrait.jpg/800px-Ada_Lovelace_portrait.jpg --output ada.jpg

gsutil cp ada.jpg gs://$DEVSHELL_PROJECT_ID

gsutil cp -r gs://$DEVSHELL_PROJECT_ID/ada.jpg .

gsutil cp gs://$DEVSHELL_PROJECT_ID/ada.jpg gs://$DEVSHELL_PROJECT_ID/image-folder/

gsutil acl ch -u AllUsers:R gs://$DEVSHELL_PROJECT_ID/ada.jpg

# 📜 10. Done
echo -e "${CYAN}"
echo "============================================================="
echo "🎉 Deployment complete!"
echo "🌍 Check your browser — you should see the 'Hello, World!' page."
echo "✨ Script finished by ePlus.DEV - https://eplus.dev"
echo "============================================================="
echo -e "${RESET}"