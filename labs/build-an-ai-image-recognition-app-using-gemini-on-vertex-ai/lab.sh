#!/usr/bin/env bash
set -euo pipefail

# ================= Colors =================
BOLD=$(tput bold || true); RESET=$(tput sgr0 || true)
GREEN=$(tput setaf 2 || true); YELLOW=$(tput setaf 3 || true)

echo "${YELLOW}${BOLD}==> Tạo file genai.py...${RESET}"

# Tạo file genai.py
cat << 'EOF' > /genai.py
#!/usr/bin/env python3
from google import genai
from google.genai.types import HttpOptions, Part

def main():
    client = genai.Client(http_options=HttpOptions(api_version="v1"))
    response = client.models.generate_content(
        model="gemini-2.0-flash-001",
        contents=[
            "What is shown in this image?",
            Part.from_uri(
                file_uri="https://storage.googleapis.com/cloud-samples-data/generative-ai/image/scones.jpg",
                mime_type="image/jpeg",
            ),
        ],
    )
    print("==== Gemini Response ====")
    print(response.text)

if __name__ == "__main__":
    main()
EOF

echo "${GREEN}✔ File /genai.py đã tạo thành công${RESET}"

# ================= Env setup =================
echo "${YELLOW}${BOLD}==> Export ENV...${RESET}"
export GOOGLE_CLOUD_PROJECT=$(gcloud projects list --format="value(projectId)" --limit=1)
export GOOGLE_CLOUD_LOCATION==$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export GOOGLE_GENAI_USE_VERTEXAI=True
echo "${GREEN}✔ Env đã được set${RESET}"

# ================= Run =================
echo "${YELLOW}${BOLD}==> Run genai.py...${RESET}"
/usr/bin/python3 /genai.py