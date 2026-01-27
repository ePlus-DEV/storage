#!/bin/bash
# =============================================================
# 🚀 Vertex AI Gemini Lab (clone then replace)
# © 2026 ePlus.DEV
# =============================================================

set -euo pipefail

# =======================
# 🌈 Colors
# =======================
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

# =======================
# 📄 File source
# =======================
RAW_URL="https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/text-to-image-generation-with-gemini-on-vertex-ai-solution/main.py"
TARGET_FILE="main.py"

echo -e "${CYAN}${BOLD}▶ Fetching main.py from repository...${RESET}"

# =======================
# ⬇️ Clone (download) main.py
# =======================
curl -fsSL "${RAW_URL}?nocache=$(date +%s)" -o "${TARGET_FILE}"
echo -e "${GREEN}✔ main.py downloaded${RESET}"

# =======================
# 🔧 Project & Region
# =======================
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}❌ PROJECT_ID not set. Run: gcloud config set project <PROJECT_ID>${RESET}"
  exit 1
fi

REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
REGION="${REGION:-us-central1}"

echo -e "${GREEN}✔ Project : ${PROJECT_ID}${RESET}"
echo -e "${GREEN}✔ Region  : ${REGION}${RESET}"

# =======================
# 🔌 Enable Vertex AI
# =======================
echo -e "${CYAN}▶ Enabling Vertex AI API...${RESET}"
gcloud services enable aiplatform.googleapis.com >/dev/null

# =======================
# 📦 Install SDK
# =======================
echo -e "${CYAN}▶ Installing google-cloud-aiplatform...${RESET}"
pip3 install --user -q --upgrade google-cloud-aiplatform

# =======================
# 📝 Replace main.py content
# =======================
echo -e "${YELLOW}▶ Replacing main.py content...${RESET}"

cat > "${TARGET_FILE}" <<PY
import vertexai
from vertexai.generative_models import GenerativeModel

PROJECT_ID = "${PROJECT_ID}"
LOCATION = "${REGION}"

vertexai.init(project=PROJECT_ID, location=LOCATION)

def get_chat_response(prompt):
    model = GenerativeModel("gemini-2.5-flash")
    response = model.generate_content(prompt)
    return response.text

if __name__ == "__main__":
    prompts = [
        "Hello! What are all the colors in a rainbow?",
        "What is Prism?"
    ]

    for question in prompts:
        print(f"User: {question}")
        try:
            answer = get_chat_response(question)
            print(f"Model: {answer}\\n")
        except Exception as e:
            print(f"Error: {e}")
PY

echo -e "${GREEN}✔ main.py replaced successfully${RESET}"

# =======================
# ▶ Run
# =======================
echo -e "${GREEN}${BOLD}▶ Running main.py...${RESET}"
python3 "${TARGET_FILE}"

echo -e "${GREEN}${BOLD}🎉 Done!${RESET}"