#!/bin/bash

# =====================================================================
#  GOOGLE DOCS NATURAL LANGUAGE SENTIMENT LAB
#  Copyright © ePlus.DEV
# =====================================================================

set -uo pipefail

# ---------------------------------------------------------------------
# COLORS
# ---------------------------------------------------------------------
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  MAGENTA="$(tput setaf 5)"
  CYAN="$(tput setaf 6)"
  WHITE="$(tput setaf 7)"
  BOLD="$(tput bold)"
  RESET="$(tput sgr0)"
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  WHITE=""
  BOLD=""
  RESET=""
fi

separator() {
  printf '%*s\n' 70 '' | tr ' ' '='
}

step() {
  echo
  echo "${CYAN}${BOLD}[$1] $2${RESET}"
  separator
}

success() {
  echo "${GREEN}✓ $1${RESET}"
}

warning() {
  echo "${YELLOW}⚠ $1${RESET}"
}

fail() {
  echo "${RED}✗ $1${RESET}" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

clear 2>/dev/null || true

echo "${MAGENTA}${BOLD}"
separator
echo "            GOOGLE NATURAL LANGUAGE API LAB"
echo "                       © ePlus.DEV"
separator
echo "${RESET}"

# =====================================================================
# 1. CHECK ENVIRONMENT
# =====================================================================
step "1/7" "Checking Google Cloud environment"

command_exists gcloud || fail "gcloud command was not found."
command_exists curl || fail "curl command was not found."

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  fail "No active Google Cloud project was detected."
fi

if [[ -z "${ACCOUNT}" || "${ACCOUNT}" == "(unset)" ]]; then
  fail "No active Google Cloud account was detected."
fi

echo "Project ID : ${BOLD}${PROJECT_ID}${RESET}"
echo "Account    : ${BOLD}${ACCOUNT}${RESET}"

gcloud config set project "${PROJECT_ID}" --quiet >/dev/null 2>&1 ||
  fail "Unable to configure project ${PROJECT_ID}."

success "Google Cloud environment detected."

# =====================================================================
# 2. ENABLE APIS
# =====================================================================
step "2/7" "Enabling required Google Cloud APIs"

if ! gcloud services enable \
  language.googleapis.com \
  apikeys.googleapis.com \
  serviceusage.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet; then
  fail "Unable to enable the required APIs."
fi

success "Cloud Natural Language API enabled."
success "API Keys API enabled."
success "Service Usage API enabled."

# =====================================================================
# 3. CREATE API KEY WITH KNOWN KEY ID
# =====================================================================
step "3/7" "Creating restricted Natural Language API key"

TIMESTAMP="$(date +%s)"
RANDOM_SUFFIX="$(printf '%04d' "$((RANDOM % 10000))")"

KEY_ID="nl-docs-${TIMESTAMP}-${RANDOM_SUFFIX}"
KEY_DISPLAY_NAME="Natural Language Docs ePlus.DEV ${TIMESTAMP}"
KEY_RESOURCE="projects/${PROJECT_ID}/locations/global/keys/${KEY_ID}"

echo "Key ID      : ${KEY_ID}"
echo "Key resource: ${KEY_RESOURCE}"

CREATE_OUTPUT="$(
  gcloud services api-keys create \
    --project="${PROJECT_ID}" \
    --key-id="${KEY_ID}" \
    --display-name="${KEY_DISPLAY_NAME}" \
    --api-target="service=language.googleapis.com" \
    --quiet 2>&1
)"
CREATE_STATUS=$?

if [[ ${CREATE_STATUS} -ne 0 ]]; then
  echo "${CREATE_OUTPUT}"

  if echo "${CREATE_OUTPUT}" | grep -qi "already exists"; then
    warning "The API key already exists. It will be reused."
  else
    fail "Unable to start API key creation."
  fi
else
  success "API key creation request accepted."
fi

# =====================================================================
# 4. WAIT FOR THE ACTUAL KEY RESOURCE
# =====================================================================
step "4/7" "Waiting for API key resource"

KEY_READY="false"

for ATTEMPT in $(seq 1 30); do
  if gcloud services api-keys describe "${KEY_RESOURCE}" \
    --project="${PROJECT_ID}" \
    --format="value(name)" \
    --quiet >/tmp/eplus-key-description.txt 2>/tmp/eplus-key-describe-error.txt; then

    DESCRIBED_RESOURCE="$(cat /tmp/eplus-key-description.txt)"

    if [[ "${DESCRIBED_RESOURCE}" == "${KEY_RESOURCE}" ]]; then
      KEY_READY="true"
      break
    fi
  fi

  printf "${YELLOW}Waiting for key resource... %s/30${RESET}\r" "${ATTEMPT}"
  sleep 5
done

echo

if [[ "${KEY_READY}" != "true" ]]; then
  cat /tmp/eplus-key-describe-error.txt 2>/dev/null || true

  echo
  echo "${YELLOW}Available API keys in this project:${RESET}"

  gcloud services api-keys list \
    --project="${PROJECT_ID}" \
    --format="table(name.basename(),displayName,state)" \
    2>/dev/null || true

  fail "The API key resource was not created successfully."
