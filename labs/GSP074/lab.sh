#!/bin/bash
set -euo pipefail

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
echo "🚀 Cloud Storage: Qwik Start - CLI/SDK - GSP074"
echo "📦 Script by ePlus.DEV | © 2025 All Rights Reserved"
echo "============================================================="
echo -e "${RESET}"

# Get default region (fallback if empty)
REGION="$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" || true)"

if [[ -z "${REGION}" ]]; then
  echo -e "${YELLOW}⚠️  Could not detect default region. Using 'us-central1'.${RESET}"
  REGION="us-central1"
fi

gcloud config set compute/region "${REGION}" >/dev/null

BUCKET="gs://${DEVSHELL_PROJECT_ID}"

# Create bucket (ignore if already exists)
if gsutil ls -b "${BUCKET}" >/dev/null 2>&1; then
  echo -e "${YELLOW}ℹ️  Bucket already exists: ${BUCKET}${RESET}"
else
  gsutil mb "${BUCKET}"
fi

curl -L "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Ada_Lovelace_portrait.jpg/800px-Ada_Lovelace_portrait.jpg" \
  --output ada.jpg

gsutil cp ada.jpg "${BUCKET}/ada.jpg"

# Download back
gsutil cp "${BUCKET}/ada.jpg" .

# Copy into folder (prefix will be created automatically)
gsutil cp "${BUCKET}/ada.jpg" "${BUCKET}/image-folder/"

# Make public (ACL 방식 - theo lab hay dùng)
gsutil acl ch -u allUsers:R "${BUCKET}/ada.jpg"

echo -e "${CYAN}"
echo "============================================================="
echo "🎉 Deployment complete!"
echo "🖼️ Uploaded: ${BUCKET}/ada.jpg (public)"
echo "✨ Script finished by ePlus.DEV - https://eplus.dev"
echo "============================================================="
echo -e "${RESET}"