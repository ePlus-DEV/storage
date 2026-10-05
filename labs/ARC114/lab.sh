#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#  Analyze Speech & Language with Google APIs - Challenge Lab
#  Automated solution
#  Copyright (c) ePlus.DEV
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
  echo -e "${MAGENTA}${BOLD}"
  echo "============================================================"
  echo "   Analyze Speech & Language with Google APIs"
  echo "                    ePlus.DEV"
  echo "============================================================"
  echo -e "${NC}"
}

step() {
  echo
  echo -e "${BLUE}${BOLD}▶ $1${NC}"
}

success() {
  echo -e "${GREEN}✔ $1${NC}"
}

warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

fail() {
  echo -e "${RED}✘ $1${NC}"
  exit 1
}

trap 'echo -e "\n${RED}✘ Error at line ${LINENO}${NC}"' ERR

banner

# ============================================================
# DETECT PROJECT + LAB VM ZONE
# ============================================================

step "Detecting Google Cloud project..."

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  fail "Unable to detect PROJECT_ID."
fi

success "PROJECT_ID: $PROJECT_ID"

step "Detecting zone of lab-vm automatically..."

ZONE="$(
  gcloud compute instances list \
    --filter="name=lab-vm" \
    --format="value(zone)" \
    --limit=1 \
    2>/dev/null || true
)"

if [[ -z "$ZONE" ]]; then
  fail "Could not find VM: lab-vm"
fi

success "lab-vm ZONE: $ZONE"

# ============================================================
# ENABLE REQUIRED APIS
# ============================================================

step "Enabling required APIs..."

for API in \
  apikeys.googleapis.com \
  language.googleapis.com \
  speech.googleapis.com
do
  echo -e "${CYAN}  → $API${NC}"
  gcloud services enable "$API" \
    --project="$PROJECT_ID" \
    --quiet
done

success "Required APIs enabled."

# ============================================================
# TASK 1 - CREATE API KEY
# ============================================================

step "TASK 1 - Creating API key..."

KEY_DISPLAY_NAME="eplus-nlp-speech-key"

KEY_NAME="$(
  gcloud services api-keys list \
    --project="$PROJECT_ID" \
    --filter="displayName='$KEY_DISPLAY_NAME'" \
    --sort-by="~createTime" \
    --limit=1 \
    --format="value(name)" \
    2>/dev/null || true
)"

if [[ -z "$KEY_NAME" ]]; then

  echo -e "${CYAN}Creating new API key...${NC}"

  CREATE_OUTPUT="$(mktemp)"

  gcloud services api-keys create \
    --project="$PROJECT_ID" \
    --display-name="$KEY_DISPLAY_NAME" \
    --format=json > "$CREATE_OUTPUT"

  KEY_NAME="$(
    python3 - "$CREATE_OUTPUT" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

print(
    data.get("name")
    or data.get("response", {}).get("name")
    or ""
)
PY
  )"

  rm -f "$CREATE_OUTPUT"

  # Fallback in case output format changes
  if [[ -z "$KEY_NAME" ]]; then
    KEY_NAME="$(
      gcloud services api-keys list \
        --project="$PROJECT_ID" \
        --filter="displayName='$KEY_DISPLAY_NAME'" \
        --sort-by="~createTime" \
        --limit=1 \
        --format="value(name)"
    )"
  fi

else
  warning "Existing API key found. Reusing it."
fi

[[ -n "$KEY_NAME" ]] || fail "Unable to find/create API key."

API_KEY="$(
  gcloud services api-keys get-key-string "$KEY_NAME" \
    --project="$PROJECT_ID" \
    --format="value(keyString)"
)"

[[ -n "$API_KEY" ]] || fail "Unable to obtain API key string."

success "API key ready."

echo
echo -e "${YELLOW}API key resource:${NC}"
echo "$KEY_NAME"

# ============================================================
# CREATE REMOTE SCRIPT
# ============================================================

step "Preparing tasks for lab-vm..."

REMOTE_SCRIPT="$(mktemp)"

cat > "$REMOTE_SCRIPT" <<'REMOTE_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step() {
  echo
  echo -e "${BLUE}${BOLD}▶ $1${NC}"
}

success() {
  echo -e "${GREEN}✔ $1${NC}"
}

warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

fail() {
  echo -e "${RED}✘ $1${NC}"
  exit 1
}

: "${API_KEY:?API_KEY was not provided}"

cd "$HOME"

# Save API key for lab tasks
printf '%s\n' "$API_KEY" > "$HOME/api_key.txt"
printf "export API_KEY='%s'\n" "$API_KEY" > "$HOME/.lab_api_key_env"

chmod 600 "$HOME/api_key.txt" "$HOME/.lab_api_key_env"

success "API key saved on lab-vm."

