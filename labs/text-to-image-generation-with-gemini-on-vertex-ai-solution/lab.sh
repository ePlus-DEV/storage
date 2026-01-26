#!/bin/bash
# =============================================================
# 🚀 Cymbal Solutions - Vertex AI Gemini Challenge
# 🧠 Model: gemini-2.5-flash
# ✍️ Author: ePlus.DEV
# =============================================================

set -euo pipefail

# ---------- Colors ----------
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

echo -e "${CYAN}"
echo "============================================================"
echo "  Vertex AI Gemini Chat + Image Generation (Python SDK)"
echo "  Cymbal Solutions - Challenge Scenario"
echo "============================================================"
echo -e "${RESET}"

# ---------- Check project ----------
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-${DEVSHELL_PROJECT_ID:-}}"
REGION="${GOOGLE_CLOUD_REGION:-${REGION:-us-central1}}"

if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}❌ PROJECT_ID not found. Set GOOGLE_CLOUD_PROJECT.${RESET}"
  exit 1
fi

echo -e "${GREEN}✔ Project: $PROJECT_ID${RESET}"
echo -e "${GREEN}✔ Region : $REGION${RESET}"

# ---------- Create Python file ----------
PY_FILE="gemini_chat.py"

cat > "$PY_FILE" <<'PYCODE'
import os
import vertexai
from vertexai.generative_models import GenerativeModel, GenerationConfig

def get_chat_response(prompt: str) -> str:
    project_id = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("DEVSHELL_PROJECT_ID")
    location = os.environ.get("GOOGLE_CLOUD_REGION") or os.environ.get("REGION") or "us-central1"

    vertexai.init(project=project_id, location=location)

    model = GenerativeModel("gemini-2.5-flash")

    config = GenerationConfig(
        temperature=0.7,
        max_output_tokens=1024,
        response_modalities=["TEXT", "IMAGE"],
    )

    response = model.generate_content(prompt, generation_config=config)

    text = response.text or ""

    # Try saving image if available
    try:
        images = getattr(response, "generated_images", None)
        if images:
            with open("output.png", "wb") as f:
                f.write(images[0].image_bytes)
            text += "\n\n[Image saved as output.png]"
    except Exception:
        pass

    return text.strip()


if __name__ == "__main__":
    prompt = (
        "You are an interactive science tutoring assistant.\n\n"
        "Question 1: Hello! What are all the colors in a rainbow?\n"
        "Question 2: What is Prism?\n\n"
        "After answering, generate an educational image showing a prism "
        "splitting white light into a rainbow."
    )

    result = get_chat_response(prompt)
    print(result)
PYCODE

echo -e "${GREEN}✔ Python file created: $PY_FILE${RESET}"

# ---------- Run Python ----------
echo -e "${CYAN}▶ Running Gemini model...${RESET}"
/usr/bin/python3 "$PY_FILE"

echo -e "${GREEN}"
echo "============================================================"
echo " ✅ Done! Check output above."
echo " 📷 If supported, image saved as output.png"
echo "============================================================"
echo -e "${RESET}"