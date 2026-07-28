#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# ANSI color codes
# ============================================================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# ============================================================
# Helper functions
# ============================================================
print_banner() {
  echo -e "${CYAN}============================================================${NC}"
  echo -e "${YELLOW}       Cloud Functions Thumbnail Lab - ePlus.DEV${NC}"
  echo -e "${WHITE}       Copyright (c) 2026 ePlus.DEV${NC}"
  echo -e "${CYAN}============================================================${NC}"
  echo
}

print_step() {
  echo
  echo -e "${BLUE}${1}${NC}"
}

prompt_required() {
  local variable_name="$1"
  local prompt_message="$2"
  local prompt_color="$3"
  local value=""

  while [[ -z "${value}" ]]; do
    echo -ne "${prompt_color}${prompt_message}${NC}"
    read -r value

    if [[ -z "${value}" ]]; then
      echo -e "${RED}Error: This value cannot be empty.${NC}"
    fi
  done

  printf -v "${variable_name}" '%s' "${value}"
  export "${variable_name}"
}

check_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo -e "${RED}Error: Required command not found: ${command_name}${NC}"
    exit 1
  fi
}

grant_project_role() {
  local service_account="$1"
  local role="$2"
  local description="$3"
  local log_file="${TEMP_DIR}/iam-$(echo "${role}" | tr '/.' '--').log"

  for attempt in {1..12}; do
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${service_account}" \
      --role="${role}" \
      --condition=None \
      --quiet >"${log_file}" 2>&1; then

      echo -e "${GREEN}Completed: ${description}${NC}"
      return 0
    fi

    echo -e "${YELLOW}Preparing ${description} (${attempt}/12)...${NC}"

    if [[ "${attempt}" -lt 12 ]]; then
      sleep 15
    fi
  done

  echo -e "${RED}Error: Failed to grant ${description}.${NC}"
  echo
  cat "${log_file}" || true
  return 1
}

grant_topic_role() {
  local service_account="$1"
  local role="$2"
  local description="$3"
  local log_file="${TEMP_DIR}/topic-iam.log"

  for attempt in {1..8}; do
    if gcloud pubsub topics add-iam-policy-binding "${TOPIC_NAME}" \
      --project="${PROJECT_ID}" \
      --member="serviceAccount:${service_account}" \
      --role="${role}" \
      --quiet >"${log_file}" 2>&1; then

      echo -e "${GREEN}Completed: ${description}${NC}"
      return 0
    fi

    echo -e "${YELLOW}Preparing ${description} (${attempt}/8)...${NC}"

    if [[ "${attempt}" -lt 8 ]]; then
      sleep 10
    fi
  done

  echo -e "${RED}Error: Failed to grant ${description}.${NC}"
  cat "${log_file}" || true
  return 1
}

grant_bucket_role() {
  local service_account="$1"
  local role="$2"
  local description="$3"
  local log_file="${TEMP_DIR}/bucket-iam.log"

  for attempt in {1..8}; do
    if gcloud storage buckets add-iam-policy-binding \
      "gs://${BUCKET_NAME}" \
      --project="${PROJECT_ID}" \
      --member="serviceAccount:${service_account}" \
      --role="${role}" \
      --quiet >"${log_file}" 2>&1; then

      echo -e "${GREEN}Completed: ${description}${NC}"
      return 0
    fi

    echo -e "${YELLOW}Preparing ${description} (${attempt}/8)...${NC}"

    if [[ "${attempt}" -lt 8 ]]; then
      sleep 10
    fi
  done

  echo -e "${RED}Error: Failed to grant ${description}.${NC}"
  cat "${log_file}" || true
  return 1
}

