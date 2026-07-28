#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Color configuration
# ============================================================
RESET="\033[0m"
BOLD="\033[1m"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# ============================================================
# Helper functions
# ============================================================
print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "============================================================"
  echo "       Cloud Functions Thumbnail Lab - ePlus.DEV"
  echo "============================================================"
  echo -e "${RESET}"
}

print_step() {
  echo
  echo -e "${BLUE}${BOLD}$1${RESET}"
}

prompt_required() {
  local variable_name="$1"
  local prompt_text="$2"
  local prompt_color="$3"
  local value=""

  while [[ -z "${value}" ]]; do
    echo -ne "${prompt_color}${BOLD}${prompt_text}${RESET}"
    read -r value

    if [[ -z "${value}" ]]; then
      echo -e "${RED}Error: This value cannot be empty.${RESET}"
    fi
  done

  printf -v "${variable_name}" '%s' "${value}"
  export "${variable_name}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

grant_project_role() {
  local service_account="$1"
  local role="$2"
  local description="$3"
  local attempt
  local log_file="${TEMP_DIR}/iam-role.log"

  for ((attempt = 1; attempt <= 8; attempt++)); do
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${service_account}" \
      --role="${role}" \
      --condition=None \
      --quiet >"${log_file}" 2>&1; then

      echo -e "${GREEN}✓ ${description}${RESET}"
      return 0
    fi

    echo -e "${YELLOW}Warning: ${description} is not ready yet (${attempt}/8).${RESET}"

    if [[ "${attempt}" -lt 8 ]]; then
      sleep 15
    fi
  done

  echo -e "${RED}Error: Unable to grant role ${role}.${RESET}"
  cat "${log_file}"
  return 1
}

prepare_service_agent() {
  local service_name="$1"
  local service_account="$2"
  local role="$3"
  local description="$4"

  local attempt
  local identity_log="${TEMP_DIR}/service-identity.log"
  local iam_log="${TEMP_DIR}/service-agent-iam.log"

  for ((attempt = 1; attempt <= 12; attempt++)); do
    # The command may return HTTP 429 when the Service Usage API
    # mutation quota has temporarily been exceeded.
    gcloud beta services identity create \
      --service="${service_name}" \
      --project="${PROJECT_ID}" \
      >"${identity_log}" 2>&1 || true

    # Try assigning the role even if the previous command failed.
    # The service agent may already exist.
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${service_account}" \
      --role="${role}" \
      --condition=None \
      --quiet >"${iam_log}" 2>&1; then

      echo -e "${GREEN}✓ ${description}${RESET}"
      return 0
    fi

    echo -e "${YELLOW}Warning: Preparing ${description} (${attempt}/12)...${RESET}"

    if [[ "${attempt}" -lt 12 ]]; then
      sleep 15
    fi
  done

  echo -e "${RED}Error: Unable to prepare ${description}.${RESET}"

  echo
  echo -e "${YELLOW}Service Identity output:${RESET}"
  cat "${identity_log}" || true

  echo
  echo -e "${YELLOW}IAM output:${RESET}"
  cat "${iam_log}" || true

  return 1
}

# ============================================================
# Start
# ============================================================
clear
print_banner

# ============================================================
# Check required commands
# ============================================================
for required_command in gcloud curl sed; do
  if ! command_exists "${required_command}"; then
    echo -e "${RED}Error: Required command not found: ${required_command}${RESET}"
    exit 1
  fi
done

# ============================================================
# Step 1: Detect project and region automatically
# ============================================================
print_step "[1/8] Reading Google Cloud configuration..."

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo -e "${RED}Error: No active Google Cloud project was found.${RESET}"
  exit 1
fi

PROJECT_NUMBER="$(
  gcloud projects describe "${PROJECT_ID}" \
    --format="value(projectNumber)"
)"

REGION="$(
  gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
    2>/dev/null || true
)"

if [[ -z "${REGION}" ]]; then
  echo -e "${RED}Error: The default region was not found in the project metadata.${RESET}"
  echo -e "${YELLOW}Verify that the lab has provided a default region.${RESET}"
  exit 1
fi

export PROJECT_ID
export PROJECT_NUMBER
export REGION

gcloud config set compute/region "${REGION}" >/dev/null

echo -e "${GREEN}✓ Project ID     : ${PROJECT_ID}${RESET}"
echo -e "${GREEN}✓ Project number : ${PROJECT_NUMBER}${RESET}"
echo -e "${GREEN}✓ Region         : ${REGION}${RESET}"

