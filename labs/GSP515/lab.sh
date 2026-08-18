#!/bin/bash

# ============================================================
# GSP515 - Explore Generative AI with Gemini API
# Full One-Script Solution
# © ePlus.DEV
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

banner() {
  echo
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}======================================================================${NC}"
}

countdown() {
  local seconds="$1"

  while [ "$seconds" -gt 0 ]; do
    printf "\rRetrying in %2d seconds..." "$seconds"
    sleep 1
    seconds=$((seconds - 1))
  done

  printf "\r                              \r"
}

refresh_token() {
  ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null)
}

main() {

clear

echo -e "${BLUE}"
echo "   ____  ____  ____  ____  _  ____"
echo "  / ___|/ ___||  _ \| ___|| || ___|"
echo " | |  _ \___ \| |_) |___ \| ||___ \\"
echo " | |_| | ___) |  __/ ___) | | ___) |"
echo "  \____||____/|_|   |____/|_||____/"
echo
echo " Gemini API Challenge Lab"
echo " One-Script Solution"
echo " © ePlus.DEV"
echo -e "${NC}"

# ============================================================
# ENVIRONMENT
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
LOCATION="global"
API_ENDPOINT="aiplatform.googleapis.com"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo -e "${RED}ERROR: Could not detect Project ID.${NC}"
  return 1
fi

# ============================================================
# REQUIRED MODEL INPUT
# ============================================================

banner "MODEL CONFIGURATION"

while true; do

  echo -ne "${YELLOW}Enter MODEL_ID (example: gemini-3.5-flash): ${NC}"
  read -r MODEL_ID

  MODEL_ID=$(echo "$MODEL_ID" | xargs)

  if [[ -n "$MODEL_ID" ]]; then
    break
  fi

  echo -e "${RED}MODEL_ID is required.${NC}"
  echo

done

BASE_URL="https://${API_ENDPOINT}/v1/projects/${PROJECT_ID}/locations/${LOCATION}/publishers/google/models/${MODEL_ID}"

echo
echo -e "${GREEN}✓ Configuration loaded${NC}"
echo
echo -e "Project ID : ${YELLOW}${PROJECT_ID}${NC}"
echo -e "Location   : ${YELLOW}${LOCATION}${NC}"
echo -e "Model      : ${YELLOW}${MODEL_ID}${NC}"

# ============================================================
# STEP 1 - ENABLE APIs
# ============================================================

banner "[1/6] Enabling required APIs"

gcloud services enable \
  aiplatform.googleapis.com \
  notebooks.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

if [[ $? -ne 0 ]]; then
  echo -e "${RED}✗ Failed to enable APIs.${NC}"
  return 1
fi

echo -e "${GREEN}✓ Required APIs enabled.${NC}"

sleep 8

# ============================================================
# TASK 1 - CURL GEMINI
# ============================================================

banner "[2/6] TASK 1 - Generate text using Gemini"

echo -e "Model  : ${YELLOW}${MODEL_ID}${NC}"
echo -e "Prompt : ${YELLOW}Why is the sky blue?${NC}"
echo

TASK1_OK=false

for attempt in {1..6}; do

  refresh_token

  HTTP_CODE=$(curl -sS \
    --max-time 180 \
    -o /tmp/gsp515_task1.json \
    -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}:streamGenerateContent" \
    -d '{
      "contents": [
        {
          "role": "user",
          "parts": [
            {
              "text": "Why is the sky blue?"
            }
          ]
        }
      ]
    }')

  if [[ "$HTTP_CODE" == "200" ]]; then
    TASK1_OK=true
    break
  fi

  echo -e "${YELLOW}Attempt ${attempt}/6 - HTTP ${HTTP_CODE}${NC}"

  cat /tmp/gsp515_task1.json 2>/dev/null
  echo

  countdown 15

done

if [[ "$TASK1_OK" != true ]]; then
  echo -e "${RED}✗ TASK 1 failed.${NC}"
  return 1
fi

echo -e "${GREEN}✓ ${MODEL_ID} successfully called via curl.${NC}"
echo

python3 <<'PY'
import json

