#!/bin/bash
# ======================================================
# 🚀 ePlus.DEV | Vertex AI Lab Minimal Patcher
# ------------------------------------------------------
# 📁 replace_project.sh
# ✅ Replaces:
#   - "qwiklabs-gcp-xxx" → current PROJECT_ID
#   - "us-east4" → current LOCATION
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

# Fallback default region if none found
if [ -z "$LOCATION" ]; then
  LOCATION="us-central1"
fi

if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}❌ Could not retrieve PROJECT_ID. Make sure you're authenticated with gcloud.${RESET}"
  exit 1
fi

echo -e "${CYAN}📡 PROJECT_ID: ${GREEN}$PROJECT_ID${RESET}"
echo -e "${CYAN}🌍 LOCATION:   ${GREEN}$LOCATION${RESET}"
echo -e "${YELLOW}⚙️  Starting replacements...${RESET}"

# 2️⃣ Validate files exist
if [ ! -f "image-analysis.ipynb" ] && [ ! -f "tagline-generator.ipynb" ]; then
  echo -e "${RED}❌ Notebooks not found. Make sure they are in the current directory.${RESET}"
  exit 1
fi

# 3️⃣ Replace in all notebooks
for FILE in image-analysis.ipynb tagline-generator.ipynb; do
  if [ -f "$FILE" ]; then
    echo -e "${CYAN}🔁 Updating ${BOLD}$FILE${RESET}..."

    # Replace any qwiklabs-gcp-* pattern with current project
    sed -i "s|qwiklabs-gcp-[a-zA-Z0-9-]\+|$PROJECT_ID|g" "$FILE"

    # Replace region us-east4 with current region
    sed -i "s|us-east4|$LOCATION|g" "$FILE"

    echo -e "✅ ${GREEN}Done:${RESET} $FILE"
  fi
done

# ✅ Finished
echo -e "\n${GREEN}🎉 All replacements complete!${RESET}"
echo -e "👉 PROJECT_ID: ${GREEN}$PROJECT_ID${RESET}"
echo -e "👉 REGION:     ${GREEN}$LOCATION${RESET}"
echo -e "${CYAN}🚀 Powered by ${BOLD}ePlus.DEV${RESET} 🌐 https://eplus.dev"