# ============================================================
# Step 2: Enter lab variables
# ============================================================
print_step "[2/8] Enter the values provided by your lab..."

echo

prompt_required \
  BUCKET_NAME \
  "Enter BUCKET_NAME   : " \
  "${CYAN}"

prompt_required \
  TOPIC_NAME \
  "Enter TOPIC_NAME    : " \
  "${MAGENTA}"

prompt_required \
  FUNCTION_NAME \
  "Enter FUNCTION_NAME : " \
  "${YELLOW}"

# Remove gs:// and a trailing slash if they were entered
BUCKET_NAME="${BUCKET_NAME#gs://}"
BUCKET_NAME="${BUCKET_NAME%/}"

export BUCKET_NAME
export TOPIC_NAME
export FUNCTION_NAME

# ============================================================
# Validate input values
# ============================================================
if [[ ! "${BUCKET_NAME}" =~ ^[a-z0-9][a-z0-9._-]+[a-z0-9]$ ]]; then
  echo -e "${RED}Error: Invalid bucket name: ${BUCKET_NAME}${RESET}"
  exit 1
fi

if [[ ! "${TOPIC_NAME}" =~ ^[A-Za-z][A-Za-z0-9._~+%-]+$ ]]; then
  echo -e "${RED}Error: Invalid Pub/Sub topic name: ${TOPIC_NAME}${RESET}"
  exit 1
fi

