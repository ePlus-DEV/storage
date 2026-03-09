#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`
#----------------------------------------------------start--------------------------------------------------#

echo "${YELLOW}${BOLD}Starting${RESET}" "${GREEN}${BOLD}Execution - ePlus.DEV${RESET}"



PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud config get-value compute/region)

if [ -z "$REGION" ] || [ "$REGION" = "(unset)" ]; then
  REGION="us-central1"
fi

# Enable APIs without prompt
gcloud services enable -q \
aiplatform.googleapis.com \
storage.googleapis.com \
serviceusage.googleapis.com \
--project="$PROJECT_ID"

# Create service identity automatically
yes | gcloud beta services identity create \
--service=aiplatform.googleapis.com \
--project="$PROJECT_ID"

# Create python file
cat > genai_image.py <<EOF
#!/usr/bin/env python3

import vertexai
from vertexai.generative_models import GenerativeModel, Part

PROJECT_ID = "$PROJECT_ID"
LOCATION = "$REGION"

vertexai.init(project=PROJECT_ID, location=LOCATION)

def load_image_from_url(prompt):
    model = GenerativeModel("gemini-2.0-flash")

    image = Part.from_uri(
        uri="gs://cloud-samples-data/vision/landmark/eiffel_tower.jpg",
        mime_type="image/jpeg"
    )

    response = model.generate_content([image, prompt])
    return response.text


if __name__ == "__main__":
    prompt = "Describe this image in detail and explain what makes it unique."

    print("Project ID:", PROJECT_ID)
    print("Location:", LOCATION)
    print("Prompt:", prompt)
    print("\\nModel Response:\\n")

    print(load_image_from_url(prompt))
EOF

/usr/bin/python3 genai_image.py


echo "${RED}${BOLD}Congratulations${RESET}" "${WHITE}${BOLD}for${RESET}" "${GREEN}${BOLD}Completing the Lab !!! - ePlus.DEV${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#