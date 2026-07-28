#!/bin/bash

set -euo pipefail

# ============================================================
# COLORS
# ============================================================
BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'
RESET=$'\033[0m'

BLACK=$'\033[0;90m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'

BG_GREEN=$'\033[42m'

print_step() {
    echo
    echo "${MAGENTA}${BOLD}▶ $1${RESET}"
}

print_success() {
    echo "${GREEN}${BOLD}✔ $1${RESET}"
}

print_error() {
    echo "${RED}${BOLD}✘ $1${RESET}"
}

# ============================================================
# HEADER
# ============================================================
clear

echo "${BLUE}${BOLD}============================================================${RESET}"
echo "${BLUE}${BOLD}          CLOUD VISION CHALLENGE LAB - ePlus.DEV${RESET}"
echo "${BLUE}${BOLD}============================================================${RESET}"
echo

# ============================================================
# STEP 0: AUTO-DETECT PROJECT
# ============================================================
print_step "STEP 0: Detecting Google Cloud project..."

PROJECT_ID="$(
    gcloud config get-value project 2>/dev/null |
    tr -d '\r'
)"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
    print_error "Unable to detect the active PROJECT_ID."
    exit 1
fi

export PROJECT_ID

ACTIVE_ACCOUNT="$(
    gcloud auth list \
        --filter="status:ACTIVE" \
        --format="value(account)" \
        --limit=1
)"

echo "${WHITE}Project ID : ${YELLOW}${PROJECT_ID}${RESET}"
echo "${WHITE}Account    : ${YELLOW}${ACTIVE_ACCOUNT}${RESET}"

print_success "Project detected."

# ============================================================
# STEP 1: ENABLE REQUIRED APIS
# ============================================================
print_step "STEP 1: Enabling required APIs..."

gcloud services enable \
    vision.googleapis.com \
    apikeys.googleapis.com \
    serviceusage.googleapis.com \
    --project="${PROJECT_ID}" \
    --quiet

print_success "Cloud Vision API and API Keys API enabled."

# ============================================================
# STEP 2: AUTO-DETECT BUCKET AND IMAGE
# ============================================================
print_step "STEP 2: Detecting the lab bucket and image..."

find_image_in_bucket() {
    local candidate_bucket="$1"

    gsutil ls -r "gs://${candidate_bucket}/**" 2>/dev/null |
        grep -Ei '\.(jpg|jpeg|png|gif|bmp|webp|tif|tiff)$' |
        head -n 1 || true
}

BUCKET=""
IMAGE_URI=""

# ------------------------------------------------------------
# First preference: PROJECT_ID-bucket
# ------------------------------------------------------------
EXPECTED_BUCKET="${PROJECT_ID}-bucket"

if gsutil ls -b "gs://${EXPECTED_BUCKET}" >/dev/null 2>&1; then
    FOUND_IMAGE="$(find_image_in_bucket "${EXPECTED_BUCKET}")"

    if [[ -n "${FOUND_IMAGE}" ]]; then
        BUCKET="${EXPECTED_BUCKET}"
        IMAGE_URI="${FOUND_IMAGE}"
    fi
fi

# ------------------------------------------------------------
# Fallback: Search all buckets in the project
# ------------------------------------------------------------
if [[ -z "${IMAGE_URI}" ]]; then
    while IFS= read -r BUCKET_URI; do
        CANDIDATE_BUCKET="$(
            echo "${BUCKET_URI}" |
            sed -E 's#^gs://##; s#/$##'
        )"

        [[ -z "${CANDIDATE_BUCKET}" ]] && continue

        FOUND_IMAGE="$(find_image_in_bucket "${CANDIDATE_BUCKET}")"

        if [[ -n "${FOUND_IMAGE}" ]]; then
            BUCKET="${CANDIDATE_BUCKET}"
            IMAGE_URI="${FOUND_IMAGE}"
            break
        fi
    done < <(
        gsutil ls -p "${PROJECT_ID}" 2>/dev/null || true
    )
fi

if [[ -z "${BUCKET}" ]]; then
    print_error "No Cloud Storage bucket containing an image was found."
    echo
    echo "${YELLOW}Available buckets:${RESET}"
    gsutil ls -p "${PROJECT_ID}" 2>/dev/null || true
    exit 1
fi

if [[ -z "${IMAGE_URI}" ]]; then
    print_error "No supported image was found in the available buckets."
    exit 1
fi

echo "${WHITE}Bucket    : ${YELLOW}gs://${BUCKET}${RESET}"
echo "${WHITE}Image URI : ${YELLOW}${IMAGE_URI}${RESET}"

print_success "Bucket and image detected automatically."

# ============================================================
# STEP 3: MAKE IMAGE PUBLIC
# ============================================================
print_step "STEP 3: Making the image publicly accessible..."

# First try object ACL, matching the original lab approach.
if gsutil acl ch -u AllUsers:R "${IMAGE_URI}" >/dev/null 2>&1; then
    print_success "Image made public using object ACL."
