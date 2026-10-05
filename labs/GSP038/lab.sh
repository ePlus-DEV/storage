#!/bin/bash

# ============================================================
#  Google Cloud Natural Language API Lab
#  Automated Lab Script
#
#  Copyright (c) ePlus.DEV
# ============================================================

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

line() {
  echo -e "${CYAN}============================================================${RESET}"
}

step() {
  echo
  echo -e "${BLUE}▶ $1${RESET}"
}

success() {
  echo -e "${GREEN}✔ $1${RESET}"
}

warning() {
  echo -e "${YELLOW}⚠ $1${RESET}"
}

error() {
  echo -e "${RED}✘ $1${RESET}"
}

# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------
main() {

  clear 2>/dev/null || true

  line
  echo -e "${MAGENTA}${WHITE}   Cloud Natural Language API Lab - ePlus.DEV${RESET}"
  line
  echo

  # ==========================================================
  # LAB CONFIGURATION
  # ==========================================================

  step "Detecting Google Cloud configuration..."

  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

  if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    error "Unable to detect PROJECT_ID."
    echo "Make sure you are running this inside Qwiklabs Cloud Shell."
    return 1
  fi

  PROJECT_NUMBER="$(
    gcloud projects describe "$PROJECT_ID" \
      --format="value(projectNumber)" \
      2>/dev/null
  )"

  # Region / Zone are not required by Natural Language API,
  # but detect them automatically for consistency with other labs.
  REGION="$(
    gcloud compute project-info describe \
      --project="$PROJECT_ID" \
      --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
      2>/dev/null || true
  )"

  ZONE="$(
    gcloud compute project-info describe \
      --project="$PROJECT_ID" \
      --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
      2>/dev/null || true
  )"

  [[ -z "$REGION" ]] && REGION="N/A (not required)"
  [[ -z "$ZONE" ]] && ZONE="N/A (not required)"

  BUCKET="${PROJECT_ID}-nlp"
  KEY_DISPLAY_NAME="nlp-lab-eplus-dev"

  success "PROJECT_ID     : $PROJECT_ID"
  success "PROJECT_NUMBER : ${PROJECT_NUMBER:-N/A}"
  success "REGION         : $REGION"
  success "ZONE           : $ZONE"
  success "BUCKET         : gs://${BUCKET}"

  # ==========================================================
  # ENABLE REQUIRED APIs
  # ==========================================================

  step "Enabling required APIs..."

  gcloud services enable \
    language.googleapis.com \
    apikeys.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

  if [[ $? -eq 0 ]]; then
    success "Cloud Natural Language API enabled."
    success "API Keys API enabled."
  else
    warning "API enable returned an error."
    warning "Continuing because the lab may have already enabled them."
  fi

  # ==========================================================
  # TASK 1 - CREATE API KEY
  # ==========================================================

  line
  echo -e "${MAGENTA}TASK 1 - CREATE API KEY${RESET}"
  line

  step "Looking for an existing lab API key..."

  KEY_RESOURCE="$(
    gcloud services api-keys list \
      --project="$PROJECT_ID" \
      --filter="displayName=${KEY_DISPLAY_NAME}" \
      --format="value(name)" \
      --limit=1 \
      2>/dev/null
  )"

  if [[ -z "$KEY_RESOURCE" ]]; then

    step "Creating API key restricted to Cloud Natural Language API..."

    gcloud services api-keys create \
      --display-name="$KEY_DISPLAY_NAME" \
      --api-target="service=language.googleapis.com" \
      --project="$PROJECT_ID" \
      --quiet >/tmp/nlp-key-create.log 2>&1

    CREATE_STATUS=$?

    if [[ $CREATE_STATUS -ne 0 ]]; then
      error "Unable to create API key."
      cat /tmp/nlp-key-create.log
      echo
      warning "If the lab blocks API key creation from CLI:"
      echo "APIs & Services → Credentials → Create credentials → API key"
      echo "Restrict it to: Cloud Natural Language API"
      return 1
    fi

    success "API key created."

    # Fetch newly-created resource
    KEY_RESOURCE="$(
      gcloud services api-keys list \
        --project="$PROJECT_ID" \
        --filter="displayName=${KEY_DISPLAY_NAME}" \
        --sort-by="~createTime" \
        --format="value(name)" \
        --limit=1 \
        2>/dev/null
    )"

  else
    success "Existing API key found."
  fi

  if [[ -z "$KEY_RESOURCE" ]]; then
    error "API key resource could not be found."
    return 1
  fi

  step "Retrieving API key string..."

  API_KEY="$(
    gcloud services api-keys get-key-string \
      "$KEY_RESOURCE" \
      --project="$PROJECT_ID" \
      --format="value(keyString)" \
      2>/dev/null
  )"

  if [[ -z "$API_KEY" ]]; then
    error "Unable to obtain API key string."
    return 1
  fi

  export API_KEY

  success "API_KEY created and loaded."
  echo -e "${CYAN}Key preview: ${API_KEY:0:8}****************${RESET}"

  # ==========================================================
  # WAIT FOR API KEY PROPAGATION
  # ==========================================================

  step "Checking API key propagation..."

  KEY_READY=false

  for ATTEMPT in 1 2 3 4 5 6; do

    CHECK_RESPONSE="$(
      curl -s \
        "https://language.googleapis.com/v1/documents:analyzeEntities?key=${API_KEY}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{
          "document": {
            "type": "PLAIN_TEXT",
            "content": "Google Cloud"
          },
          "encodingType": "UTF8"
        }'
    )"

    if ! echo "$CHECK_RESPONSE" | grep -q '"error"'; then
      KEY_READY=true
      success "API key is ready."
      break
    fi

    warning "API key is still propagating... attempt ${ATTEMPT}/6"

    if [[ $ATTEMPT -lt 6 ]]; then
      sleep 5
    fi
  done

  if [[ "$KEY_READY" != "true" ]]; then
    warning "API key may still be propagating."
    warning "Continuing with the lab."
  fi

  # ==========================================================
  # TASK 2 - ENTITY ANALYSIS REQUEST
  # ==========================================================

  line
  echo -e "${MAGENTA}TASK 2 - CREATE ENTITY ANALYSIS REQUEST${RESET}"
  line

  step "Creating request.json..."

  cat > request.json <<'EOF'
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "Joanne Rowling, who writes under the pen names J. K. Rowling and Robert Galbraith, is a British novelist and screenwriter who wrote the Harry Potter fantasy series."
  },
  "encodingType": "UTF8"
}
EOF

  success "request.json created."

  echo
  cat request.json

  # ==========================================================
  # TASK 3 - CALL NATURAL LANGUAGE API
  # ==========================================================

  line
  echo -e "${MAGENTA}TASK 3 - ENTITY ANALYSIS${RESET}"
  line

  step "Calling documents:analyzeEntities..."

  curl \
    "https://language.googleapis.com/v1/documents:analyzeEntities?key=${API_KEY}" \
    -s \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @request.json \
    > result.json

  if grep -q '"error"' result.json; then
    error "Entity Analysis returned an error:"
    cat result.json
    return 1
  fi

  success "Entity Analysis completed."

  echo
  echo -e "${CYAN}Entity Analysis result:${RESET}"

  if command -v jq >/dev/null 2>&1; then
    jq . result.json
  else
    cat result.json
  fi

  # ----------------------------------------------------------
  # Ensure required NLP bucket exists
  # ----------------------------------------------------------

  step "Checking Cloud Storage bucket gs://${BUCKET}..."

  if gcloud storage buckets describe \
      "gs://${BUCKET}" \
      --project="$PROJECT_ID" \
      >/dev/null 2>&1; then

    success "Bucket already exists."

  else

    warning "Bucket not found. Creating it..."

    gcloud storage buckets create \
      "gs://${BUCKET}" \
      --project="$PROJECT_ID" \
      --location=US \
      --quiet

    if [[ $? -ne 0 ]]; then
      error "Unable to create gs://${BUCKET}"
      return 1
    fi

    success "Bucket created."
  fi

  # ----------------------------------------------------------
  # Upload result.json - REQUIRED BY GRADER
  # ----------------------------------------------------------

  step "Uploading result.json..."

  gcloud storage cp \
    result.json \
    "gs://${BUCKET}/result.json"

  if [[ $? -eq 0 ]]; then
    success "Uploaded:"
    echo -e "${GREEN}gs://${BUCKET}/result.json${RESET}"
  else
    error "Failed to upload result.json."
    return 1
  fi

  # ==========================================================
  # TASK 4 - SENTIMENT ANALYSIS
  # ==========================================================

  line
  echo -e "${MAGENTA}TASK 4 - SENTIMENT ANALYSIS${RESET}"
  line

  step "Creating sentiment request..."

  cat > request.json <<'EOF'
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "Harry Potter is the best book. I think everyone should read it."
  },
  "encodingType": "UTF8"
}
EOF

  step "Calling documents:analyzeSentiment..."

  curl \
    "https://language.googleapis.com/v1/documents:analyzeSentiment?key=${API_KEY}" \
    -s \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @request.json \
    > sentiment.json

  if grep -q '"error"' sentiment.json; then
    warning "Sentiment API returned:"
    cat sentiment.json
  else
    success "Sentiment Analysis completed."

    if command -v jq >/dev/null 2>&1; then
      jq . sentiment.json
    else
      cat sentiment.json
    fi
  fi

  # ==========================================================
  # TASK 5 - ENTITY SENTIMENT ANALYSIS
  # ==========================================================

  line
  echo -e "${MAGENTA}TASK 5 - ENTITY SENTIMENT ANALYSIS${RESET}"
  line

  cat > request.json <<'EOF'
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "I liked the sushi but the service was terrible."
  },
  "encodingType": "UTF8"
}
EOF

  step "Calling documents:analyzeEntitySentiment..."

  curl \
    "https://language.googleapis.com/v1/documents:analyzeEntitySentiment?key=${API_KEY}" \
    -s \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @request.json \
    > entity-sentiment.json

  if grep -q '"error"' entity-sentiment.json; then
    warning "Entity Sentiment API returned:"
    cat entity-sentiment.json
  else
    success "Entity Sentiment Analysis completed."

    if command -v jq >/dev/null 2>&1; then
      jq . entity-sentiment.json
    else
      cat entity-sentiment.json
    fi
  fi

  # ==========================================================
  # TASK 6 - SYNTAX ANALYSIS
  # ==========================================================

  line
  echo -e "${MAGENTA}TASK 6 - SYNTAX ANALYSIS${RESET}"
  line

  cat > request.json <<'EOF'
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "Joanne Rowling is a British novelist, screenwriter and film producer."
  },
  "encodingType": "UTF8"
}
EOF

  step "Calling documents:analyzeSyntax..."

  curl \
    "https://language.googleapis.com/v1/documents:analyzeSyntax?key=${API_KEY}" \
    -s \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @request.json \
    > syntax.json

  if grep -q '"error"' syntax.json; then
    warning "Syntax API returned:"
    cat syntax.json
  else
    success "Syntax Analysis completed."

    if command -v jq >/dev/null 2>&1; then
      jq . syntax.json
    else
      cat syntax.json
    fi
  fi

  # ==========================================================
  # TASK 7 - MULTILINGUAL NLP
  # ==========================================================

  line
  echo -e "${MAGENTA}TASK 7 - MULTILINGUAL NLP / JAPANESE${RESET}"
  line

  cat > request.json <<'EOF'
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "日本のグーグルのオフィスは、東京の六本木ヒルズにあります"
  }
}
EOF

  step "Calling analyzeEntities with Japanese text..."

  curl \
    "https://language.googleapis.com/v1/documents:analyzeEntities?key=${API_KEY}" \
    -s \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @request.json \
    > japanese-entities.json

  if grep -q '"error"' japanese-entities.json; then
    warning "Japanese Entity API returned:"
    cat japanese-entities.json
  else
    success "Japanese NLP completed."

    if command -v jq >/dev/null 2>&1; then
      jq . japanese-entities.json
    else
      cat japanese-entities.json
    fi
  fi

  # ==========================================================
  # FINAL VERIFICATION
  # ==========================================================

  line
  echo -e "${MAGENTA}FINAL VERIFICATION${RESET}"
  line

  echo
  echo -e "${CYAN}Local files:${RESET}"
  ls -lh \
    request.json \
    result.json \
    sentiment.json \
    entity-sentiment.json \
    syntax.json \
    japanese-entities.json \
    2>/dev/null

  echo
  step "Checking result.json in Cloud Storage..."

  gcloud storage ls -l \
    "gs://${BUCKET}/result.json" \
    2>/dev/null

  if [[ $? -eq 0 ]]; then
    success "Required result.json exists in Cloud Storage."
  else
    warning "Could not verify uploaded result.json."
  fi

  echo
  line
  echo -e "${GREEN}✔ CLOUD NATURAL LANGUAGE LAB COMPLETED${RESET}"
  echo -e "${MAGENTA}              ePlus.DEV${RESET}"
  line

  echo
  echo -e "${WHITE}Now click:${RESET}"
  echo -e "${GREEN}  ✔ Check my progress - Create an API Key${RESET}"
  echo -e "${GREEN}  ✔ Check my progress - Make an Entity Analysis Request and save the result${RESET}"
  echo
}

main