try:
    data = json.load(open("/tmp/gsp515_task1.json"))

    if not isinstance(data, list):
        data = [data]

    for obj in data:
        for c in obj.get("candidates", []):
            for p in c.get("content", {}).get("parts", []):
                if p.get("text"):
                    print(p["text"], end="")
except Exception:
    print(open("/tmp/gsp515_task1.json").read())
PY

echo
echo
echo -e "${GREEN}✓ TASK 1 COMPLETE${NC}"

# ============================================================
# FIND WORKBENCH INSTANCE
# ============================================================

banner "[3/6] Detecting Agent Platform Workbench"

WB_URI=$(gcloud workbench instances list \
  --project="$PROJECT_ID" \
  --uri \
  2>/dev/null | head -n1)

INSTANCE=""
ZONE=""

if [[ -n "$WB_URI" ]]; then

  INSTANCE=$(echo "$WB_URI" | awk -F/ '{print $NF}')

  ZONE=$(echo "$WB_URI" \
    | sed -n 's#.*locations/\([^/]*\)/instances/.*#\1#p')

fi

# Fallback to Compute Engine list
if [[ -z "$INSTANCE" || -z "$ZONE" ]]; then

  echo -e "${YELLOW}Workbench API lookup incomplete. Trying VM detection...${NC}"

  VM_LINE=$(gcloud compute instances list \
    --project="$PROJECT_ID" \
    --format='value(name,zone.basename())' \
    2>/dev/null \
    | grep -Ei 'jupyter|workbench|generative|gemini' \
    | head -n1)

  if [[ -z "$VM_LINE" ]]; then
    VM_LINE=$(gcloud compute instances list \
      --project="$PROJECT_ID" \
      --format='value(name,zone.basename())' \
      2>/dev/null \
      | head -n1)
  fi

  INSTANCE=$(echo "$VM_LINE" | awk '{print $1}')
  ZONE=$(echo "$VM_LINE" | awk '{print $2}')

fi

if [[ -z "$INSTANCE" || -z "$ZONE" ]]; then

  echo -e "${RED}✗ Workbench instance could not be detected.${NC}"
  echo
  echo "Open:"
  echo "Agent Platform > Notebooks > Workbench"
  echo
  return 1

fi

echo -e "${GREEN}✓ Workbench detected${NC}"
echo
echo -e "Instance : ${YELLOW}${INSTANCE}${NC}"
echo -e "Zone     : ${YELLOW}${ZONE}${NC}"

# ============================================================
# DETECT SSH METHOD
# ============================================================

EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)' \
  2>/dev/null)

SSH_EXTRA=()

if [[ -z "$EXTERNAL_IP" ]]; then
  echo -e "${YELLOW}No external IP detected. Using IAP tunnel.${NC}"
  SSH_EXTRA+=(--tunnel-through-iap)
else
  echo -e "${GREEN}✓ External IP available.${NC}"
fi

# ============================================================
# CREATE NOTEBOOK PATCHER
# ============================================================

cat > /tmp/gsp515_patch.py <<'PYEOF'
#!/usr/bin/env python3

import glob
import json
import os
import re
import shutil
import sys


def source_text(cell):
    src = cell.get("source", "")
    if isinstance(src, list):
        return "".join(src)
    return src


def set_source(cell, text):
    cell["source"] = text.splitlines(True)
    cell["execution_count"] = None

    if cell.get("cell_type") == "code":
        cell["outputs"] = []


def locate():
    preferred = glob.glob(
        "/home/**/gemini-explorer-challenge.ipynb",
        recursive=True,
    )

    if preferred:
        print(preferred[0])
        return 0

    notebooks = glob.glob("/home/**/*.ipynb", recursive=True)

    for path in notebooks:
        try:
            with open(path, encoding="utf-8") as f:
                nb = json.load(f)

            text = "\n".join(
                source_text(c)
                for c in nb.get("cells", [])
            )

            if "Task 3.1" in text and "Task 4" in text:
                print(path)
                return 0

        except Exception:
            continue

    return 1


