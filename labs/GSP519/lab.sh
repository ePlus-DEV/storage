#!/bin/bash
# ======================================================
# 🚀 ePlus.DEV | Vertex AI Lab Helper (FINAL)
# ------------------------------------------------------
# 📁 replace_project.sh
# Automatically refreshes and patches Vertex AI lab notebooks:
#   - image-analysis.ipynb
#   - tagline-generator.ipynb
#
# 🧑‍💻 Author: ePlus.DEV
# 🌐 Website: https://eplus.dev
# ======================================================

# 🎨 Color definitions
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# 1️⃣ Detect PROJECT_ID and LOCATION
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
LOCATION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [ -z "$LOCATION" ]; then
  LOCATION="us-central1"
fi

if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}❌ Could not retrieve PROJECT_ID. Make sure you're authenticated with gcloud.${RESET}"
  exit 1
fi

echo -e "${CYAN}📡 PROJECT_ID: ${GREEN}$PROJECT_ID${RESET}"
echo -e "${CYAN}🌍 LOCATION:   ${GREEN}$LOCATION${RESET}"
echo -e "${YELLOW}⚙️  Starting notebook update process...${RESET}"

# 2️⃣ Clean up old notebooks
echo -e "${CYAN}🧹 Removing old notebooks...${RESET}"
rm -f image-analysis.ipynb
rm -f tagline-generator.ipynb

# 3️⃣ Download fresh copies
echo -e "${CYAN}⬇️  Downloading notebooks...${RESET}"
curl -s -LO "https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP519/image-analysis.ipynb"
curl -s -LO "https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP519/tagline-generator.ipynb"

# 4️⃣ Verify
if [ ! -f "image-analysis.ipynb" ] || [ ! -f "tagline-generator.ipynb" ]; then
  echo -e "${RED}❌ Download failed. Check your connection or URLs.${RESET}"
  exit 1
fi

# 5️⃣ Preview current gs:// references
echo -e "${CYAN}🔍 Checking bucket references before replacement...${RESET}"
grep -m 1 "gs://" image-analysis.ipynb || echo -e "${YELLOW}⚠️  No gs:// reference found in image-analysis.ipynb${RESET}"

# 6️⃣ Perform replacements

echo -e "${CYAN}🔁 Replacing all project references and paths...${RESET}"

# ✅ Replace correct bucket paths with -bucket suffix
sed -i "s|gs://qwiklabs-gcp-[a-zA-Z0-9-]\+-bucket|gs://$PROJECT_ID-bucket|g" image-analysis.ipynb

# ✅ FIX: If notebook still contains gs://<PROJECT_ID>/... without -bucket
sed -i "s|gs://$PROJECT_ID/|gs://$PROJECT_ID-bucket/|g" image-analysis.ipynb

# ✅ Replace project and location arguments
sed -i "s|project=\"[a-zA-Z0-9-]\+\", *location=\"[a-zA-Z0-9-]\+\"|project=\"$PROJECT_ID\", location=\"$LOCATION\"|g" image-analysis.ipynb
sed -i "s|project=\"[a-zA-Z0-9-]\+\", *location=\"[a-zA-Z0-9-]\+\"|project=\"$PROJECT_ID\", location=\"$LOCATION\"|g" tagline-generator.ipynb

# ✅ Replace Python variable PROJECT_ID if defined
sed -i "s|PROJECT_ID = \"[a-zA-Z0-9-]\+\"|PROJECT_ID = \"$PROJECT_ID\"|g" image-analysis.ipynb
sed -i "s|PROJECT_ID = \"[a-zA-Z0-9-]\+\"|PROJECT_ID = \"$PROJECT_ID\"|g" tagline-generator.ipynb

# ✅ Replace any leftover project strings
sed -i "s|qwiklabs-gcp-[a-zA-Z0-9-]\+|$PROJECT_ID|g" image-analysis.ipynb
sed -i "s|qwiklabs-gcp-[a-zA-Z0-9-]\+|$PROJECT_ID|g" tagline-generator.ipynb

# ✅ Final safety: double-check any file_uri lines and force -bucket suffix
sed -i "s|gs://$PROJECT_ID[^-/]*|gs://$PROJECT_ID-bucket|g" image-analysis.ipynb

# 7️⃣ Show preview after replacement
echo -e "${CYAN}✅ Updated gs:// reference (first occurrence):${RESET}"
grep -m 1 "gs://" image-analysis.ipynb || echo -e "${YELLOW}⚠️  Still no gs:// reference found after patch${RESET}"

# 🔚 Final message
echo -e "${GREEN}🎉 DONE!${RESET}"
echo -e "👉 ${BOLD}PROJECT_ID${RESET}: ${GREEN}${PROJECT_ID}${RESET}"
echo -e "👉 ${BOLD}LOCATION${RESET}: ${GREEN}${LOCATION}${RESET}"
echo -e "📁 Updated notebooks: ${BOLD}image-analysis.ipynb${RESET} & ${BOLD}tagline-generator.ipynb${RESET}"
echo -e "${CYAN}🚀 Powered by ${BOLD}ePlus.DEV${RESET} 🌐 https://eplus.dev"