fi

success "API key resource is ready."
echo "Resource: ${KEY_RESOURCE}"

# =====================================================================
# 5. RETRIEVE KEY STRING
# =====================================================================
step "5/7" "Retrieving API key value"

API_KEY=""

for ATTEMPT in $(seq 1 20); do
  API_KEY="$(
    gcloud services api-keys get-key-string "${KEY_RESOURCE}" \
      --project="${PROJECT_ID}" \
      --format="value(keyString)" \
      --quiet 2>/tmp/eplus-get-key-error.txt || true
  )"

  if [[ -n "${API_KEY}" && "${API_KEY}" == AIza* ]]; then
    break
  fi

  API_KEY=""
  printf "${YELLOW}Waiting for key string... %s/20${RESET}\r" "${ATTEMPT}"
  sleep 5
done

echo

if [[ -z "${API_KEY}" ]]; then
  cat /tmp/eplus-get-key-error.txt 2>/dev/null || true
  fail "Unable to retrieve the API key value."
fi

printf '%s\n' "${API_KEY}" > natural-language-api-key.txt
chmod 600 natural-language-api-key.txt

success "API key value retrieved successfully."
success "API key saved to natural-language-api-key.txt."

MASKED_KEY="${API_KEY:0:8}************************${API_KEY: -4}"
echo "API key: ${YELLOW}${MASKED_KEY}${RESET}"

# =====================================================================
# 6. GENERATE GOOGLE APPS SCRIPT
# =====================================================================
step "6/7" "Generating complete Google Apps Script"

cat > Code.gs <<'APPS_SCRIPT'
/**
 * @OnlyCurrentDoc
 *
 * Google Docs Natural Language Sentiment Analyzer
 * Copyright © ePlus.DEV
 */

/**
 * Creates the Natural Language Tools menu.
 */
function onOpen() {
  var ui = DocumentApp.getUi();

  ui.createMenu('Natural Language Tools')
    .addItem('Mark Sentiment', 'markSentiment')
    .addToUi();
}

/**
 * Analyzes the currently selected text and applies a background color.
 *
 * Green: positive sentiment
 * Red: negative sentiment
 * Yellow: neutral sentiment
 */
function markSentiment() {
  var POSITIVE_COLOR = '#00ff00';
  var NEGATIVE_COLOR = '#ff0000';
  var NEUTRAL_COLOR = '#ffff00';

  var NEGATIVE_CUTOFF = -0.2;
  var POSITIVE_CUTOFF = 0.2;

  var ui = DocumentApp.getUi();
  var document = DocumentApp.getActiveDocument();
  var selection = document.getSelection();

  if (!selection) {
    ui.alert(
      'No text selected',
      'Please select some English text before choosing Mark Sentiment.',
      ui.ButtonSet.OK
    );
    return;
  }

  var selectedText = getSelectedText();

  if (!selectedText || selectedText.trim() === '') {
    ui.alert(
      'Empty selection',
      'The selected area does not contain editable text.',
      ui.ButtonSet.OK
    );
    return;
  }

  var sentiment = retrieveSentiment(selectedText);
  var color = NEUTRAL_COLOR;

  if (sentiment <= NEGATIVE_CUTOFF) {
    color = NEGATIVE_COLOR;
  } else if (sentiment >= POSITIVE_CUTOFF) {
    color = POSITIVE_COLOR;
  }

  var elements = selection.getSelectedElements();

  for (var i = 0; i < elements.length; i++) {
    var selectedElement = elements[i];
    var documentElement = selectedElement.getElement();

    try {
      var textElement = documentElement.editAsText();

      if (selectedElement.isPartial()) {
        var startIndex = selectedElement.getStartOffset();
        var endIndex = selectedElement.getEndOffsetInclusive();

        textElement.setBackgroundColor(
          startIndex,
          endIndex,
          color
        );
      } else {
        textElement.setBackgroundColor(color);
      }
    } catch (error) {
      console.log(
        'Skipped unsupported element: ' +
        documentElement.getType()
      );
    }
  }

  ui.alert(
    'Sentiment result',
    'Sentiment score: ' + sentiment,
    ui.ButtonSet.OK
  );
}

/**
 * Returns the contents of the selected text.
 *
 * @return {string} Selected text.
 */
function getSelectedText() {
  var selection = DocumentApp
    .getActiveDocument()
    .getSelection();

  var result = '';

  if (!selection) {
    return result;
  }

  var elements = selection.getSelectedElements();

  for (var i = 0; i < elements.length; i++) {
    var selectedElement = elements[i];
    var element = selectedElement.getElement();

    if (selectedElement.isPartial()) {
      var textElement = element.asText();
      var startIndex = selectedElement.getStartOffset();
      var endIndex =
        selectedElement.getEndOffsetInclusive() + 1;

      result += textElement
        .getText()
        .substring(startIndex, endIndex);
    } else {
      try {
        result += element.asText().getText();
      } catch (error) {
        console.log(
          'Skipped non-text element: ' +
          element.getType()
        );
      }
    }
  }

  return result;
}