def patch(path, project, model):

    with open(path, encoding="utf-8") as f:
        nb = json.load(f)

    backup = path + ".eplus-backup"

    if not os.path.exists(backup):
        shutil.copy2(path, backup)

    replacements = {
        "Task 3.1": f'''# Task 3.1

model_id = "{model}"
''',

        "Task 3.2": '''# Task 3.2

get_current_weather_func = FunctionDeclaration(
    name="get_current_weather",
    description="Get the current weather in a given location",
    parameters={
        "type": "object",
        "properties": {
            "location": {
                "type": "string",
                "description": "Location"
            }
        },
        "required": ["location"],
    },
)
''',

        "Task 3.3": '''# Task 3.3

weather_tool = Tool(
    function_declarations=[get_current_weather_func],
)
''',

        "Task 3.4": '''# Task 3.4

prompt = "What is the weather like in Boston?"

response = client.models.generate_content(
    model=model_id,
    contents=prompt,
    config=GenerateContentConfig(
        tools=[weather_tool],
        temperature=0,
    ),
)

# Make the weather-related data explicitly visible in cell output.
function_call = None

for part in response.candidates[0].content.parts:
    if getattr(part, "function_call", None):
        function_call = part.function_call
        break

print("Weather related data:")
print("---------------------")

if function_call:
    print("Function :", function_call.name)
    print("Arguments:", function_call.args)
else:
    print("No function call returned.")
    try:
        print(response.text)
    except Exception:
        pass

response
''',

        "Task 4.1": f'''# Task 4.1

multimodal_model = "{model}"
''',

        "Task 4.2": '''# Task 4.2 Generate a video description

prompt = """
What is shown in this video?
Where should I go to see it?
What are the top 5 places in the world that look like this?
"""

video = Part.from_uri(
    file_uri="gs://github-repo/img/gemini/multimodality_usecases_overview/mediterraneansea.mp4",
    mime_type="video/mp4",
)

contents = [prompt, video]

responses = client.models.generate_content_stream(
    model=multimodal_model,
    contents=contents,
)

print("-------Prompt--------")
print_multimodal_prompt(contents)

print("\\n-------Response--------")

for response in responses:
    print(response.text, end="")
''',
    }

    found = set()

    for cell in nb.get("cells", []):

        if cell.get("cell_type") != "code":
            continue

        src = source_text(cell)

        # Keep notebook's preconfigured setup but ensure current
        # Qwiklabs project and global location are used.
        if (
            "PROJECT_ID" in src
            and "LOCATION" in src
            and ("genai.Client" in src or "Getting Started" in src)
        ):
            src = re.sub(
                r'(?m)^PROJECT_ID\s*=.*$',
                f'PROJECT_ID = "{project}"',
                src,
            )

            src = re.sub(
                r'(?m)^LOCATION\s*=.*$',
                'LOCATION = "global"',
                src,
            )

            set_source(cell, src)

        for marker, replacement in replacements.items():

            if marker in src:
                set_source(cell, replacement)
                found.add(marker)
                break

    missing = set(replacements) - found

    if missing:
        print(
            "ERROR: Missing task cells:",
            ", ".join(sorted(missing)),
            file=sys.stderr,
        )

        print(
            "Available task markers:",
            file=sys.stderr,
        )

        for cell in nb.get("cells", []):
            src = source_text(cell)

            for line in src.splitlines():
                if "Task " in line:
                    print(" ", line, file=sys.stderr)

        return 2

    with open(path, "w", encoding="utf-8") as f:
        json.dump(nb, f, ensure_ascii=False, indent=1)

    print("PATCH_OK")
    return 0


def output_text(cell):

    result = []

    for output in cell.get("outputs", []):

        if output.get("output_type") == "stream":

            text = output.get("text", "")

            if isinstance(text, list):
                result.extend(text)
            else:
                result.append(text)

        data = output.get("data", {})

        text = data.get("text/plain")

        if isinstance(text, list):
            result.extend(text)
        elif text:
            result.append(text)

        if output.get("output_type") == "error":
            result.append(
                output.get("ename", "")
                + ": "
                + output.get("evalue", "")
            )

    return "".join(result)


