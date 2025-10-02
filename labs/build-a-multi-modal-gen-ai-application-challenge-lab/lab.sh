#!/bin/bash
# -----------------------------------------------------------------------------
# Copyright (c) 2025 ePlus.DEV
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# -----------------------------------------------------------------------------

# 🌸 AI Bouquet Generator – ePlus.DEV

# Colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)

echo -e "${GREEN}✅ Using Project:${NC} $PROJECT_ID"
echo -e "${GREEN}✅ Using Region:${NC} $REGION"

# ✅ Install dependencies
echo -e "${YELLOW}📦 Installing required Python packages...${NC}"
pip install --quiet --upgrade google-cloud-aiplatform

# 🧠 Make sure pip install is loaded before running Python
hash -r
python3 -m pip install --upgrade pip > /dev/null 2>&1

# 🚀 Run inline Python
python3 <<EOF
import os
import vertexai
from vertexai.preview.generative_models import ImageGenerationModel, GenerativeModel, Part

# Init Vertex AI
PROJECT_ID = "$PROJECT_ID"
LOCATION = "$REGION"
vertexai.init(project=PROJECT_ID, location=LOCATION)

# --- Task 1: Generate bouquet image ---
prompt = "Create an image containing a bouquet of 2 sunflowers and 3 roses."
model = ImageGenerationModel.from_pretrained("imagen-3.0-generate-002")
result = model.generate_images(prompt=prompt, number_of_images=1, aspect_ratio="1:1")

image_path = "bouquet.png"
result.images[0].save(image_path)
print(f"\\n${GREEN}✅ Image generated and saved to {image_path}${NC}")

# --- Task 2: Analyze bouquet image ---
gemini = GenerativeModel("gemini-2.0-flash-001")
image_part = Part.from_image(image_path)
text_prompt = "Generate a creative birthday wish based on this bouquet image."

print(f"\\n${YELLOW}🎉 Birthday wish generated:${NC}")
responses = gemini.generate_content([image_part, text_prompt], stream=True)
for response in responses:
    if response.candidates:
        print(response.candidates[0].content.parts[0].text)
EOF