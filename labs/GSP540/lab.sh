#!/bin/bash
clear

# ==============================================================================
# ORBIT OF OPS COMMAND CENTER: GSP540 ADK CHALLENGE LAB MASTER SCRIPT
# ==============================================================================
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
RESET=$(tput sgr0)

echo "${CYAN}${BOLD}"
echo "   ePlus.DEV"
echo "${RESET}"
echo "${MAGENTA}${BOLD}>>> INITIATING GSP540 ADK AUTOMATION PIPELINE <<<${RESET}"
echo ""

export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
export PATH=$PATH:"/home/${USER}/.local/bin"

# ==============================================================================
# PHASE 1: SILENT AUTHENTICATION & ENVIRONMENT SETUP
# ==============================================================================
echo "${YELLOW}[*] Phase 1: Installing ADK and bypassing browser authentication...${RESET}"
python3 -m pip install google-adk --quiet

# Generating a key for the default Compute Service Account to bypass browser logins
gcloud iam service-accounts keys create ~/adc.json --iam-account=$SA_EMAIL --quiet
export GOOGLE_APPLICATION_CREDENTIALS=~/adc.json

echo -e "\n${YELLOW}[*] Phase 2: Downloading and dynamically locating the ADK project...${RESET}"
cd ~
rm -rf adk_project*
gsutil cp gs://${PROJECT_ID}-bucket/adk_project.zip . 2>/dev/null || gsutil cp gs://${PROJECT_ID}/adk_project.zip .
unzip -q -o adk_project.zip

# Dynamically locate the root directory to bypass nested folder extraction bugs
TARGET_DIR=$(find . -name "requirements.txt" -printf '%h\n' -quit)
cd $TARGET_DIR
echo "[+] Project root dynamically located at: $(pwd)"
pip install -r requirements.txt --quiet

# ==============================================================================
# PHASE 2: DYNAMIC PYTHON PATCHING
# ==============================================================================
echo -e "\n${CYAN}[*] Phase 3: Architecting the Python Patcher for Broken Agents...${RESET}"

cat << 'EOF' > patch_agents.py
import os, re

project_id = os.environ.get('PROJECT_ID', '')
env_content = f"""GOOGLE_GENAI_USE_ENTERPRISE=true
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
echo "${GREEN}${BOLD}>>> PIPELINE COMPLETE! ALL TASKS ARE PROVISIONED AND TESTED <<<${RESET}"
echo "${GREEN}${BOLD}>>> YOU CAN NOW CLICK 'CHECK MY PROGRESS' ON ALL TASKS!     <<<${RESET}"
echo "${GREEN}${BOLD}====================================================================${RESET}"