else
    echo "${YELLOW}Object ACL is unavailable. Trying bucket IAM...${RESET}"

    gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
        --member="allUsers" \
        --role="roles/storage.objectViewer" \
        --project="${PROJECT_ID}" \
        --quiet >/dev/null

    print_success "Bucket objects made public using IAM."
fi

# Verify public HTTP access.
OBJECT_PATH="${IMAGE_URI#gs://${BUCKET}/}"
ENCODED_OBJECT_PATH="$(
    python3 -c \
        'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="/"))' \
        "${OBJECT_PATH}"
)"

PUBLIC_IMAGE_URL="https://storage.googleapis.com/${BUCKET}/${ENCODED_OBJECT_PATH}"

HTTP_STATUS="$(
    curl -L -s \
        -o /dev/null \
        -w "%{http_code}" \
        "${PUBLIC_IMAGE_URL}"
)"

if [[ "${HTTP_STATUS}" == "200" ]]; then
    print_success "Public image access verified."
else
    echo "${YELLOW}Warning: HTTP verification returned ${HTTP_STATUS}.${RESET}"
    echo "${YELLOW}The Vision API will still be tested using the GCS URI.${RESET}"
fi

# ============================================================
# STEP 4: CREATE OR REUSE API KEY
# ============================================================
print_step "STEP 4: Creating an API key restricted to Vision API..."

KEY_DISPLAY_NAME="vision-lab-key"

KEY_NAME="$(
    gcloud services api-keys list \
        --project="${PROJECT_ID}" \
        --filter="displayName=${KEY_DISPLAY_NAME}" \
        --format="value(name)" \
        --limit=1 2>/dev/null || true
)"

if [[ -n "${KEY_NAME}" ]]; then
    echo "${YELLOW}Existing vision-lab-key found. Reusing it.${RESET}"

    # Ensure the existing key remains restricted to Vision API.
    gcloud services api-keys update "${KEY_NAME}" \
        --project="${PROJECT_ID}" \
        --api-target="service=vision.googleapis.com" \
        --quiet >/dev/null
else
    KEY_NAME="$(
        gcloud services api-keys create \
            --project="${PROJECT_ID}" \
            --display-name="${KEY_DISPLAY_NAME}" \
            --api-target="service=vision.googleapis.com" \
            --format="value(name)" \
            --quiet
    )"
fi

if [[ -z "${KEY_NAME}" ]]; then
    # Retry finding the key after asynchronous propagation.
    for ATTEMPT in $(seq 1 12); do
        KEY_NAME="$(
            gcloud services api-keys list \
                --project="${PROJECT_ID}" \
                --filter="displayName=${KEY_DISPLAY_NAME}" \
                --format="value(name)" \
                --limit=1 2>/dev/null || true
        )"

        [[ -n "${KEY_NAME}" ]] && break
        sleep 5
    done
fi

if [[ -z "${KEY_NAME}" ]]; then
    print_error "The API key resource could not be created."
    exit 1
fi

API_KEY=""

for ATTEMPT in $(seq 1 12); do
    API_KEY="$(
        gcloud services api-keys get-key-string "${KEY_NAME}" \
            --project="${PROJECT_ID}" \
            --format="value(keyString)" \
            --quiet 2>/dev/null || true
    )"

    [[ -n "${API_KEY}" ]] && break

    echo "${YELLOW}Waiting for API key propagation (${ATTEMPT}/12)...${RESET}"
    sleep 5
done

if [[ -z "${API_KEY}" ]]; then
    print_error "Unable to retrieve the API key string."
    exit 1
fi

export API_KEY

# Save for future Cloud Shell sessions.
touch "${HOME}/.bashrc"
sed -i '/^export API_KEY=/d' "${HOME}/.bashrc"
printf 'export API_KEY=%q\n' "${API_KEY}" >>"${HOME}/.bashrc"

MASKED_KEY="${API_KEY:0:8}...${API_KEY: -4}"

echo "${WHITE}Key name  : ${YELLOW}${KEY_NAME}${RESET}"
echo "${WHITE}API_KEY   : ${YELLOW}${MASKED_KEY}${RESET}"

print_success "API key created, restricted and exported as API_KEY."

# ============================================================
# VISION REQUEST FUNCTIONS
# ============================================================
create_request_json() {
    local feature_type="$1"

    cat >request.json <<JSON
{
  "requests": [
    {
      "image": {
        "source": {
          "gcsImageUri": "${IMAGE_URI}"
        }
      },
      "features": [
        {
          "type": "${feature_type}",
          "maxResults": 10
        }
      ]
    }
  ]
}
JSON
}