create_eventarc_identity() {
  local log_file="${TEMP_DIR}/eventarc-identity.log"

  for attempt in {1..8}; do
    if gcloud beta services identity create \
      --service="eventarc.googleapis.com" \
      --project="${PROJECT_ID}" \
      >"${log_file}" 2>&1; then

      echo -e "${GREEN}Completed: Eventarc Service Identity${NC}"
      return 0
    fi

    # The identity may already exist even when the command returns
    # a temporary quota or propagation error.
    if gcloud projects get-iam-policy "${PROJECT_ID}" \
      --flatten="bindings[].members" \
      --filter="bindings.members:serviceAccount:${EVENTARC_SERVICE_AGENT}" \
      --format="value(bindings.members)" \
      2>/dev/null | grep -q "${EVENTARC_SERVICE_AGENT}"; then

      echo -e "${GREEN}Completed: Eventarc Service Identity already exists${NC}"
      return 0
    fi

    echo -e "${YELLOW}Creating Eventarc Service Identity (${attempt}/8)...${NC}"

    if [[ "${attempt}" -lt 8 ]]; then
      sleep 15
    fi
  done

  echo -e "${YELLOW}Warning: The Eventarc identity command did not complete cleanly.${NC}"
  echo -e "${YELLOW}The script will attempt the IAM binding directly.${NC}"
  return 0
}

# ============================================================
# Start
# ============================================================
clear
print_banner

check_command gcloud
check_command curl
check_command sed
check_command grep

# ============================================================
# Step 1: Detect project and region
# ============================================================
print_step "[1/8] Reading Google Cloud configuration..."

PROJECT_ID="$(gcloud config get-value project -q 2>/dev/null || true)"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo -e "${RED}Error: No active Google Cloud project was found.${NC}"
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
  echo -e "${RED}Error: The default region was not found in project metadata.${NC}"
  exit 1
fi

export PROJECT_ID
export PROJECT_NUMBER
export REGION

gcloud config set compute/region "${REGION}" >/dev/null

echo -e "${GREEN}Project ID     : ${PROJECT_ID}${NC}"
echo -e "${GREEN}Project number : ${PROJECT_NUMBER}${NC}"
echo -e "${GREEN}Region         : ${REGION}${NC}"

# ============================================================
# Step 2: Read lab variables
# ============================================================
print_step "[2/8] Enter the values provided by the lab..."

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

BUCKET_NAME="${BUCKET_NAME#gs://}"
BUCKET_NAME="${BUCKET_NAME%/}"

export BUCKET_NAME
export TOPIC_NAME
export FUNCTION_NAME

if [[ ! "${BUCKET_NAME}" =~ ^[a-z0-9][a-z0-9._-]+[a-z0-9]$ ]]; then
  echo -e "${RED}Error: Invalid bucket name: ${BUCKET_NAME}${NC}"
  exit 1
fi

if [[ ! "${TOPIC_NAME}" =~ ^[A-Za-z][A-Za-z0-9._~+%-]+$ ]]; then
  echo -e "${RED}Error: Invalid Pub/Sub topic name: ${TOPIC_NAME}${NC}"
  exit 1
fi