# ------------------------------------------------------------
# Helper - POST with retry
# ------------------------------------------------------------

api_post() {

  local URL="$1"
  local REQUEST_FILE="$2"
  local RESPONSE_FILE="$3"

  local HTTP_CODE=""

  for ATTEMPT in 1 2 3 4 5 6 7 8; do

    echo -e "${CYAN}API request attempt $ATTEMPT/8...${NC}"

    HTTP_CODE="$(
      curl -sS \
        -o "$RESPONSE_FILE" \
        -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json; charset=utf-8" \
        -H "X-goog-api-key: ${API_KEY}" \
        --data-binary "@${REQUEST_FILE}" \
        "$URL" \
        || true
    )"

    if [[ "$HTTP_CODE" == "200" ]] &&
       ! grep -q '"error"' "$RESPONSE_FILE" 2>/dev/null; then
      return 0
    fi

    warning "Request returned HTTP $HTTP_CODE"

    if [[ -s "$RESPONSE_FILE" ]]; then
      cat "$RESPONSE_FILE"
      echo
    fi

    sleep 5
  done

  return 1
}

# ============================================================
# TASK 2
# ENTITY ANALYSIS
# ============================================================

step "TASK 2 - Creating nl_request.json..."

cat > "$HOME/nl_request.json" <<'JSON'
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "With approximately 8.2 million people residing in Boston, the capital city of Massachusetts is one of the largest in the United States."
  },
  "encodingType": "UTF8"
}
JSON

success "nl_request.json created."

step "Calling Natural Language Entity Analysis API..."

api_post \
  "https://language.googleapis.com/v1/documents:analyzeEntities" \
  "$HOME/nl_request.json" \
  "$HOME/nl_response.json" \
  || fail "Natural Language entity request failed."

if ! grep -q '"entities"' "$HOME/nl_response.json"; then
  echo
  cat "$HOME/nl_response.json"
  fail "nl_response.json does not contain entities."
fi

success "nl_response.json created successfully."

echo
echo -e "${CYAN}Natural Language response:${NC}"

python3 -m json.tool "$HOME/nl_response.json" 2>/dev/null \
  || cat "$HOME/nl_response.json"

# ============================================================
# TASK 3
# SPEECH ANALYSIS
# ============================================================

step "TASK 3 - Creating speech_request.json..."

cat > "$HOME/speech_request.json" <<'JSON'
{
  "config": {
    "encoding": "FLAC",
    "languageCode": "en-US"
  },
  "audio": {
    "uri": "gs://cloud-samples-tests/speech/brooklyn.flac"
  }
}
JSON

success "speech_request.json created."

step "Calling Speech-to-Text API..."

api_post \
  "https://speech.googleapis.com/v1/speech:recognize" \
  "$HOME/speech_request.json" \
  "$HOME/speech_response.json" \
  || fail "Speech API request failed."

if ! grep -q '"transcript"' "$HOME/speech_response.json"; then
  echo
  cat "$HOME/speech_response.json"
  fail "speech_response.json does not contain a transcript."
fi

success "speech_response.json created successfully."

echo
echo -e "${CYAN}Speech response:${NC}"

python3 -m json.tool "$HOME/speech_response.json" 2>/dev/null \
  || cat "$HOME/speech_response.json"

# ============================================================
# TASK 4
# SENTIMENT ANALYSIS
# ============================================================

step "TASK 4 - Updating sentiment_analysis.py..."

# This follows Google's Natural Language sentiment tutorial.
cat > "$HOME/sentiment_analysis.py" <<'PYTHON'
"""Demonstrates how to make a simple call to the Natural Language API."""

import argparse

from google.cloud import language_v1


def print_result(annotations):
    score = annotations.document_sentiment.score
    magnitude = annotations.document_sentiment.magnitude

    for index, sentence in enumerate(annotations.sentences):
        sentence_sentiment = sentence.sentiment.score
        print(
            f"Sentence {index} has a sentiment score "
            f"of {sentence_sentiment}"
        )

    print(
        f"Overall Sentiment: score of {score} "
        f"with magnitude of {magnitude}"
    )

    return 0


def analyze(movie_review_filename):
    """Run a sentiment analysis request on text within a passed filename."""

    client = language_v1.LanguageServiceClient()

    with open(movie_review_filename) as review_file:
        content = review_file.read()

    document = language_v1.Document(
        content=content,
        type_=language_v1.Document.Type.PLAIN_TEXT
    )

    annotations = client.analyze_sentiment(
        request={"document": document}
    )

    print_result(annotations)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        "movie_review_filename",
        help="The filename of the movie review you'd like to analyze.",
    )

    args = parser.parse_args()

    analyze(args.movie_review_filename)
PYTHON

success "sentiment_analysis.py updated."

# ------------------------------------------------------------
# Verify Python library
# ------------------------------------------------------------