/**
 * Calls the Cloud Natural Language API.
 *
 * @param {string} line Text to analyze.
 * @return {number} Sentiment score from -1.0 to 1.0.
 */
function retrieveSentiment(line) {
  var apiKey = '__EPLUS_API_KEY__';

  var apiEndpoint =
    'https://language.googleapis.com/v1/documents:analyzeSentiment?key=' +
    apiKey;

  var docDetails = {
    language: 'en',
    type: 'PLAIN_TEXT',
    content: line
  };

  var nlData = {
    document: docDetails,
    encodingType: 'UTF8'
  };

  var nlOptions = {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(nlData),
    muteHttpExceptions: true
  };

  var response = UrlFetchApp.fetch(
    apiEndpoint,
    nlOptions
  );

  var statusCode = response.getResponseCode();
  var responseText = response.getContentText();

  if (statusCode < 200 || statusCode >= 300) {
    throw new Error(
      'Natural Language API error ' +
      statusCode +
      ': ' +
      responseText
    );
  }

  var data = JSON.parse(responseText);
  var sentiment = 0.0;

  if (
    data &&
    data.documentSentiment &&
    typeof data.documentSentiment.score === 'number'
  ) {
    sentiment = data.documentSentiment.score;
  }

  return sentiment;
}
APPS_SCRIPT

sed -i "s|__EPLUS_API_KEY__|${API_KEY}|g" Code.gs

if grep -q "__EPLUS_API_KEY__" Code.gs; then
  fail "Unable to insert the API key into Code.gs."
fi

success "Complete Apps Script generated: Code.gs"

# =====================================================================
# 7. TEST NATURAL LANGUAGE API
# =====================================================================
step "7/7" "Testing Cloud Natural Language API"

TEST_SUCCESS="false"
TEST_RESPONSE=""

for ATTEMPT in $(seq 1 12); do
  TEST_RESPONSE="$(
    curl -sS \
      --request POST \
      --header "Content-Type: application/json" \
      "https://language.googleapis.com/v1/documents:analyzeSentiment?key=${API_KEY}" \
      --data '{
        "document": {
          "type": "PLAIN_TEXT",
          "language": "en",
          "content": "I am very happy. This is a wonderful day."
        },
        "encodingType": "UTF8"
      }' 2>/dev/null || true
  )"

  if echo "${TEST_RESPONSE}" | grep -q '"documentSentiment"'; then
    TEST_SUCCESS="true"
    break
  fi

  printf "${YELLOW}Waiting for API key propagation... %s/12${RESET}\r" "${ATTEMPT}"
  sleep 5
done

echo

if [[ "${TEST_SUCCESS}" == "true" ]]; then
  success "Cloud Natural Language API test passed."

  if command_exists python3; then
    SENTIMENT_SCORE="$(
      printf '%s' "${TEST_RESPONSE}" |
        python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
    print(data.get("documentSentiment", {}).get("score", "unknown"))
except Exception:
    print("unknown")
' 2>/dev/null
    )"

    echo "Test sentiment score: ${BOLD}${SENTIMENT_SCORE}${RESET}"
  fi
else
  warning "The key was created, but the API test has not propagated yet."
  echo "${TEST_RESPONSE}"
fi

rm -f \
  /tmp/eplus-key-description.txt \
  /tmp/eplus-key-describe-error.txt \
  /tmp/eplus-get-key-error.txt

echo
echo "${GREEN}${BOLD}"
separator
echo "                         COMPLETED"
echo "                       © ePlus.DEV"
separator
echo "${RESET}"

echo "${BOLD}Generated files:${RESET}"
echo "  ${CYAN}Code.gs${RESET}"
echo "  ${CYAN}natural-language-api-key.txt${RESET}"

echo
echo "${BOLD}Continue in Google Docs:${RESET}"
echo "  1. Create a new Google Doc using the Qwiklabs account."
echo "  2. Select Extensions → Apps Script."
echo "  3. Delete all default code."
echo "  4. Run ${CYAN}cat Code.gs${RESET} in Cloud Shell."
echo "  5. Copy and paste the complete code into Apps Script."
echo "  6. Save the Apps Script project."
echo "  7. Reload the Google Doc."
echo "  8. Select English text."
echo "  9. Choose Natural Language Tools → Mark Sentiment."
echo " 10. Approve the requested permissions."

echo
echo "${BOLD}Suggested test text:${RESET}"
echo "  ${GREEN}Positive:${RESET} I am very happy. This is wonderful."
echo "  ${RED}Negative:${RESET} I am angry. This is the worst experience."
echo "  ${YELLOW}Neutral :${RESET} The table is in the room."

echo
echo "${MAGENTA}${BOLD}Copyright © ePlus.DEV${RESET}"