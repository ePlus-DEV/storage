#!/usr/bin/env bash

# Run the entire script in a subshell.
# An error will stop only the script, not the current Cloud Shell session.
(
  set -Eeuo pipefail

  # ==========================================================
  # ANSI color codes
  # ==========================================================
  RED='\033[1;31m'
  GREEN='\033[1;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[1;34m'
  MAGENTA='\033[1;35m'
  CYAN='\033[1;36m'
  WHITE='\033[1;37m'
  NC='\033[0m'

  TEMP_DIR="$(mktemp -d)"

  cleanup() {
    rm -rf "${TEMP_DIR}"
  }

  trap cleanup EXIT

  # ==========================================================
  # Helper functions
  # ==========================================================
  print_banner() {
    clear
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${YELLOW}       Wildlife Thumbnail Challenge Lab - ePlus.DEV${NC}"
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

  # ==========================================================
  # Start
  # ==========================================================
  print_banner

  check_command gcloud
  check_command curl
  check_command sed
  check_command grep

  # ==========================================================
  # Step 1: Detect the Google Cloud project and region
  # ==========================================================
  print_step "[1/7] Reading Google Cloud configuration..."

  PROJECT_ID="$(
    gcloud config get-value project \
      --quiet \
      2>/dev/null || true
  )"

  if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
    echo -e "${RED}Error: No active Google Cloud project was found.${NC}"
    exit 1
  fi

  PROJECT_NUMBER="$(
    gcloud projects describe "${PROJECT_ID}" \
      --format="value(projectNumber)"
  )"

  DETECTED_REGION="$(
    gcloud compute project-info describe \
      --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
      2>/dev/null || true
  )"

  # The challenge lab requires resources in us-east1.
  REGION="${DETECTED_REGION:-us-east1}"

  if [[ "${REGION}" != "us-east1" ]]; then
    echo -e "${YELLOW}The detected region is ${REGION}.${NC}"
    echo -e "${YELLOW}The challenge requires us-east1, so us-east1 will be used.${NC}"
    REGION="us-east1"
  fi

  export PROJECT_ID
  export PROJECT_NUMBER
  export REGION

  gcloud config set compute/region "${REGION}" \
    --quiet >/dev/null

  echo -e "${GREEN}Project ID     : ${PROJECT_ID}${NC}"
  echo -e "${GREEN}Project number : ${PROJECT_NUMBER}${NC}"
  echo -e "${GREEN}Region         : ${REGION}${NC}"

  # ==========================================================
  # Step 2: Read the values provided by the lab
  # ==========================================================
  print_step "[2/7] Enter the values provided by the lab..."

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

  # Remove gs:// and trailing slash if entered accidentally.
  BUCKET_NAME="${BUCKET_NAME#gs://}"
  BUCKET_NAME="${BUCKET_NAME%/}"

  export BUCKET_NAME
  export TOPIC_NAME
  export FUNCTION_NAME

  # ==========================================================
  # Validate input values
  # ==========================================================
  if [[ ! "${BUCKET_NAME}" =~ ^[a-z0-9][a-z0-9._-]+[a-z0-9]$ ]]; then
    echo -e "${RED}Error: Invalid bucket name: ${BUCKET_NAME}${NC}"
    exit 1
  fi

  if [[ ! "${TOPIC_NAME}" =~ ^[A-Za-z][A-Za-z0-9._~+%-]+$ ]]; then
    echo -e "${RED}Error: Invalid Pub/Sub topic name: ${TOPIC_NAME}${NC}"
    exit 1
  fi

  if [[ ! "${FUNCTION_NAME}" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo -e "${RED}Error: Invalid Cloud Function name: ${FUNCTION_NAME}${NC}"
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
  echo -e "Generation  : ${GREEN}1st gen${NC}"
  echo -e "Entry point : ${GREEN}thumbnail${NC}"
  echo -e "Trigger     : ${GREEN}Cloud Storage${NC}"
  echo -e "${CYAN}------------------------------------------------------------${NC}"

  # ==========================================================
  # Step 3: Enable the required APIs
  # ==========================================================
  print_step "[3/7] Enabling required APIs..."

  API_LOG="${TEMP_DIR}/enable-apis.log"
  APIS_ENABLED=false

  for attempt in {1..5}; do
    if gcloud services enable \
      cloudfunctions.googleapis.com \
      cloudbuild.googleapis.com \
      artifactregistry.googleapis.com \
      logging.googleapis.com \
      pubsub.googleapis.com \
      storage.googleapis.com \
      --project="${PROJECT_ID}" \
      >"${API_LOG}" 2>&1; then

      APIS_ENABLED=true
      break
    fi

    echo -e "${YELLOW}API enable attempt ${attempt}/5 failed.${NC}"

    if [[ "${attempt}" -lt 5 ]]; then
      sleep 10
    fi
  done

  if [[ "${APIS_ENABLED}" != true ]]; then
    echo -e "${RED}Error: Failed to enable the required APIs.${NC}"
    cat "${API_LOG}"
    exit 1
  fi

  echo -e "${GREEN}Required APIs enabled successfully.${NC}"

  # ==========================================================
  # Step 4: Create the bucket and Pub/Sub topic
  # ==========================================================
  print_step "[4/7] Creating the Cloud Storage bucket and Pub/Sub topic..."

  if gcloud storage buckets describe \
    "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    >/dev/null 2>&1; then

    echo -e "${YELLOW}Bucket already exists: gs://${BUCKET_NAME}${NC}"
  else
    gcloud storage buckets create \
      "gs://${BUCKET_NAME}" \
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

  # ==========================================================
  # Step 5: Prepare the Cloud Function source code
  # ==========================================================
  print_step "[5/7] Preparing the Cloud Function source code..."

  WORK_DIR="${HOME}/quicklab"

  rm -rf "${WORK_DIR}"
  mkdir -p "${WORK_DIR}"
  cd "${WORK_DIR}"

  cat > index.js <<'EOF_END'
/* globals exports, require */
// jshint strict: false
// jshint esversion: 6

"use strict";

const { Storage } = require("@google-cloud/storage");
const { PubSub } = require("@google-cloud/pubsub");
const imagemagick = require("imagemagick-stream");

const gcs = new Storage();
const pubsub = new PubSub();

exports.thumbnail = (event, context) => {
  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64";
  const bucket = gcs.bucket(bucketName);
  const topicName = "__TOPIC_NAME__";

  if (!fileName || !bucketName) {
    console.log("Missing event.name or event.bucket");
    return Promise.resolve();
  }

  if (fileName.search("64x64_thumbnail") !== -1) {
    console.log(
      `gs://${bucketName}/${fileName} already has a thumbnail`
    );

    return Promise.resolve();
  }

  const filenameSplit = fileName.split(".");
  const filenameExt =
    filenameSplit[filenameSplit.length - 1].toLowerCase();

  const filenameWithoutExt = fileName.substring(
    0,
    fileName.length - filenameExt.length
  );

  if (filenameExt !== "png" && filenameExt !== "jpg") {
    console.log(
      `gs://${bucketName}/${fileName} is not an image I can handle`
    );

    return Promise.resolve();
  }

  console.log(
    `Processing Original: gs://${bucketName}/${fileName}`
  );

  const gcsObject = bucket.file(fileName);

  // Keep the exact filename format used by the lab sample:
  // wildlife.jpg -> wildlife.64x64_thumbnail.jpg
  const newFilename =
    filenameWithoutExt + size + "_thumbnail." + filenameExt;

  const gcsNewObject = bucket.file(newFilename);
  const sourceStream = gcsObject.createReadStream();

  const destinationStream = gcsNewObject.createWriteStream({
    metadata: {
      contentType: `image/${filenameExt}`,
    },
  });

  const resize = imagemagick()
    .resize(size)
    .quality(90);

  return new Promise((resolve, reject) => {
    sourceStream
      .on("error", reject)
      .pipe(resize)
      .on("error", reject)
      .pipe(destinationStream)
      .on("error", reject)
      .on("finish", async () => {
        console.log(
          `Success: ${fileName} -> ${newFilename}`
        );

        try {
          const messageId = await pubsub
            .topic(topicName)
            .publishMessage({
              data: Buffer.from(newFilename),
            });

          console.log(
            `Message ${messageId} published to ${topicName}.`
          );

          resolve();
        } catch (error) {
          console.error(
            "Failed to publish the Pub/Sub message:",
            error
          );

          reject(error);
        }
      });
  });
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
    "start": "node index.js"
  },
  "dependencies": {
    "@google-cloud/pubsub": "^4.11.0",
    "@google-cloud/storage": "^7.16.0",
    "imagemagick-stream": "4.1.1"
  },
  "engines": {
    "node": "22"
  }
}
EOF_END

  echo -e "${GREEN}Function source created in ${WORK_DIR}.${NC}"
  echo -e "${GREEN}Topic inserted into index.js: ${TOPIC_NAME}${NC}"
  echo -e "${GREEN}Entry point configured as: thumbnail${NC}"

  echo
  echo -e "${WHITE}Topic verification:${NC}"

  grep \
    'const topicName' \
    index.js

  # ==========================================================
  # Step 6: Deploy Cloud Functions 1st gen
  # ==========================================================
  print_step "[6/7] Deploying the Cloud Functions 1st gen function..."

  DEPLOY_LOG="${TEMP_DIR}/deploy.log"
  DEPLOY_SUCCESS=false
  MAX_DEPLOY_ATTEMPTS=3

  for ((attempt = 1; attempt <= MAX_DEPLOY_ATTEMPTS; attempt++)); do
    echo -e "${YELLOW}Deployment attempt ${attempt}/${MAX_DEPLOY_ATTEMPTS}...${NC}"

    if gcloud functions deploy "${FUNCTION_NAME}" \
      --project="${PROJECT_ID}" \
      --no-gen2 \
      --runtime="nodejs22" \
      --entry-point="thumbnail" \
      --source="." \
      --region="${REGION}" \
      --trigger-bucket="${BUCKET_NAME}" \
      --max-instances=5 \
      --quiet 2>&1 | tee "${DEPLOY_LOG}"; then

      DEPLOY_SUCCESS=true
      break
    fi

    if [[ "${attempt}" -lt "${MAX_DEPLOY_ATTEMPTS}" ]]; then
      echo
      echo -e "${YELLOW}The deployment failed and will be retried.${NC}"
      sleep 20
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

  # ==========================================================
  # Verify the deployed function configuration
  # ==========================================================
  echo
  echo -e "${WHITE}Deployed function configuration:${NC}"

  gcloud functions describe "${FUNCTION_NAME}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --format="yaml(
      name,
      status,
      entryPoint,
      runtime,
      eventTrigger.eventType,
      eventTrigger.resource
    )"

  # ==========================================================
  # Step 7: Upload and verify the wildlife test image
  # ==========================================================
  print_step "[7/7] Uploading and verifying the wildlife test image..."

  TEST_IMAGE="wildlife.jpg"
  THUMBNAIL_NAME="wildlife.64x64_thumbnail.jpg"

  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --output "${TEST_IMAGE}" \
    "https://storage.googleapis.com/cloud-training/arc102/wildlife.jpg"

  # Remove previous test files so a new event is generated.
  gcloud storage rm \
    "gs://${BUCKET_NAME}/${TEST_IMAGE}" \
    "gs://${BUCKET_NAME}/${THUMBNAIL_NAME}" \
    --project="${PROJECT_ID}" \
    --quiet \
    >/dev/null 2>&1 || true

  gcloud storage cp \
    "${TEST_IMAGE}" \
    "gs://${BUCKET_NAME}/${TEST_IMAGE}" \
    --project="${PROJECT_ID}" \
    --quiet

  echo -e "${GREEN}Test image uploaded successfully.${NC}"
  echo -e "${YELLOW}Checking for the generated thumbnail...${NC}"

  THUMBNAIL_CREATED=false

  for attempt in {1..18}; do
    if gcloud storage ls \
      "gs://${BUCKET_NAME}/${THUMBNAIL_NAME}" \
      --project="${PROJECT_ID}" \
      >/dev/null 2>&1; then

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
    echo -e "${GREEN}Congratulations! The lab script completed successfully.${NC}"
    echo -e "${GREEN}Thumbnail created: gs://${BUCKET_NAME}/${THUMBNAIL_NAME}${NC}"
  else
    echo -e "${RED}The thumbnail was not detected.${NC}"
    echo -e "${YELLOW}Recent Cloud Function logs:${NC}"
    echo

    gcloud functions logs read "${FUNCTION_NAME}" \
      --project="${PROJECT_ID}" \
      --region="${REGION}" \
      --limit=30 || true
  fi

  echo -e "${WHITE}Project     : ${PROJECT_ID}${NC}"
  echo -e "${GREEN}Region      : ${REGION}${NC}"
  echo -e "${CYAN}Bucket      : gs://${BUCKET_NAME}${NC}"
  echo -e "${MAGENTA}Topic       : ${TOPIC_NAME}${NC}"
  echo -e "${YELLOW}Function    : ${FUNCTION_NAME}${NC}"
  echo -e "${GREEN}Generation  : 1st gen${NC}"
  echo -e "${GREEN}Entry point : thumbnail${NC}"
  echo -e "${WHITE}Copyright (c) 2026 ePlus.DEV${NC}"
  echo -e "${CYAN}============================================================${NC}"
)

SCRIPT_STATUS=$?

if [[ "${SCRIPT_STATUS}" -ne 0 ]]; then
  echo
  echo -e "\033[1;31m============================================================\033[0m"
  echo -e "\033[1;31mThe script stopped because an error occurred.\033[0m"
  echo -e "\033[1;33mThe Cloud Shell terminal remains active.\033[0m"
  echo -e "\033[1;31m============================================================\033[0m"
fi