call_vision_api() {
    local feature_type="$1"
    local output_file="$2"

    create_request_json "${feature_type}"

    for ATTEMPT in $(seq 1 12); do
        HTTP_CODE="$(
            curl -sS \
                -X POST \
                -H "Content-Type: application/json" \
                --data-binary @request.json \
                "https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}" \
                -o "${output_file}" \
                -w "%{http_code}"
        )"

        HAS_RESPONSE="$(
            jq -r '
                if (
                    (.responses | type == "array") and
                    ((.responses | length) > 0) and
                    (.responses[0].error == null)
                )
                then "yes"
                else "no"
                end
            ' "${output_file}" 2>/dev/null || echo "no"
        )"

        if [[ "${HTTP_CODE}" == "200" && "${HAS_RESPONSE}" == "yes" ]]; then
            return 0
        fi

        echo "${YELLOW}${feature_type} attempt ${ATTEMPT}/12 was not ready.${RESET}"

        if [[ "${ATTEMPT}" -lt 12 ]]; then
            sleep 5
        fi
    done

    print_error "${feature_type} request failed."
    echo

    jq . "${output_file}" 2>/dev/null || cat "${output_file}"
    exit 1
}

# ============================================================
# STEP 5: TEXT DETECTION
# ============================================================
print_step "STEP 5: Performing TEXT_DETECTION..."

call_vision_api \
    "TEXT_DETECTION" \
    "text-response.json"

gsutil cp \
    text-response.json \
    "gs://${BUCKET}/text-response.json" >/dev/null

print_success "TEXT_DETECTION completed."
print_success "Uploaded gs://${BUCKET}/text-response.json"

echo
echo "${CYAN}${BOLD}Detected text:${RESET}"

DETECTED_TEXT="$(
    jq -r '
        .responses[0].textAnnotations[0].description // empty
    ' text-response.json
)"

if [[ -n "${DETECTED_TEXT}" ]]; then
    echo "${DETECTED_TEXT}"
else
    echo "No text annotations were returned."
fi

# ============================================================
# STEP 6: LANDMARK DETECTION
# ============================================================
print_step "STEP 6: Performing LANDMARK_DETECTION..."

call_vision_api \
    "LANDMARK_DETECTION" \
    "landmark-response.json"

gsutil cp \
    landmark-response.json \
    "gs://${BUCKET}/landmark-response.json" >/dev/null

print_success "LANDMARK_DETECTION completed."
print_success "Uploaded gs://${BUCKET}/landmark-response.json"

echo
echo "${CYAN}${BOLD}Detected landmarks:${RESET}"

DETECTED_LANDMARKS="$(
    jq -r '
        .responses[0].landmarkAnnotations[]?.description
    ' landmark-response.json
)"

if [[ -n "${DETECTED_LANDMARKS}" ]]; then
    echo "${DETECTED_LANDMARKS}"
else
    echo "No landmark annotations were returned."
fi

# Important:
# Leave request.json with LANDMARK_DETECTION for lab validation.
create_request_json "LANDMARK_DETECTION"

# ============================================================
# STEP 7: FINAL VALIDATION
# ============================================================
print_step "STEP 7: Validating lab outputs..."

for LOCAL_FILE in \
    request.json \
    text-response.json \
    landmark-response.json
do
    if [[ ! -s "${LOCAL_FILE}" ]]; then
        print_error "${LOCAL_FILE} is missing or empty."
        exit 1
    fi
done

if ! jq -e '
    .requests[0].features[0].type == "LANDMARK_DETECTION"
' request.json >/dev/null; then
    print_error "request.json is not configured for LANDMARK_DETECTION."
    exit 1
fi

gsutil ls \
    "gs://${BUCKET}/text-response.json" \
    "gs://${BUCKET}/landmark-response.json" >/dev/null

print_success "All required local and Cloud Storage files verified."

# ============================================================
# COMPLETE
# ============================================================
echo
echo "${BG_GREEN}${BLACK}${BOLD}============================================================${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}                 LAB EXECUTED SUCCESSFULLY                  ${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}============================================================${RESET}"
echo

echo "${GREEN}✔ Project detected automatically${RESET}"
echo "${GREEN}✔ Bucket detected automatically${RESET}"
echo "${GREEN}✔ Image detected automatically${RESET}"
echo "${GREEN}✔ Image made publicly accessible${RESET}"
echo "${GREEN}✔ API key exported as API_KEY${RESET}"
echo "${GREEN}✔ TEXT_DETECTION completed${RESET}"
echo "${GREEN}✔ LANDMARK_DETECTION completed${RESET}"
echo "${GREEN}✔ request.json left as LANDMARK_DETECTION${RESET}"
echo

echo "${WHITE}${BOLD}Project:${RESET}"
echo "${YELLOW}${PROJECT_ID}${RESET}"

echo
echo "${WHITE}${BOLD}Bucket:${RESET}"
echo "${YELLOW}gs://${BUCKET}${RESET}"

echo
echo "${WHITE}${BOLD}Image:${RESET}"
echo "${YELLOW}${IMAGE_URI}${RESET}"

echo
echo "${WHITE}${BOLD}Uploaded responses:${RESET}"
echo "${YELLOW}gs://${BUCKET}/text-response.json${RESET}"
echo "${YELLOW}gs://${BUCKET}/landmark-response.json${RESET}"

echo
echo "${CYAN}${BOLD}Click Check my progress for all three objectives.${RESET}"