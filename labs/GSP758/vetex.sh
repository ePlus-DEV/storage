#!/bin/bash
# ======================================================
# 🚀 ePlus.DEV | Vertex AI Lab Auto Updater (FINAL CLEAN)
# ------------------------------------------------------
# 📁 lab.sh
# ✅ Removes old notebooks (no prompt), retries download,
#    replaces project ID + region, and deletes itself.
# ======================================================

# 🎨 Colors
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# 1️⃣ Detect project and region
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
LOCATION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [ -z "$LOCATION" ]; then
  LOCATION="us-central1"
fi

if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}❌ Could not retrieve PROJECT_ID. Please authenticate with gcloud first.${RESET}"
  exit 1
fi

echo -e "${CYAN}📡 PROJECT_ID: ${GREEN}$PROJECT_ID${RESET}"
echo -e "${CYAN}🌍 LOCATION:   ${GREEN}$LOCATION${RESET}"

# 2️⃣ Force-remove old notebooks without asking
echo -e "${CYAN}🧹 Removing old notebooks (no prompt)...${RESET}"
rm -f measuring-accuracy.ipynb notebook_template.ipynb image-analysis.backup.ipynb tagline-generator.backup.ipynb 2>/dev/null

# 3️⃣ Download function with retry
download_with_retry() {
  local url="$1"
  local output="$2"
  local attempt=1
  local max_attempts=3

  while [ $attempt -le $max_attempts ]; do
    echo -e "${CYAN}⬇️  Attempt $attempt: Downloading ${BOLD}$output${RESET}..."
    curl -s -L -o "$output" "$url"

    if [ -f "$output" ] && [ -s "$output" ]; then
      echo -e "${GREEN}✅ Download successful:${RESET} $output"
      return 0
    else
      echo -e "${YELLOW}⚠️  Download failed for ${output}. Retrying...${RESET}"
      rm -f "$output" 2>/dev/null
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  echo -e "${RED}❌ Failed to download ${output} after ${max_attempts} attempts.${RESET}"
  exit 1
}

# 4️⃣ Download latest notebooks with retry
download_with_retry "https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/GSP785/measuring-accuracy.ipynb" "measuring-accuracy.ipynb"
download_with_retry "https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/GSP785/notebook_template.ipynb" "notebook_template.ipynb"

# 5️⃣ Replace project and region in all notebooks
for FILE in measuring-accuracy.ipynb notebook_template.ipynb; do
  if [ -f "$FILE" ]; then
    echo -e "${CYAN}🔁 Updating ${BOLD}$FILE${RESET}..."

    # Replace project IDs
    sed -i "s|qwiklabs-gcp-[a-zA-Z0-9-]\+|$PROJECT_ID|g" "$FILE"

    # Replace region
    sed -i "s|us-east4|$LOCATION|g" "$FILE"

    echo -e "✅ ${GREEN}Patched:${RESET} $FILE"
  fi
done

# ✅ Done
echo -e "\n${GREEN}🎉 All notebooks updated successfully!${RESET}"
echo -e "👉 PROJECT_ID: ${GREEN}$PROJECT_ID${RESET}"
echo -e "👉 REGION:     ${GREEN}$LOCATION${RESET}"
echo -e "📁 Files ready: ${BOLD}measuring-accuracy.ipynb${RESET}, ${BOLD}notebook_template.ipynb${RESET}"
echo -e "${CYAN}🚀 Powered by ${BOLD}ePlus.DEV${RESET} 🌐 https://eplus.dev"