def verify(path):

    with open(path, encoding="utf-8") as f:
        nb = json.load(f)

    task3 = ""
    task4 = ""

    for cell in nb.get("cells", []):

        src = source_text(cell)

        if "Task 3.4" in src:
            task3 = output_text(cell)

        if "Task 4.2" in src:
            task4 = output_text(cell)

    print("")
    print("TASK 3 NOTEBOOK OUTPUT")
    print("======================")

    print(task3[:3000] if task3 else "NO OUTPUT")

    weather_ok = (
        "get_current_weather" in task3
        and "Boston" in task3
    )

    print("")
    print("Weather output check:",
          "PASS" if weather_ok else "FAIL")

    print("")
    print("TASK 4 NOTEBOOK OUTPUT")
    print("======================")

    print(task4[:3000] if task4 else "NO OUTPUT")

    video_ok = (
        len(task4.strip()) > 100
        and "Error" not in task4[:100]
    )

    print("")
    print("Video output check:",
          "PASS" if video_ok else "FAIL")

    return 0 if weather_ok and video_ok else 3


if __name__ == "__main__":

    if len(sys.argv) < 2:
        sys.exit(1)

    action = sys.argv[1]

    if action == "locate":
        sys.exit(locate())

    if action == "patch":
        sys.exit(
            patch(
                sys.argv[2],
                sys.argv[3],
                sys.argv[4],
            )
        )

    if action == "verify":
        sys.exit(verify(sys.argv[2]))

    sys.exit(1)
PYEOF

# ============================================================
# CREATE REMOTE EXECUTOR
# ============================================================

cat > /tmp/gsp515_execute.sh <<'SHEOF'
#!/bin/bash

NB="$1"

if [[ ! -f "$NB" ]]; then
  echo "Notebook not found: $NB"
  exit 1
fi

OWNER=$(stat -c '%U' "$NB")

echo "Notebook owner: $OWNER"

JUPYTER=$(sudo -u "$OWNER" -H bash -lc \
  'command -v jupyter 2>/dev/null || true')

if [[ -z "$JUPYTER" && -x /opt/conda/bin/jupyter ]]; then
  JUPYTER="/opt/conda/bin/jupyter"
fi

if [[ -z "$JUPYTER" ]]; then
  echo "ERROR: jupyter command not found."
  exit 1
fi

echo "Jupyter: $JUPYTER"

DIR=$(dirname "$NB")
FILE=$(basename "$NB")

echo
echo "Executing notebook..."
echo

sudo -u "$OWNER" -H bash -lc \
  "cd \"$DIR\" && \"$JUPYTER\" nbconvert \
    --to notebook \
    --execute \
    --inplace \
    --ExecutePreprocessor.timeout=900 \
    \"$FILE\""

exit $?
SHEOF

chmod +x /tmp/gsp515_execute.sh

# ============================================================
# UPLOAD PATCHER
# ============================================================

echo
echo -e "${YELLOW}Uploading notebook automation files...${NC}"

gcloud compute scp \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  "${SSH_EXTRA[@]}" \
  /tmp/gsp515_patch.py \
  /tmp/gsp515_execute.sh \
  "${INSTANCE}:/tmp/"

if [[ $? -ne 0 ]]; then
  echo -e "${RED}✗ Could not connect to Workbench VM.${NC}"
  return 1
fi

# ============================================================
# LOCATE NOTEBOOK
# ============================================================

NB_PATH=$(gcloud compute ssh "$INSTANCE" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  "${SSH_EXTRA[@]}" \
  --command="sudo python3 /tmp/gsp515_patch.py locate" \
  2>/dev/null \
  | tail -n1)

if [[ -z "$NB_PATH" ]]; then

  echo -e "${RED}✗ gemini challenge notebook not found.${NC}"

  echo
  echo "Notebooks available on Workbench:"

  gcloud compute ssh "$INSTANCE" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --quiet \
    "${SSH_EXTRA[@]}" \
    --command="sudo find /home -type f -name '*.ipynb' 2>/dev/null | head -20"

  return 1

fi

echo
echo -e "${GREEN}✓ Challenge notebook found${NC}"
echo -e "Notebook : ${YELLOW}${NB_PATH}${NC}"

# ============================================================
# PATCH NOTEBOOK
# ============================================================

banner "[4/6] TASK 3 - Insert weather function call"

