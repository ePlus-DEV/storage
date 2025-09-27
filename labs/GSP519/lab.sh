#!/bin/bash
# ======================================================
# 🚀 ePlus.DEV | Vertex AI Lab Helper
# ------------------------------------------------------
# 📁 replace_project.sh
# Automatically refreshes lab notebooks:
#   - image-analysis.ipynb
#   - tagline-generator.ipynb
#
# ✅ Features:
#   - Auto-detect PROJECT_ID
#   - Replace gs:// bucket references
#   - Replace project="..." , location="..."
#   - Colored terminal output
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

# 1️⃣ Set project and location
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
LOCATION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}❌ Could not retrieve PROJECT_ID. Make sure you're authenticated with gcloud.${RESET}"
  exit 1
fi

echo -e "${CYAN}📡 PROJECT_ID: ${GREEN}$PROJECT_ID${RESET}"
echo -e "${CYAN}🌍 LOCATION:   ${GREEN}$LOCATION${RESET}"
echo -e "${YELLOW}⚙️  Starting notebook update process...${RESET}"

# 2️⃣ Remove old notebooks if they exist
echo -e "${CYAN}🧹 Removing old notebooks...${RESET}"
rm -f image-analysis.ipynb
rm -f tagline-generator.ipynb

# 3️⃣ Download image-analysis.ipynb
echo -e "${CYAN}⬇️  Downloading ${BOLD}image-analysis.ipynb${RESET}..."
curl -s -LO "https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP519/image-analysis.ipynb"

# 4️⃣ Download tagline-generator.ipynb
echo -e "${CYAN}⬇️  Downloading ${BOLD}tagline-generator.ipynb${RESET}..."
curl -s -LO "https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP519/tagline-generator.ipynb"

# 5️⃣ Verify downloads
if [ ! -f "image-analysis.ipynb" ] || [ ! -f "tagline-generator.ipynb" ]; then
  echo -e "${RED}❌ Download failed. Please check the URLs or your network connection.${RESET}"
  exit 1
fi

# 6️⃣ Preview gs:// reference (only in image-analysis.ipynb)
echo -e "${CYAN}🔍 Checking bucket references before replacement...${RESET}"
grep -m 1 "gs://" image-analysis.ipynb || echo -e "${YELLOW}⚠️  No gs:// reference found in image-analysis.ipynb${RESET}"

# 7️⃣ Replace project IDs (including in gs://)
echo -e "${CYAN}🔁 Replacing ${BOLD}PROJECT_ID${RESET} in ${BOLD}image-analysis.ipynb${RESET}..."
sed -i "s/qwiklabs-gcp-[a-zA-Z0-9-]\+/$PROJECT_ID/g" image-analysis.ipynb

# 8️⃣ Replace project + location lines in BOTH notebooks
echo -e "${CYAN}🔁 Updating ${BOLD}project${RESET} and ${BOLD}location${RESET} in both notebooks..."
sed -i "s/project=\"[a-zA-Z0-9-]\+\", location=\"[a-zA-Z0-9-]\+\"/project=\"$PROJECT_ID\", location=\"$LOCATION\"/g" image-analysis.ipynb
sed -i "s/project=\"[a-zA-Z0-9-]\+\", location=\"[a-zA-Z0-9-]\+\"/project=\"$PROJECT_ID\", location=\"$LOCATION\"/g" tagline-generator.ipynb

# 9️⃣ Preview gs:// reference after replacement
echo -e "${CYAN}✅ Updated bucket references after replacement:${RESET}"
grep -m 1 "gs://" image-analysis.ipynb || echo -e "${YELLOW}⚠️  No gs:// reference found after replacement${RESET}"

# 🔟 Done!
echo -e "${GREEN}🎉 DONE!${RESET}"
echo -e "👉 ${BOLD}PROJECT_ID${RESET} is now: ${GREEN}${PROJECT_ID}${RESET}"
echo -e "👉 ${BOLD}LOCATION${RESET} is now: ${GREEN}${LOCATION}${RESET}"
echo -e "📁 Notebooks are ready: ${BOLD}image-analysis.ipynb${RESET} & ${BOLD}tagline-generator.ipynb${RESET}"
echo -e "${CYAN}🚀 Powered by ${BOLD}ePlus.DEV${RESET} 🌐 https://eplus.dev"