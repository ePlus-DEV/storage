#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -Eeuo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]] && command -v tput >/dev/null 2>&1; then
  GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; CYAN="$(tput setaf 6)"
  MAGENTA="$(tput setaf 5)"; WHITE="$(tput setaf 7)"; BOLD="$(tput bold)"; RESET="$(tput sgr0)"
else
  GREEN=''; YELLOW=''; CYAN=''; MAGENTA=''; WHITE=''; BOLD=''; RESET=''
fi
printf '%s\n' 'ePlus.DEV – Starting Execution' 'GSP540: Engineer AI Agents with ADK'

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set a valid lab project.' >&2; exit 1; }
export PROJECT_ID
export PATH="$PATH:$HOME/.local/bin"

# ==============================================================================
# PHASE 1: SILENT AUTHENTICATION & ENVIRONMENT SETUP
# ==============================================================================
echo "${YELLOW}[*] Phase 1: Installing ADK and checking keyless credentials...${RESET}"
python3 -m pip install google-adk --quiet
# Do not mint long-lived keys for the default Compute service account.
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo 'ERROR: Application Default Credentials are unavailable. Run gcloud auth application-default login in the authorized lab Cloud Shell, then rerun.' >&2
  exit 1
fi

echo -e "\n${YELLOW}[*] Phase 2: Downloading and dynamically locating the ADK project...${RESET}"
WORK_DIR="$HOME/gsp540-adk-work"
mkdir -p "$WORK_DIR/extracted"
cd "$WORK_DIR"
if ! gcloud storage cp "gs://${PROJECT_ID}-bucket/adk_project.zip" ./adk_project.zip; then
  gcloud storage cp "gs://${PROJECT_ID}/adk_project.zip" ./adk_project.zip
fi
unzip -q -o ./adk_project.zip -d "$WORK_DIR/extracted"
TARGET_DIR="$(find "$WORK_DIR/extracted" -type f -name requirements.txt -printf '%h\n' -quit)"
[[ -n "$TARGET_DIR" ]] || { echo 'ERROR: requirements.txt not found in extracted lab archive.' >&2; exit 1; }
cd "$TARGET_DIR"
echo "[+] Lab project: $TARGET_DIR"
python3 -m pip install -r requirements.txt --quiet

# ==============================================================================
# PHASE 2: DYNAMIC PYTHON PATCHING
# ==============================================================================
echo -e "\n${CYAN}[*] Phase 3: Architecting the Python Patcher for Broken Agents...${RESET}"

cat << 'EOF' > patch_agents.py
import os, re

project_id = os.environ.get('PROJECT_ID', '')
env_content = f"""GOOGLE_GENAI_USE_VERTEXAI=true
GOOGLE_CLOUD_PROJECT={project_id}
GOOGLE_CLOUD_LOCATION=global
MODEL=gemini-2.5-flash
"""

# Enforce environment files
for d in ["my_google_search_agent", "geo_validator", "llm_auditor"]:
    if os.path.exists(d):
        with open(os.path.join(d, ".env"), "w") as f:
            f.write(env_content)

# Fix Task 2: Travel Scout (my_google_search_agent)
if os.path.exists("my_google_search_agent/agent.py"):
    with open("my_google_search_agent/agent.py", "r") as f:
        content = f.read()
    
    # Uncomment safely if hashed out
    content = re.sub(r'#\s*from google\.adk\.tools import google_search', 'from google.adk.tools import google_search', content)
    content = re.sub(r'#\s*tools=\[google_search\]', 'tools=[google_search]', content)
    
    # Inject if entirely missing
    if 'from google.adk.tools import google_search' not in content:
        content = 'from google.adk.tools import google_search\n' + content
    if 'tools=[google_search]' not in content:
        content = re.sub(r'(Agent\()', r'\1\n    tools=[google_search],', content)
        
    with open("my_google_search_agent/agent.py", "w") as f:
        f.write(content)

# Fix Task 4: Geo Validator (geo_validator)
if os.path.exists("geo_validator/agent.py"):
    with open("geo_validator/agent.py", "r") as f:
        content = f.read()

    class_def = "\nfrom pydantic import BaseModel\nclass CountryCapital(BaseModel):\n    capital: str\n"
    if 'CountryCapital' not in content:
        content = class_def + content

    if 'output_schema=' not in content:
        content = re.sub(r'(Agent\()', r'\1\n    output_schema=CountryCapital,\n    disallow_transfer_to_parent=True,\n    disallow_transfer_to_peers=True,\n', content)

    with open("geo_validator/agent.py", "w") as f:
        f.write(content)

# Fix Task 5: Brochure Auditor (llm_auditor)
if os.path.exists("llm_auditor/agent.py"):
    with open("llm_auditor/agent.py", "r") as f:
        content = f.read()

    # Safely strip hashes from the import without triggering an IndentationError
    lines = content.split('\n')
    for i, line in enumerate(lines):
        if 'import' in line and 'reviser_agent' in line and line.strip().startswith('#'):
            lines[i] = line.lstrip(' #')
    content = '\n'.join(lines)
    
    if 'from .sub_agents.reviser.agent import reviser_agent' not in content:
        content = 'from .sub_agents.reviser.agent import reviser_agent\n' + content
        
    # Forcefully inject the reviser_agent directly into the array
    content = re.sub(r'critic_agent\s*,?\s*\]', 'critic_agent, reviser_agent]', content)

    with open("llm_auditor/agent.py", "w") as f:
        f.write(content)

print("[+] All Python Agent files have been successfully patched and structured!")
EOF

python3 patch_agents.py

# ==============================================================================
# PHASE 3: EXECUTION & GRADING TRIGGERS
# ==============================================================================
echo -e "\n${MAGENTA}[*] Phase 4: Simulating CLI Agent interactions for Grading...${RESET}"

echo -e "\n[*] --- Running Travel Scout (Tasks 2 & 3) ---"
adk run my_google_search_agent "What are some major events in Tokyo in 2025?"
sleep 3
adk run my_google_search_agent "What is the currency exchange rate for Japan?"
sleep 3

echo -e "\n[*] --- Running Geo Validator programmatically (Task 4) ---"
python3 geo_validator/agent.py
sleep 3

echo -e "\n[*] --- Running Brochure Auditor Pipeline (Task 5) ---"
adk run llm_auditor "Double check this: You can take a direct train from Hawaii to Japan."
sleep 3

echo -e "\n${GREEN}${BOLD}====================================================================${RESET}"
echo "${GREEN}${BOLD}>>> CLI COMMANDS FINISHED; REVIEW AGENT OUTPUT AND LAB GRADER <<<${RESET}"
echo "${GREEN}${BOLD}>>> Verify each task manually using Check my progress.         <<<${RESET}"
echo "${GREEN}${BOLD}====================================================================${RESET}"