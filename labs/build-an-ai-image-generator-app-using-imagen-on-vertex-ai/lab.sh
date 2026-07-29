#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════╗"
echo "║       ePlus.DEV - GenAI Image Lab     ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo -e "${RED}Error: Unable to detect the Google Cloud project ID.${NC}"
  exit 1
fi

echo -e "${GREEN}Project ID : ${PROJECT_ID}${NC}"
echo -e "${GREEN}Location   : global${NC}"
echo

echo -e "${YELLOW}Checking the required Python packages...${NC}"

python3 -m pip install --user --quiet \
  --upgrade \
  google-genai \
  google-cloud-logging \
  pillow

cat > GenerateImage.py <<PYTHON
import time

from google import genai
from google.cloud import logging as gcp_logging
from google.genai.errors import ClientError
from google.genai.types import HttpOptions

PROJECT_ID = "${PROJECT_ID}"
LOCATION = "global"
MODEL_NAME = "gemini-3.1-flash-image"

# ------------------------------------------------------------------
# The Cloud Logging code below is required for Qwiklabs verification.
# Do not edit or remove it.
# ------------------------------------------------------------------
gcp_logging_client = gcp_logging.Client(project=PROJECT_ID)
gcp_logging_client.setup_logging()

client = genai.Client(
    enterprise=True,
    project=PROJECT_ID,
    location=LOCATION,
    http_options=HttpOptions(api_version="v1"),
)

prompt = (
    "Create an image of a cricket ground in the heart of Los Angeles",
)

MAX_RETRIES = 3
INITIAL_DELAY = 2
response = None

for attempt in range(MAX_RETRIES + 1):
    try:
        print(f"Sending the prompt to {MODEL_NAME}...")
        print(f"Attempt: {attempt + 1}/{MAX_RETRIES + 1}")

        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[prompt],
        )

        image_saved = False

        for part in response.parts:
            if part.text is not None:
                print(part.text)

            elif part.inline_data is not None:
                image = part.as_image()
                image.save("image.png")
                image_saved = True
                print("Status: Image saved as image.png")

        if not image_saved:
            raise RuntimeError(
                "The model returned a response, but no image data was found."
            )

        print(
            "Success: Content generation and processing completed successfully."
        )
        break

    except ClientError as error:
        error_message = str(error)

        if "429" in error_message or "RESOURCE_EXHAUSTED" in error_message:
            if attempt < MAX_RETRIES:
                delay = INITIAL_DELAY * (2 ** attempt)
                print(
                    f"Warning: Resource exhausted (429). "
                    f"Retrying in {delay} seconds... "
                    f"(Attempt {attempt + 1}/{MAX_RETRIES})"
                )
                time.sleep(delay)
                continue

            print(
                "The service is currently experiencing high demand due to "
                "quota exhaustion. Run the script again later."
            )
            raise

        print(f"Error: The Gemini request failed.\n{error}")
        raise

    except Exception as error:
        print(f"Error: {error}")
        raise

if response is None:
    print("Final Status: Process terminated unsuccessfully.")
    raise SystemExit(1)
PYTHON

echo -e "${GREEN}GenerateImage.py was created successfully.${NC}"
echo
echo -e "${YELLOW}Sending the image generation request...${NC}"
echo

python3 GenerateImage.py

echo

if [[ -s "image.png" ]]; then
  echo -e "${GREEN}Lab task completed successfully.${NC}"
  echo -e "${GREEN}Output file: $(pwd)/image.png${NC}"
  ls -lh image.png
else
  echo -e "${RED}Error: image.png was not created.${NC}"
  exit 1
fi