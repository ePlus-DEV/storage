#!/bin/bash
set -euo pipefail

# ==================================================
#        ePlus.DEV - Gemini Chat Lab
# ==================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear

echo -e "${CYAN}"
echo "╔════════════════════════════════════════╗"
echo "║      ePlus.DEV - Gemini Chat Lab       ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo -e "${RED}Error: Unable to detect the Google Cloud project ID.${NC}"
  exit 1
fi

echo -e "${GREEN}Project ID : ${PROJECT_ID}${NC}"
echo -e "${GREEN}Location   : global${NC}"
echo -e "${GREEN}Model      : gemini-3.5-flash${NC}"
echo

echo -e "${CYAN}Checking required Python packages...${NC}"

if ! /usr/bin/python3 -c "from google import genai; from google.cloud import logging" >/dev/null 2>&1; then
  echo -e "${YELLOW}Installing required Google Cloud packages...${NC}"
  /usr/bin/python3 -m pip install --user --quiet \
    google-genai \
    google-cloud-logging
fi

echo -e "${GREEN}Required packages are available.${NC}"
echo

# ==================================================
# Non-streaming chat
# ==================================================

cat > /SendChatwithoutStream.py <<PYTHON
import time
from google import genai
from google.genai.types import HttpOptions, ModelContent, Part, UserContent

import logging
from google.cloud import logging as gcp_logging
from google.genai.errors import ClientError

# ------ Below cloud logging code is for Qwiklab's internal use, do not edit/remove it. --------
# Initialize GCP logging
gcp_logging_client = gcp_logging.Client()
gcp_logging_client.setup_logging()

client = genai.Client(
    enterprise=True,
    project="${PROJECT_ID}",
    location="global",
    http_options=HttpOptions(api_version="v1"),
)

# Configuration for retry logic
MAX_RETRIES = 3
INITIAL_DELAY = 2

response_received = False

for attempt in range(MAX_RETRIES + 1):
    try:
        chat = client.chats.create(
            model="gemini-3.5-flash",
            history=[
                UserContent(parts=[Part(text="Hello")]),
                ModelContent(
                    parts=[
                        Part(
                            text="Great to meet you. What would you like to know?"
                        )
                    ],
                ),
            ],
        )

        response = chat.send_message(
            "What are all the colors in a rainbow?"
        )
        print(response.text)

        response = chat.send_message(
            "Why does it appear when it rains?"
        )
        print(response.text)

        response_received = True
        logging.info(
            "Successfully received non-streaming Gemini chat responses."
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
            else:
                print(
                    "I am currently experiencing high demand due to quota "
                    "exhaustion. Please wait for a while and try again."
                )
        else:
            logging.exception("Gemini request failed.")
            raise

if not response_received:
    print("Final Status: Process terminated unsuccessfully.")
    raise SystemExit(1)
PYTHON

# ==================================================
# Streaming chat
# ==================================================

cat > /SendChatwithStream.py <<PYTHON
import time
from google import genai
from google.genai.types import HttpOptions

import logging
from google.cloud import logging as gcp_logging
from google.genai.errors import ClientError

# ------ Below cloud logging code is for Qwiklab's internal use, do not edit/remove it. --------
# Initialize GCP logging
gcp_logging_client = gcp_logging.Client()
gcp_logging_client.setup_logging()

client = genai.Client(
    enterprise=True,
    project="${PROJECT_ID}",
    location="global",
    http_options=HttpOptions(api_version="v1"),
)

chat = client.chats.create(model="gemini-3.5-flash")

# Configuration for retry logic
MAX_RETRIES = 3
INITIAL_DELAY = 2

response_received = False

for attempt in range(MAX_RETRIES + 1):
    response_text = ""

    try:
        for chunk in chat.send_message_stream(
            "What are all the colors in a rainbow?"
        ):
            if chunk.text:
                print(chunk.text, end="", flush=True)
                response_text += chunk.text

        print()

        if response_text:
            response_received = True
            logging.info(
                "Successfully received a streaming Gemini chat response."
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
            else:
                print(
                    "I am currently experiencing high demand due to quota "
                    "exhaustion. Please wait for a while and try again."
                )
        else:
            logging.exception("Gemini streaming request failed.")
            raise

if not response_received:
    print("Final Status: Process terminated unsuccessfully.")
    raise SystemExit(1)
PYTHON

echo -e "${CYAN}Running the non-streaming chat file...${NC}"
echo

/usr/bin/python3 /SendChatwithoutStream.py

echo
echo -e "${GREEN}Non-streaming chat completed successfully.${NC}"
echo
echo -e "${YELLOW}Waiting for the Cloud Logging entry to be created...${NC}"

sleep 20

echo
echo -e "${CYAN}Running the streaming chat file...${NC}"
echo

/usr/bin/python3 /SendChatwithStream.py

echo
echo -e "${GREEN}Streaming chat completed successfully.${NC}"
echo
echo -e "${YELLOW}Waiting for the final Cloud Logging entry...${NC}"

sleep 15

echo
echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}Lab execution completed successfully.${NC}"
echo -e "${GREEN}Click \"Check my progress\" in the lab page.${NC}"
echo -e "${GREEN}==================================================${NC}"