PATCH_RESULT=$(gcloud compute ssh "$INSTANCE" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  "${SSH_EXTRA[@]}" \
  --command="sudo python3 /tmp/gsp515_patch.py patch '$NB_PATH' '$PROJECT_ID' '$MODEL_ID'" \
  2>&1)

echo "$PATCH_RESULT"

if ! echo "$PATCH_RESULT" | grep -q "PATCH_OK"; then
  echo -e "${RED}✗ Notebook patch failed.${NC}"
  return 1
fi

echo
echo -e "${GREEN}✓ Task 3.1 inserted${NC}"
echo -e "${GREEN}✓ Task 3.2 get_current_weather inserted${NC}"
echo -e "${GREEN}✓ Task 3.3 weather_tool inserted${NC}"
echo -e "${GREEN}✓ Task 3.4 Boston weather prompt inserted${NC}"
echo -e "${GREEN}✓ Weather-related output printing inserted${NC}"
echo -e "${GREEN}✓ Task 4 video cells inserted${NC}"

# ============================================================
# EXECUTE NOTEBOOK
# ============================================================

banner "[5/6] Executing Workbench notebook"

EXEC_OK=false

for attempt in {1..3}; do

  echo -e "${YELLOW}Notebook execution attempt ${attempt}/3...${NC}"

  gcloud compute ssh "$INSTANCE" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --quiet \
    "${SSH_EXTRA[@]}" \
    --command="sudo bash /tmp/gsp515_execute.sh '$NB_PATH'"

  STATUS=$?

  if [[ "$STATUS" == "0" ]]; then
    EXEC_OK=true
    break
  fi

  echo
  echo -e "${YELLOW}Notebook execution failed or received a temporary API error.${NC}"

  if [[ "$attempt" -lt 3 ]]; then
    echo -e "${YELLOW}Waiting 60 seconds before retry...${NC}"
    countdown 60
  fi

done

if [[ "$EXEC_OK" != true ]]; then

  echo -e "${RED}✗ Notebook could not be executed successfully.${NC}"
  echo
  echo "The notebook was patched successfully."
  echo "You can open JupyterLab and run all cells manually if required."

  return 1

fi

echo
echo -e "${GREEN}✓ Notebook execution completed.${NC}"

# ============================================================
# VERIFY NOTEBOOK OUTPUT
# ============================================================

banner "[6/6] Verifying Task 3 and Task 4 outputs"

VERIFY_OUTPUT=$(gcloud compute ssh "$INSTANCE" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  "${SSH_EXTRA[@]}" \
  --command="sudo python3 /tmp/gsp515_patch.py verify '$NB_PATH'" \
  2>&1)

VERIFY_STATUS=$?

echo "$VERIFY_OUTPUT"

echo

if [[ "$VERIFY_STATUS" == "0" ]]; then

  echo -e "${GREEN}✓ Weather related data exists in Task 3 cell output.${NC}"
  echo -e "${GREEN}✓ Video description exists in Task 4 cell output.${NC}"

else

  echo -e "${YELLOW}Notebook executed, but automatic output verification was incomplete.${NC}"

fi

# ============================================================
# FINISH
# ============================================================

banner "GSP515 COMPLETE"

echo -e "${GREEN}✓ TASK 1 - Gemini called via curl${NC}"
echo -e "${GREEN}✓ TASK 3 - Function call inserted into Workbench notebook${NC}"
echo -e "${GREEN}✓ TASK 3 - Weather data printed in cell output${NC}"
echo -e "${GREEN}✓ TASK 4 - Video analysis inserted into Workbench notebook${NC}"
echo -e "${GREEN}✓ Notebook executed${NC}"

echo
echo -e "Project ID : ${YELLOW}${PROJECT_ID}${NC}"
echo -e "Model      : ${YELLOW}${MODEL_ID}${NC}"
echo -e "Workbench  : ${YELLOW}${INSTANCE}${NC}"
echo -e "Notebook   : ${YELLOW}${NB_PATH}${NC}"

echo
echo -e "${YELLOW}Now click Check my progress for all checkpoints.${NC}"

echo
echo -e "${CYAN}© ePlus.DEV${NC}"

return 0
}

main "$@"