if [[ ! "${FUNCTION_NAME}" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo -e "${RED}Error: Invalid function name: ${FUNCTION_NAME}${NC}"
  echo -e "${YELLOW}Use lowercase letters, numbers, and hyphens only.${NC}"
  exit 1
fi

echo
echo -e "${WHITE}Configuration summary${NC}"
echo -e "${CYAN}------------------------------------------------------------${NC}"
echo -e "Project     : ${WHITE}${PROJECT_ID}${NC}"
echo -e "Region      : ${GREEN}${REGION}${NC}"
echo -e "Bucket      : ${CYAN}${BUCKET_NAME}${NC}"
echo -e "Topic       : ${MAGENTA}${TOPIC_NAME}${NC}"
echo -e "Function    : ${YELLOW}${FUNCTION_NAME}${NC}"
echo -e "Entry point : ${GREEN}thumbnail${NC}"
echo -e "${CYAN}------------------------------------------------------------${NC}"

# ============================================================
# Step 3: Enable required APIs
# ============================================================
print_step "[3/8] Enabling required APIs..."

API_LOG="${TEMP_DIR}/enable-apis.log"
APIS_ENABLED=false

for attempt in {1..6}; do
  if gcloud services enable \
    artifactregistry.googleapis.com \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    compute.googleapis.com \
    eventarc.googleapis.com \
    run.googleapis.com \
    logging.googleapis.com \
    pubsub.googleapis.com \
    storage.googleapis.com \
    --project="${PROJECT_ID}" \
    >"${API_LOG}" 2>&1; then

    APIS_ENABLED=true
    break
  fi

  echo -e "${YELLOW}API enable attempt ${attempt}/6 failed.${NC}"

  if [[ "${attempt}" -lt 6 ]]; then
    sleep 15
  fi
done

if [[ "${APIS_ENABLED}" != true ]]; then
  echo -e "${RED}Error: Failed to enable the required APIs.${NC}"
  cat "${API_LOG}"
  exit 1
fi

echo -e "${GREEN}Required APIs enabled successfully.${NC}"

# ============================================================
# Step 4: Create the bucket and Pub/Sub topic
# ============================================================
print_step "[4/8] Creating the Cloud Storage bucket and Pub/Sub topic..."

if gcloud storage buckets describe \
  "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  >/dev/null 2>&1; then

  echo -e "${YELLOW}Bucket already exists: gs://${BUCKET_NAME}${NC}"
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access

  echo -e "${GREEN}Bucket created: gs://${BUCKET_NAME}${NC}"
fi

if gcloud pubsub topics describe "${TOPIC_NAME}" \
  --project="${PROJECT_ID}" \
  >/dev/null 2>&1; then

  echo -e "${YELLOW}Pub/Sub topic already exists: ${TOPIC_NAME}${NC}"
else
  gcloud pubsub topics create "${TOPIC_NAME}" \
    --project="${PROJECT_ID}"

  echo -e "${GREEN}Pub/Sub topic created: ${TOPIC_NAME}${NC}"
fi

# ============================================================
# Step 5: Prepare service agents and IAM permissions
# ============================================================
print_step "[5/8] Preparing service agents and IAM permissions..."

EVENTARC_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com"
RUNTIME_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Retrieve the official Cloud Storage Service Agent address.
STORAGE_SERVICE_AGENT="$(
  gcloud storage service-agent \
    --project="${PROJECT_ID}"
)"

echo -e "${WHITE}Eventarc Service Agent : ${EVENTARC_SERVICE_AGENT}${NC}"
echo -e "${WHITE}Storage Service Agent  : ${STORAGE_SERVICE_AGENT}${NC}"
echo -e "${WHITE}Runtime Service Account: ${RUNTIME_SERVICE_ACCOUNT}${NC}"

create_eventarc_identity

# Do not check the managed Service Agent using:
# gcloud iam service-accounts describe
#
# Assign the role directly and retry until IAM propagation completes.
grant_project_role \
  "${EVENTARC_SERVICE_AGENT}" \
  "roles/eventarc.serviceAgent" \
  "Eventarc Service Agent role"

grant_project_role \
  "${STORAGE_SERVICE_AGENT}" \
  "roles/pubsub.publisher" \
  "Cloud Storage Pub/Sub Publisher role"

grant_project_role \
  "${RUNTIME_SERVICE_ACCOUNT}" \
  "roles/eventarc.eventReceiver" \
  "Eventarc Event Receiver role"

grant_project_role \
  "${RUNTIME_SERVICE_ACCOUNT}" \
  "roles/run.invoker" \
  "Cloud Run Invoker role"

grant_bucket_role \
  "${RUNTIME_SERVICE_ACCOUNT}" \
  "roles/storage.objectAdmin" \
  "Cloud Storage Object Admin role for the function"

grant_topic_role \
  "${RUNTIME_SERVICE_ACCOUNT}" \
  "roles/pubsub.publisher" \
  "Pub/Sub Publisher role for the function"

# ============================================================
# Step 6: Prepare the function source
# ============================================================
print_step "[6/8] Preparing the Cloud Function source code..."

WORK_DIR="${HOME}/quicklab"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

cat > index.js <<'EOF_END'
/* globals exports, require */
/**
 * Thumbnail Generator Function
 * Copyright (c) 2026 ePlus.DEV
 */

'use strict';

const { Storage } = require('@google-cloud/storage');
const { PubSub } = require('@google-cloud/pubsub');
const sharp = require('sharp');

const storage = new Storage();
const pubsub = new PubSub();

exports.thumbnail = async cloudEvent => {
  // Support both CloudEvent and legacy event formats.
  const event = cloudEvent.data || cloudEvent;

  const fileName = event.name;
  const bucketName = event.bucket;
  const size = '64x64';
  const topicName = '__TOPIC_NAME__';

  if (!fileName || !bucketName) {
    console.error('Missing event.name or event.bucket.');
    return;
  }

  if (fileName.includes('64x64_thumbnail')) {
    console.log(
      `gs://${bucketName}/${fileName} already has a thumbnail.`
    );
    return;
  }

  const fileNameParts = fileName.split('.');
  const fileExtension =
    fileNameParts[fileNameParts.length - 1].toLowerCase();

  if (
    fileExtension !== 'png' &&
    fileExtension !== 'jpg' &&
    fileExtension !== 'jpeg'
  ) {
    console.log(
      `gs://${bucketName}/${fileName} is not a supported image type.`
    );
    return;
  }

  const fileNameWithoutExtension = fileName.substring(
    0,
    fileName.length - fileExtension.length
  );

  // This keeps the file naming format used by the lab instructions.
  const newFileName =
    `${fileNameWithoutExtension}${size}_thumbnail.${fileExtension}`;

  const outputFormat =
    fileExtension === 'jpg' ? 'jpeg' : fileExtension;

  const contentType =
    outputFormat === 'jpeg'
      ? 'image/jpeg'
      : `image/${outputFormat}`;

  const bucket = storage.bucket(bucketName);
  const sourceFile = bucket.file(fileName);
  const destinationFile = bucket.file(newFileName);

  try {
    console.log(
      `Processing original image: gs://${bucketName}/${fileName}`
    );

    const [sourceBuffer] = await sourceFile.download();

    const thumbnailBuffer = await sharp(sourceBuffer)
      .resize(64, 64, {
        fit: 'inside',
        withoutEnlargement: true,
      })
      .toFormat(outputFormat)
      .toBuffer();

    await destinationFile.save(thumbnailBuffer, {
      metadata: {
        contentType,
      },
    });

    console.log(
      `Success: ${fileName} -> ${newFileName}`
    );

    const messageId = await pubsub
      .topic(topicName)
      .publishMessage({
        data: Buffer.from(newFileName),
      });

    console.log(
      `Message ${messageId} published to ${topicName}.`
    );
  } catch (error) {
    console.error('Thumbnail processing failed:', error);
    throw error;
  }
};
EOF_END

sed -i \
  "s|__TOPIC_NAME__|${TOPIC_NAME}|g" \
  index.js

cat > package.json <<'EOF_END'
{
  "name": "thumbnails",
  "version": "1.0.0",
  "description": "Create a thumbnail of an uploaded image",
  "author": "ePlus.DEV",
  "license": "UNLICENSED",
  "main": "index.js",
  "scripts": {
    "start": "functions-framework --target=thumbnail"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.4.5",
    "@google-cloud/pubsub": "^4.11.0",
    "@google-cloud/storage": "^7.16.0",
    "sharp": "^0.33.5"
  },
  "engines": {
    "node": "20"
  }
}
EOF_END

echo -e "${GREEN}Function source created in ${WORK_DIR}.${NC}"
echo -e "${GREEN}Topic ID inserted into index.js: ${TOPIC_NAME}${NC}"
echo -e "${GREEN}Function entry point configured as: thumbnail${NC}"

# ============================================================
# Step 7: Deploy the Cloud Function
# ============================================================
print_step "[7/8] Deploying the Cloud Functions Gen2 function..."

DEPLOY_LOG="${TEMP_DIR}/deploy.log"
DEPLOY_SUCCESS=false
MAX_DEPLOY_ATTEMPTS=10

for ((attempt = 1; attempt <= MAX_DEPLOY_ATTEMPTS; attempt++)); do
  echo -e "${YELLOW}Deployment attempt ${attempt}/${MAX_DEPLOY_ATTEMPTS}...${NC}"

  if gcloud functions deploy "${FUNCTION_NAME}" \
    --project="${PROJECT_ID}" \
    --gen2 \
    --runtime="nodejs20" \
    --entry-point="thumbnail" \
    --source="." \
    --region="${REGION}" \
    --service-account="${RUNTIME_SERVICE_ACCOUNT}" \
    --trigger-bucket="${BUCKET_NAME}" \
    --max-instances=5 \
    --quiet 2>&1 | tee "${DEPLOY_LOG}"; then

    DEPLOY_SUCCESS=true
    break
  fi

  if [[ "${attempt}" -lt "${MAX_DEPLOY_ATTEMPTS}" ]]; then
    echo
    echo -e "${YELLOW}Eventarc or IAM permissions may still be propagating.${NC}"
    echo -e "${YELLOW}The deployment will be retried automatically.${NC}"
    sleep 30
  fi
done

if [[ "${DEPLOY_SUCCESS}" != true ]]; then
  echo
  echo -e "${RED}Error: The Cloud Function deployment failed.${NC}"
  echo -e "${YELLOW}Last deployment output:${NC}"
  cat "${DEPLOY_LOG}" || true
  exit 1
fi

echo -e "${GREEN}Cloud Function deployed successfully.${NC}"

# ============================================================
# Step 8: Upload and verify the test image
# ============================================================
print_step "[8/8] Uploading and verifying the wildlife test image..."

TEST_IMAGE="wildlife.jpg"

curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --output "${TEST_IMAGE}" \
  "https://storage.googleapis.com/cloud-training/arc102/wildlife.jpg"

gcloud storage cp \
  "${TEST_IMAGE}" \
  "gs://${BUCKET_NAME}/${TEST_IMAGE}" \
  --project="${PROJECT_ID}" \
  --quiet

echo -e "${GREEN}Test image uploaded successfully.${NC}"
echo -e "${YELLOW}Checking for a generated thumbnail...${NC}"

THUMBNAIL_CREATED=false
THUMBNAIL_PATH=""

for attempt in {1..18}; do
  THUMBNAIL_PATH="$(
    gcloud storage ls \
      "gs://${BUCKET_NAME}/" \
      --project="${PROJECT_ID}" \
      2>/dev/null |
      grep '64x64_thumbnail' |
      head -n 1 || true
  )"

  if [[ -n "${THUMBNAIL_PATH}" ]]; then
    THUMBNAIL_CREATED=true
    break
  fi

  echo -e "${YELLOW}Thumbnail check ${attempt}/18...${NC}"
  sleep 10
