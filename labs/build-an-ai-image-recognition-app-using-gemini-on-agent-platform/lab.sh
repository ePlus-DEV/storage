#!/bin/bash
set -euo pipefail

# ==================================================
#          ePlus.DEV - Gemini Image Lab
# ==================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════╗"
echo "║      ePlus.DEV - Gemini Image Lab      ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo -e "${RED}Error: No active Google Cloud project was found.${NC}"
  exit 1
fi

# Detect the project's default Compute Engine region
REGION="$(gcloud compute project-info describe \
  --project="$PROJECT_ID" \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
  2>/dev/null || true)"

if [[ -z "$REGION" ]]; then
  REGION="Not configured"
fi

# Gemini 3.5 Flash for this lab is available through the global location
GENAI_LOCATION="global"

echo -e "${GREEN}Project ID              : ${PROJECT_ID}${NC}"
echo -e "${GREEN}Detected compute region : ${REGION}${NC}"
echo -e "${GREEN}Gemini location         : ${GENAI_LOCATION}${NC}"

export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
export GOOGLE_CLOUD_LOCATION="$GENAI_LOCATION"
export GOOGLE_GENAI_USE_ENTERPRISE="True"

echo -e "\n${YELLOW}Checking the Google Gen AI SDK...${NC}"

if ! python3 -c "from google import genai" >/dev/null 2>&1; then
  echo "Installing google-genai..."
  python3 -m pip install --user --quiet --upgrade google-genai
fi

cat > genai.py <<'PYTHON'
import os
import time

from google import genai
from google.genai.errors import ClientError
from google.genai.types import HttpOptions, Part


PROJECT_ID = os.environ["GOOGLE_CLOUD_PROJECT"]
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "global")

client = genai.Client(
    http_options=HttpOptions(api_version="v1"),
    enterprise=True,
    project=PROJECT_ID,
    location=LOCATION,
)

MAX_RETRIES = 3
INITIAL_DELAY = 2

print(f"Using project: {PROJECT_ID}")
print(f"Using Gemini location: {LOCATION}")

for attempt in range(MAX_RETRIES + 1):
    try:
        response = client.models.generate_content(
            model="gemini-3.5-flash",
            contents=[
                "What is shown in this image?",
                Part.from_uri(
                    file_uri=(
                        "https://storage.googleapis.com/"
                        "cloud-samples-data/generative-ai/image/scones.jpg"
                    ),
                    mime_type="image/jpeg",
                ),
            ],
        )

        output_text = response.text or ""

        if not output_text.strip():
            raise RuntimeError("Gemini returned an empty response.")

        with open("output.txt", "w", encoding="utf-8") as output_file:
            output_file.write(output_text)

        print("\n========== GEMINI RESPONSE ==========\n")
        print(output_text)
        print("\n=====================================")
        print("The response was saved to output.txt.")
        break

    except ClientError as error:
        error_message = str(error)

        if "429" in error_message or "RESOURCE_EXHAUSTED" in error_message:
            if attempt < MAX_RETRIES:
                delay = INITIAL_DELAY * (2 ** attempt)
                print(
                    f"Warning: Resource exhausted. Retrying in {delay} seconds "
                    f"(attempt {attempt + 1}/{MAX_RETRIES})..."
                )
                time.sleep(delay)
                continue

        print(f"Error: The Gemini request failed.\n{error}")
        raise
else:
    raise RuntimeError("Gemini did not return a response.")
PYTHON

echo -e "\n${YELLOW}Sending the image and prompt to Gemini...${NC}\n"

python3 genai.py

if [[ ! -s output.txt ]]; then
  echo -e "${RED}Error: output.txt was not created or is empty.${NC}"
  exit 1
fi

echo -e "\n${GREEN}Lab task completed successfully.${NC}"
echo -e "${GREEN}Output file: $(pwd)/output.txt${NC}"