step "Checking google-cloud-language Python library..."

if python3 -c 'from google.cloud import language_v1' \
    >/dev/null 2>&1; then

  success "google-cloud-language is already installed."

else

  warning "google-cloud-language not found. Installing..."

  python3 -m pip install \
    --user \
    --quiet \
    google-cloud-language

  success "google-cloud-language installed."
fi

# ------------------------------------------------------------
# Download sentiment samples
# ------------------------------------------------------------

step "Downloading sentiment samples..."

rm -rf "$HOME/reviews"
rm -f \
  "$HOME/sentiment-samples.tgz" \
  "$HOME/sentiment-samples.tar"

if command -v gcloud >/dev/null 2>&1; then

  gcloud storage cp \
    gs://cloud-samples-tests/natural-language/sentiment-samples.tgz \
    "$HOME/sentiment-samples.tgz"

else

  gsutil cp \
    gs://cloud-samples-tests/natural-language/sentiment-samples.tgz \
    "$HOME/sentiment-samples.tgz"
fi

success "Sample archive downloaded."

step "Extracting review samples..."

cd "$HOME"

gunzip -f sentiment-samples.tgz
tar -xf sentiment-samples.tar

if [[ ! -f "$HOME/reviews/bladerunner-pos.txt" ]]; then
  fail "reviews/bladerunner-pos.txt was not extracted."
fi

success "Reviews extracted."

# ------------------------------------------------------------
# Execute required sentiment analysis
# ------------------------------------------------------------

step "Running sentiment analysis on bladerunner-pos.txt..."

python3 "$HOME/sentiment_analysis.py" \
  "$HOME/reviews/bladerunner-pos.txt" \
  | tee "$HOME/sentiment_response.txt"

success "Sentiment analysis completed."

# ============================================================
# FINAL VALIDATION
# ============================================================

echo
echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo "                    LAB COMPLETED"
echo "============================================================"
echo -e "${NC}"

echo -e "${GREEN}✔ TASK 1${NC} API key created"
echo -e "${GREEN}✔ TASK 2${NC} nl_request.json / nl_response.json"
echo -e "${GREEN}✔ TASK 3${NC} speech_request.json / speech_response.json"
echo -e "${GREEN}✔ TASK 4${NC} sentiment analysis executed"

echo
echo -e "${CYAN}Files on lab-vm:${NC}"

ls -lh \
  "$HOME/nl_request.json" \
  "$HOME/nl_response.json" \
  "$HOME/speech_request.json" \
  "$HOME/speech_response.json" \
  "$HOME/sentiment_analysis.py" \
  "$HOME/reviews/bladerunner-pos.txt" \
  "$HOME/sentiment_response.txt"

echo
echo -e "${YELLOW}Expected Speech transcript:${NC}"
grep -o '"transcript"[^,}]*' "$HOME/speech_response.json" \
  || true

echo
echo -e "${GREEN}${BOLD}ePlus.DEV - Done!${NC}"
REMOTE_EOF

# ============================================================
# COPY SCRIPT TO VM
# ============================================================

step "Copying automation script to lab-vm..."

SCP_OK=0

for TRY in 1 2 3 4; do

  if gcloud compute scp \
      "$REMOTE_SCRIPT" \
      "lab-vm:/tmp/eplus-nlp-speech.sh" \
      --zone="$ZONE" \
      --project="$PROJECT_ID" \
      --quiet; then

    SCP_OK=1
    break

  fi

  warning "SSH not ready. Retrying..."
  sleep 5
done

[[ "$SCP_OK" == "1" ]] \
  || fail "Could not copy script to lab-vm."

success "Script copied."

# ============================================================
# EXECUTE ON VM
# ============================================================

step "Executing Tasks 2-4 on lab-vm..."

SSH_OK=0

for TRY in 1 2 3 4; do

  if gcloud compute ssh lab-vm \
      --zone="$ZONE" \
      --project="$PROJECT_ID" \
      --quiet \
      --command="chmod +x /tmp/eplus-nlp-speech.sh && API_KEY='$API_KEY' /tmp/eplus-nlp-speech.sh"; then

    SSH_OK=1
    break

  fi

  warning "Execution failed or SSH not ready. Retrying..."
  sleep 5
done

rm -f "$REMOTE_SCRIPT"

[[ "$SSH_OK" == "1" ]] \
  || fail "Remote execution failed."

echo
echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo "       ALL CHALLENGE LAB TASKS FINISHED - ePlus.DEV"
echo "============================================================"
echo -e "${NC}"

echo "PROJECT_ID : $PROJECT_ID"
echo "VM         : lab-vm"
echo "ZONE       : $ZONE"

echo
echo -e "${YELLOW}${BOLD}Now click Check my progress for Task 1 → Task 4.${NC}"