if [[ ! "${FUNCTION_NAME}" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
  echo -e "${RED}Error: Invalid function name: ${FUNCTION_NAME}${RESET}"
  exit 1
fi

echo
echo -e "${WHITE}${BOLD}Configuration summary${RESET}"
echo -e "${BLUE}------------------------------------------------------------${RESET}"
echo -e "Project  : ${WHITE}${PROJECT_ID}${RESET}"
echo -e "Region   : ${GREEN}${REGION}${RESET}"
echo -e "Bucket   : ${CYAN}${BUCKET_NAME}${RESET}"
echo -e "Topic    : ${MAGENTA}${TOPIC_NAME}${RESET}"
echo -e "Function : ${YELLOW}${FUNCTION_NAME}${RESET}"
echo -e "${BLUE}------------------------------------------------------------${RESET}"

# ============================================================
# Step 3: Enable required APIs
# ============================================================
print_step "[3/8] Enabling required APIs..."

API_LOG="${TEMP_DIR}/enable-apis.log"
APIS_ENABLED=false

for attempt in 1 2 3 4; do
  if gcloud services enable \
    cloudfunctions.googleapis.com \
    eventarc.googleapis.com \
    run.googleapis.com \
    pubsub.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    storage.googleapis.com \
    --project="${PROJECT_ID}" \
    >"${API_LOG}" 2>&1; then

    APIS_ENABLED=true
    break
  fi

  echo -e "${YELLOW}Warning: API enable attempt ${attempt}/4 failed.${RESET}"

  if [[ "${attempt}" -lt 4 ]]; then
    sleep 15
  fi
done

if [[ "${APIS_ENABLED}" != true ]]; then
  echo -e "${RED}Error: Failed to enable the required APIs.${RESET}"
  cat "${API_LOG}"
  exit 1
fi

echo -e "${GREEN}✓ Required APIs enabled.${RESET}"

# ============================================================
# Step 4: Prepare service agents and IAM permissions
# ============================================================
print_step "[4/8] Preparing Eventarc and Cloud Storage permissions..."

EVENTARC_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com"
STORAGE_SERVICE_AGENT="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
COMPUTE_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

prepare_service_agent \
  "eventarc.googleapis.com" \
  "${EVENTARC_SERVICE_AGENT}" \
  "roles/eventarc.serviceAgent" \
  "Eventarc Service Agent"

prepare_service_agent \
  "storage.googleapis.com" \
  "${STORAGE_SERVICE_AGENT}" \
  "roles/pubsub.publisher" \
  "Cloud Storage Pub/Sub Publisher permission"

grant_project_role \
  "${COMPUTE_SERVICE_ACCOUNT}" \
  "roles/eventarc.eventReceiver" \
  "Eventarc Event Receiver permission"

grant_project_role \
  "${COMPUTE_SERVICE_ACCOUNT}" \
  "roles/run.invoker" \
  "Cloud Run Invoker permission"

# ============================================================
# Step 5: Create the bucket and Pub/Sub topic
# ============================================================
print_step "[5/8] Creating the Cloud Storage bucket and Pub/Sub topic..."

if gcloud storage buckets describe \
  "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  >/dev/null 2>&1; then

  echo -e "${YELLOW}Warning: Bucket already exists: gs://${BUCKET_NAME}${RESET}"
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access

  echo -e "${GREEN}✓ Bucket created: gs://${BUCKET_NAME}${RESET}"
fi

if gcloud pubsub topics describe "${TOPIC_NAME}" \
  --project="${PROJECT_ID}" \
  >/dev/null 2>&1; then

  echo -e "${YELLOW}Warning: Topic already exists: ${TOPIC_NAME}${RESET}"
else
  gcloud pubsub topics create "${TOPIC_NAME}" \
    --project="${PROJECT_ID}"

  echo -e "${GREEN}✓ Topic created: ${TOPIC_NAME}${RESET}"
fi

# ============================================================
# Step 6: Create the Cloud Function source code
# ============================================================
print_step "[6/8] Preparing the Cloud Function source code..."

WORK_DIR="${HOME}/quicklab"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');
const { Storage } = require('@google-cloud/storage');
const { PubSub } = require('@google-cloud/pubsub');
const sharp = require('sharp');

const storage = new Storage();
const pubsub = new PubSub();

functions.cloudEvent('__FUNCTION_NAME__', async cloudEvent => {
  const event = cloudEvent.data;

  const fileName = event.name;
  const bucketName = event.bucket;
  const topicName = process.env.TOPIC_NAME;

  console.log(`Event: ${JSON.stringify(event)}`);

  if (!fileName || !bucketName) {
    console.error('The event does not contain a bucket name or object name.');
    return;
  }

  if (!topicName) {
    throw new Error('The TOPIC_NAME environment variable is missing.');
  }

  if (fileName.includes('64x64_thumbnail')) {
    console.log(
      `gs://${bucketName}/${fileName} is already a thumbnail.`
    );
    return;
  }

  const fileNameParts = fileName.split('.');

  if (fileNameParts.length < 2) {
    console.log(`The file does not have a supported extension: ${fileName}`);
    return;
  }

  const fileExtension =
    fileNameParts[fileNameParts.length - 1].toLowerCase();

  const supportedExtensions = ['png', 'jpg', 'jpeg'];

  if (!supportedExtensions.includes(fileExtension)) {
    console.log(
      `gs://${bucketName}/${fileName} is not a supported image file.`
    );
    return;
  }

  const fileNameWithoutExtension = fileName.substring(
    0,
    fileName.length - fileExtension.length - 1
  );

  const thumbnailName =
    `${fileNameWithoutExtension}_64x64_thumbnail.${fileExtension}`;

  const sharpFormat =
    fileExtension === 'jpg' ? 'jpeg' : fileExtension;

  const contentType =
    sharpFormat === 'jpeg' ? 'image/jpeg' : `image/${sharpFormat}`;

  const bucket = storage.bucket(bucketName);
  const originalFile = bucket.file(fileName);
  const thumbnailFile = bucket.file(thumbnailName);

  try {
    console.log(
      `Processing original image: gs://${bucketName}/${fileName}`
    );

    const [imageBuffer] = await originalFile.download();

    const thumbnailBuffer = await sharp(imageBuffer)
      .resize(64, 64, {
        fit: 'inside',
        withoutEnlargement: true,
      })
      .toFormat(sharpFormat)
      .toBuffer();

    await thumbnailFile.save(thumbnailBuffer, {
      metadata: {
        contentType,
      },
    });

    console.log(
      `Thumbnail created: gs://${bucketName}/${thumbnailName}`
    );

    const messageId = await pubsub
      .topic(topicName)
      .publishMessage({
        data: Buffer.from(thumbnailName),
      });

    console.log(
      `Message ${messageId} published to topic ${topicName}`
    );
  } catch (error) {
    console.error('Thumbnail processing failed:', error);
    throw error;
  }
});
EOF

cat > package.json <<'EOF'
{
  "name": "memories-thumbnail-generator",
  "version": "1.0.0",
  "description": "Generate thumbnails for uploaded Cloud Storage images",
  "main": "index.js",
  "scripts": {
    "start": "functions-framework --target=__FUNCTION_NAME__"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.4.5",
    "@google-cloud/pubsub": "^4.11.0",
    "@google-cloud/storage": "^7.16.0",
    "sharp": "^0.33.5"
  },
  "engines": {
    "node": "22"
  }
}
EOF

sed -i \
  "s|__FUNCTION_NAME__|${FUNCTION_NAME}|g" \
  index.js \
  package.json

echo -e "${GREEN}✓ Source code created in ${WORK_DIR}.${RESET}"

# ============================================================
# Step 7: Deploy the Cloud Function
# ============================================================
print_step "[7/8] Deploying the Cloud Functions Gen2 function..."

DEPLOY_LOG="${TEMP_DIR}/deploy.log"
DEPLOY_SUCCESS=false
MAX_DEPLOY_ATTEMPTS=8

for ((attempt = 1; attempt <= MAX_DEPLOY_ATTEMPTS; attempt++)); do
  echo -e "${YELLOW}Deployment attempt ${attempt}/${MAX_DEPLOY_ATTEMPTS}...${RESET}"

  if gcloud functions deploy "${FUNCTION_NAME}" \
    --project="${PROJECT_ID}" \
    --gen2 \
    --runtime="nodejs22" \
    --entry-point="${FUNCTION_NAME}" \
    --source="." \
    --region="${REGION}" \
    --service-account="${COMPUTE_SERVICE_ACCOUNT}" \
    --set-env-vars="TOPIC_NAME=${TOPIC_NAME}" \
    --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
    --trigger-event-filters="bucket=${BUCKET_NAME}" \
    --quiet 2>&1 | tee "${DEPLOY_LOG}"; then

    DEPLOY_SUCCESS=true
    break
  fi

  if [[ "${attempt}" -lt "${MAX_DEPLOY_ATTEMPTS}" ]]; then
    echo
    echo -e "${YELLOW}Warning: Eventarc or IAM permissions may still be propagating.${RESET}"
    echo -e "${YELLOW}The deployment will be retried automatically.${RESET}"
    sleep 30
  fi
done

if [[ "${DEPLOY_SUCCESS}" != true ]]; then
  echo
  echo -e "${RED}Error: Function deployment failed.${RESET}"
  echo -e "${YELLOW}Last deployment output:${RESET}"
  cat "${DEPLOY_LOG}"
  exit 1
fi

echo -e "${GREEN}✓ Cloud Function deployed successfully.${RESET}"

# ============================================================
# Step 8: Upload and verify a test image
# ============================================================
print_step "[8/8] Uploading and checking a test image..."

TEST_IMAGE="travel.jpg"
THUMBNAIL_IMAGE="travel_64x64_thumbnail.jpg"

curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --output "${TEST_IMAGE}" \
  "https://storage.googleapis.com/cloud-training/arc101/travel.jpg"

gcloud storage cp \
  "${TEST_IMAGE}" \
  "gs://${BUCKET_NAME}/${TEST_IMAGE}" \
  --project="${PROJECT_ID}" \
  --quiet

echo -e "${GREEN}✓ Test image uploaded.${RESET}"
echo -e "${YELLOW}Checking whether the thumbnail has been created...${RESET}"

THUMBNAIL_CREATED=false

for attempt in {1..12}; do
  if gcloud storage ls \
    "gs://${BUCKET_NAME}/${THUMBNAIL_IMAGE}" \
    --project="${PROJECT_ID}" \
    >/dev/null 2>&1; then

    THUMBNAIL_CREATED=true
    break
  fi

  echo -e "${YELLOW}Thumbnail check ${attempt}/12...${RESET}"
  sleep 10
done

echo
echo -e "${BLUE}${BOLD}Bucket contents:${RESET}"

gcloud storage ls \
  "gs://${BUCKET_NAME}/" \
  --project="${PROJECT_ID}" || true

echo
echo -e "${CYAN}${BOLD}============================================================${RESET}"

if [[ "${THUMBNAIL_CREATED}" == true ]]; then
  echo -e "${GREEN}${BOLD}   Script completed successfully ✅${RESET}"
  echo -e "${GREEN}   The thumbnail was created successfully.${RESET}"
else
  echo -e "${YELLOW}${BOLD}   The function was deployed successfully.${RESET}"
  echo -e "${YELLOW}   The thumbnail is still being processed.${RESET}"
fi

echo -e "${WHITE}   Project  : ${PROJECT_ID}${RESET}"
echo -e "${GREEN}   Region   : ${REGION}${RESET}"
echo -e "${CYAN}   Bucket   : gs://${BUCKET_NAME}${RESET}"
echo -e "${MAGENTA}   Topic    : ${TOPIC_NAME}${RESET}"
echo -e "${YELLOW}   Function : ${FUNCTION_NAME}${RESET}"
echo -e "${CYAN}   © 2026 ePlus.DEV — All Rights Reserved${RESET}"
echo -e "${CYAN}${BOLD}============================================================${RESET}"