done

echo
echo -e "${BLUE}Bucket contents:${NC}"

gcloud storage ls \
  "gs://${BUCKET_NAME}/" \
  --project="${PROJECT_ID}" || true

echo
echo -e "${CYAN}============================================================${NC}"

if [[ "${THUMBNAIL_CREATED}" == true ]]; then
  echo -e "${GREEN}   Congratulations! The lab script completed successfully.${NC}"
  echo -e "${GREEN}   Thumbnail created: ${THUMBNAIL_PATH}${NC}"
else
  echo -e "${YELLOW}   The function was deployed successfully.${NC}"
  echo -e "${YELLOW}   The thumbnail was not detected yet.${NC}"
  echo -e "${YELLOW}   Review the function logs if the lab checker does not pass.${NC}"
fi

echo -e "${WHITE}   Project     : ${PROJECT_ID}${NC}"
echo -e "${GREEN}   Region      : ${REGION}${NC}"
echo -e "${CYAN}   Bucket      : gs://${BUCKET_NAME}${NC}"
echo -e "${MAGENTA}   Topic       : ${TOPIC_NAME}${NC}"
echo -e "${YELLOW}   Function    : ${FUNCTION_NAME}${NC}"
echo -e "${GREEN}   Entry point : thumbnail${NC}"
echo -e "${WHITE}   Copyright (c) 2026 ePlus.DEV${NC}"
echo -e "${CYAN}============================================================${NC}"