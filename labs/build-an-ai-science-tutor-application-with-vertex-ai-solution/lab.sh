#!/bin/bash

# Color Definitions
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Confirm User Input
echo "${GREEN_TEXT}${BOLD_TEXT}You have entered the region:${RESET_FORMAT} ${YELLOW_TEXT}${REGION}${RESET_FORMAT}"
echo

# Fetch GCP Project ID
PROJECT_ID="$(gcloud projects list --format='value(PROJECT_ID)')"
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Multimodal Analysis Script
cat > genai.py <<EOF_END

import vertexai
from vertexai.generative_models import GenerativeModel

# Replace with your actual project details
PROJECT_ID = "$PROJECT_ID"
LOCATION = "$REGION"

# Initialize Vertex AI onAxcode
vertexai.init(project=PROJECT_ID, location=LOCATION)

def science_tutoring(prompt):
    """
    Sends a prompt to ab Gemini 2.5 Flash Lite model
    and returns the generated response.
    """
    try:
        # Load ab52=460 2.5 Flash Lite model
        model = GenerativeModel("gemini-2.5-flash-lite")

        # Generate response
        response = model.generate_content(prompt)

        return response.text

    except Exception as e:
        return f"Error occurred: {str(e)}"


if __name__ == "__main__":
    test_prompt = "How many planets are there in the solar system?"
    
    result = science_tutoring(test_prompt)
    
    print("Response:")
    print(result)
EOF_END

echo "${YELLOW_TEXT}${BOLD_TEXT}Analyzing the generated image with Gemini...${RESET_FORMAT}"
/usr/bin/python3 /home/student/genai.py

# Enhanced Completion Message
echo
echo "${GREEN_TEXT}${BOLD_TEXT}╔══════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}║                                                  ║${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}║          🎉 LAB COMPLETED SUCCESSFULLY! 🎉       ║${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}║                                                  ║${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}╚══════════════════════════════════════════════════╝${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}┌──────────────────────────────────────────────────┐${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}│  ${WHITE_TEXT}🔍 Explore more AI content at:                  ${CYAN_TEXT}│${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}│  ${BLUE_TEXT}${UNDERLINE_TEXT}https://eplus.dev${NO_COLOR}${CYAN_TEXT}   │${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}└──────────────────────────────────────────────────┘${RESET_FORMAT}"
echo