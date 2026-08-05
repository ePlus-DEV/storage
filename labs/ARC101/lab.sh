#!/bin/bash

# ============================================================
# Color variables
# ============================================================

BLACK=$(tput setaf 0 2>/dev/null)
RED=$(tput setaf 1 2>/dev/null)
GREEN=$(tput setaf 2 2>/dev/null)
YELLOW=$(tput setaf 3 2>/dev/null)
BLUE=$(tput setaf 4 2>/dev/null)
MAGENTA=$(tput setaf 5 2>/dev/null)
CYAN=$(tput setaf 6 2>/dev/null)
WHITE=$(tput setaf 7 2>/dev/null)

BG_BLACK=$(tput setab 0 2>/dev/null)
BG_RED=$(tput setab 1 2>/dev/null)
BG_GREEN=$(tput setab 2 2>/dev/null)
BG_YELLOW=$(tput setab 3 2>/dev/null)
BG_BLUE=$(tput setab 4 2>/dev/null)
BG_MAGENTA=$(tput setab 5 2>/dev/null)
BG_CYAN=$(tput setab 6 2>/dev/null)
BG_WHITE=$(tput setab 7 2>/dev/null)

BOLD=$(tput bold 2>/dev/null)
RESET=$(tput sgr0 2>/dev/null)

# ============================================================
# Helper functions
# ============================================================

print_step() {
  echo
  echo "${CYAN}${BOLD}============================================================${RESET}"
  echo "${CYAN}${BOLD}$1${RESET}"
  echo "${CYAN}${BOLD}============================================================${RESET}"
}

print_success() {
  echo "${GREEN}${BOLD}✓ $1${RESET}"
}

print_warning() {
  echo "${YELLOW}${BOLD}⚠ $1${RESET}"
}

print_error() {
  echo "${RED}${BOLD}✗ $1${RESET}"
}

prompt_required() {
  local VARIABLE_NAME="$1"
  local LABEL="$2"
  local VALUE=""

  while [[ -z "$VALUE" ]]; do
    printf "${YELLOW}${BOLD}Enter ${LABEL}:${RESET} ${CYAN}"

    IFS= read -r VALUE </dev/tty

    printf "${RESET}"

    VALUE=$(printf '%s' "$VALUE" |
      sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ -z "$VALUE" ]]; then
      echo "${RED}${BOLD}${LABEL} cannot be empty.${RESET}"
    fi
  done

  printf -v "$VARIABLE_NAME" '%s' "$VALUE"
  export "$VARIABLE_NAME"
}

# ============================================================
# Start
# ============================================================

clear

echo "${BG_MAGENTA}${WHITE}${BOLD}"
echo "============================================================"
echo " Travel Thumbnail Challenge Lab"
echo " © ePlus.DEV"
echo "============================================================"
echo "${RESET}"

# Force input every time the script runs
unset BUCKET_NAME
unset TOPIC_NAME
unset FUNCTION_NAME
unset BUCKET_USER

echo
echo "${CYAN}${BOLD}Please enter the values from the lab instructions.${RESET}"
echo

prompt_required "BUCKET_NAME" "BUCKET_NAME"
prompt_required "TOPIC_NAME" "TOPIC_NAME"
prompt_required "FUNCTION_NAME" "FUNCTION_NAME"
prompt_required "BUCKET_USER" "BUCKET_USER"

echo
echo "${GREEN}${BOLD}✓ Input completed${RESET}"
echo
echo "${WHITE}${BOLD}BUCKET_NAME   :${RESET} ${CYAN}${BUCKET_NAME}${RESET}"
echo "${WHITE}${BOLD}TOPIC_NAME    :${RESET} ${CYAN}${TOPIC_NAME}${RESET}"
echo "${WHITE}${BOLD}FUNCTION_NAME :${RESET} ${CYAN}${FUNCTION_NAME}${RESET}"
echo "${WHITE}${BOLD}BUCKET_USER   :${RESET} ${CYAN}${BUCKET_USER}${RESET}"
echo

# ============================================================
# Project configuration
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
  --format="value(projectNumber)" \
  2>/dev/null)

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe--format="value(commonInstanceMetadata.items[google-compute-default-region])")

RUNTIME_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

STORAGE_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"

ALERT_EMAIL=$(gcloud config get-value account 2>/dev/null)

WORK_DIR="$HOME/travel-thumbnail-function"

echo "${BLUE}${BOLD}Project configuration:${RESET}"
echo "${WHITE}PROJECT_ID    :${RESET} ${CYAN}${PROJECT_ID}${RESET}"
echo "${WHITE}PROJECT_NUMBER:${RESET} ${CYAN}${PROJECT_NUMBER}${RESET}"
echo "${WHITE}REGION        :${RESET} ${CYAN}${REGION}${RESET}"
echo "${WHITE}ZONE          :${RESET} ${CYAN}${ZONE}${RESET}"
echo "${WHITE}ALERT_EMAIL   :${RESET} ${CYAN}${ALERT_EMAIL}${RESET}"

# ============================================================
# Enable APIs
# ============================================================

print_step "[1/8] Enabling required APIs"

gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudfunctions.googleapis.com \
  eventarc.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  pubsub.googleapis.com \
  run.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

if [[ $? -eq 0 ]]; then
  print_success "Required APIs enabled"
else
  print_warning "Some APIs may still be enabling"
fi

gcloud config set compute/region "$REGION" \
  --quiet >/dev/null 2>&1

gcloud config set compute/zone "$ZONE" \
  --quiet >/dev/null 2>&1

# ============================================================
# Task 1 - Create bucket
# ============================================================

print_step "[2/8] Creating Cloud Storage bucket"

if gcloud storage buckets describe \
  "gs://$BUCKET_NAME" \
  --project="$PROJECT_ID" \
  >/dev/null 2>&1; then

  print_warning "Bucket already exists: gs://$BUCKET_NAME"

else

  gcloud storage buckets create \
    "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --quiet

  if [[ $? -eq 0 ]]; then
    print_success "Bucket created: gs://$BUCKET_NAME"
  else
    print_error "Unable to create the bucket"
  fi

fi

echo
echo "${CYAN}${BOLD}Granting Storage Object Viewer to:${RESET}"
echo "${YELLOW}${BUCKET_USER}${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:$BUCKET_USER" \
  --role="roles/storage.objectViewer" \
  --condition=None \
  --quiet >/dev/null

if [[ $? -eq 0 ]]; then
  print_success "Storage Object Viewer role granted"
else
  print_warning "Unable to grant project IAM role"
fi

# ============================================================
# Task 2 - Create Pub/Sub topic
# ============================================================

print_step "[3/8] Creating Pub/Sub topic"

if gcloud pubsub topics describe \
  "$TOPIC_NAME" \
  --project="$PROJECT_ID" \
  >/dev/null 2>&1; then

  print_warning "Topic already exists: $TOPIC_NAME"

else

  gcloud pubsub topics create \
    "$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --quiet

  if [[ $? -eq 0 ]]; then
    print_success "Pub/Sub topic created: $TOPIC_NAME"
  else
    print_error "Unable to create Pub/Sub topic"
  fi

fi

# ============================================================
# Prepare IAM permissions
# ============================================================

print_step "[4/8] Preparing Cloud Function IAM permissions"

echo "${YELLOW}Runtime service account:${RESET}"
echo "${CYAN}${RUNTIME_SERVICE_ACCOUNT}${RESET}"
echo

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/eventarc.eventReceiver" \
  --condition=None \
  --quiet >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/run.invoker" \
  --condition=None \
  --quiet >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/storage.objectAdmin" \
  --condition=None \
  --quiet >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/pubsub.publisher" \
  --condition=None \
  --quiet >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/logging.logWriter" \
  --condition=None \
  --quiet >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$STORAGE_SERVICE_ACCOUNT" \
  --role="roles/pubsub.publisher" \
  --condition=None \
  --quiet >/dev/null

print_success "IAM permissions configured"

echo "${YELLOW}Waiting for IAM propagation...${RESET}"
sleep 15

# ============================================================
# Create function source
# ============================================================

print_step "[5/8] Creating Cloud Run Function source"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

cat > index.js <<EOF_INDEX
/* globals exports, require */
// jshint strict: false
// jshint esversion: 6
"use strict";

const {Storage} = require("@google-cloud/storage");
const {PubSub} = require("@google-cloud/pubsub");
const sharp = require("sharp");

const storage = new Storage();
const pubsub = new PubSub();

exports.thumbnail = async (cloudEvent) => {
  const event = cloudEvent.data || cloudEvent;

  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64";
  const topicName = "${TOPIC_NAME}";

  if (!fileName || !bucketName) {
    console.log("Bucket name or file name was not found.");
    return;
  }

  if (fileName.includes("64x64_thumbnail")) {
    console.log(
      \`gs://\${bucketName}/\${fileName} already has a thumbnail\`
    );

    return;
  }

  const fileNameParts = fileName.split(".");
  const extension = fileNameParts.pop().toLowerCase();

  if (
    extension !== "png" &&
    extension !== "jpg" &&
    extension !== "jpeg"
  ) {
    console.log(
      \`gs://\${bucketName}/\${fileName} is not an image I can handle\`
    );

    return;
  }

  const fileNameWithoutExtension = fileName.substring(
    0,
    fileName.length - extension.length
  );

  const outputExtension =
    extension === "jpeg" ? "jpg" : extension;

  const newFileName =
    fileNameWithoutExtension +
    size +
    "_thumbnail." +
    outputExtension;

  console.log(
    \`Processing Original: gs://\${bucketName}/\${fileName}\`
  );

  const bucket = storage.bucket(bucketName);
  const sourceFile = bucket.file(fileName);
  const thumbnailFile = bucket.file(newFileName);

  const [sourceBuffer] = await sourceFile.download();

  let image = sharp(sourceBuffer).resize(
    64,
    64,
    {
      fit: "inside",
      withoutEnlargement: true
    }
  );

  let contentType;

  if (outputExtension === "png") {
    image = image.png({
      quality: 90
    });

    contentType = "image/png";
  } else {
    image = image.jpeg({
      quality: 90
    });

    contentType = "image/jpeg";
  }

  const thumbnailBuffer = await image.toBuffer();

  await thumbnailFile.save(
    thumbnailBuffer,
    {
      resumable: false,
      metadata: {
        contentType: contentType
      }
    }
  );

  const messageId = await pubsub
    .topic(topicName)
    .publishMessage({
      data: Buffer.from(newFileName)
    });

  console.log(
    \`Success: \${fileName} → \${newFileName}\`
  );

  console.log(
    \`Message \${messageId} published.\`
  );
};
EOF_INDEX

cat > package.json <<'EOF_PACKAGE'
{
  "name": "travel-thumbnail-generator",
  "version": "1.0.0",
  "description": "Create a thumbnail when an image is uploaded",
  "main": "index.js",
  "scripts": {
    "start": "functions-framework --target=thumbnail"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.4.5",
    "@google-cloud/pubsub": "^4.10.0",
    "@google-cloud/storage": "^7.16.0",
    "sharp": "^0.33.5"
  },
  "engines": {
    "node": "22"
  }
}
EOF_PACKAGE

print_success "Function source files created"

# ============================================================
# Deploy Cloud Run Function Gen2
# ============================================================

print_step "[6/8] Deploying Cloud Run Function Gen2"

deploy_function() {
  gcloud functions deploy "$FUNCTION_NAME" \
    --gen2 \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --runtime="nodejs22" \
    --source="$WORK_DIR" \
    --entry-point="thumbnail" \
    --service-account="$RUNTIME_SERVICE_ACCOUNT" \
    --trigger-service-account="$RUNTIME_SERVICE_ACCOUNT" \
    --trigger-bucket="$BUCKET_NAME" \
    --trigger-location="$REGION" \
    --memory="256Mi" \
    --max-instances="2" \
    --timeout="120s" \
    --quiet
}

deploy_function
DEPLOY_STATUS=$?

if [[ $DEPLOY_STATUS -ne 0 ]]; then
  echo
  print_warning "First deployment failed"
  echo "${YELLOW}Waiting 20 seconds before retrying once...${RESET}"

  sleep 20

  deploy_function
  DEPLOY_STATUS=$?
fi

if [[ $DEPLOY_STATUS -eq 0 ]]; then
  print_success "Cloud Run Function deployed successfully"
else
  print_error "Function deployment failed"
  print_warning "The script will continue without closing the terminal"
fi

# ============================================================
# Upload test image
# ============================================================

print_step "[7/8] Uploading test image"

cd "$WORK_DIR"

wget -q \
  "https://storage.googleapis.com/cloud-training/arc101/travel.jpg" \
  -O travel.jpg

if [[ -f travel.jpg && -s travel.jpg ]]; then

  print_success "travel.jpg downloaded"

  gcloud storage cp \
    travel.jpg \
    "gs://$BUCKET_NAME/travel.jpg" \
    --project="$PROJECT_ID" \
    --quiet

  if [[ $? -eq 0 ]]; then
    print_success "travel.jpg uploaded to gs://$BUCKET_NAME"
  else
    print_error "Unable to upload travel.jpg"
  fi

else
  print_error "Unable to download travel.jpg"
fi

# ============================================================
# Task 4 - Create notification channel
# ============================================================

print_step "[8/8] Creating Monitoring alert policy"

echo "${WHITE}Notification email:${RESET} ${CYAN}${ALERT_EMAIL}${RESET}"

NOTIFICATION_CHANNEL=$(gcloud beta monitoring channels list \
  --project="$PROJECT_ID" \
  --filter="type=email AND labels.email_address=\"$ALERT_EMAIL\"" \
  --format="value(name)" \
  --limit=1 \
  2>/dev/null)

if [[ -z "$NOTIFICATION_CHANNEL" ]]; then

  echo "${YELLOW}Creating email notification channel...${RESET}"

  NOTIFICATION_CHANNEL=$(gcloud beta monitoring channels create \
    --project="$PROJECT_ID" \
    --display-name="Cloud Function Alert Email" \
    --description="Email notification for active Cloud Run Function instances" \
    --type="email" \
    --channel-labels="email_address=$ALERT_EMAIL" \
    --format="value(name)" \
    --quiet \
    2>/dev/null)

fi

if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
  print_success "Email notification channel created"
  CHANNEL_JSON="\"$NOTIFICATION_CHANNEL\""
else
  print_warning "Email notification channel could not be created"
  CHANNEL_JSON=""
fi

# Remove existing policy with the same name
EXISTING_POLICY=$(gcloud monitoring policies list \
  --project="$PROJECT_ID" \
  --filter='displayName="Active Cloud Run Function Instances"' \
  --format="value(name)" \
  --limit=1 \
  2>/dev/null)

if [[ -n "$EXISTING_POLICY" ]]; then

  print_warning "Existing alert policy found; recreating it"

  gcloud monitoring policies delete \
    "$EXISTING_POLICY" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1

fi

cat > active-instances-policy.json <<EOF_POLICY
{
  "displayName": "Active Cloud Run Function Instances",
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
    ${CHANNEL_JSON}
  ],
  "conditions": [
    {
      "displayName": "Cloud Function - Active instances greater than zero",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_function\" AND metric.type = \"cloudfunctions.googleapis.com/function/active_instances\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "trigger": {
          "count": 1
        },
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MAX",
            "crossSeriesReducer": "REDUCE_NONE"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  }
}
EOF_POLICY

gcloud monitoring policies create \
  --project="$PROJECT_ID" \
  --policy-from-file="active-instances-policy.json" \
  --quiet

POLICY_STATUS=$?

if [[ $POLICY_STATUS -eq 0 ]]; then
  print_success "Alert policy created successfully"
else
  print_error "Unable to create alert policy"
fi

# ============================================================
# Final summary
# ============================================================

echo
echo "${BG_GREEN}${BLACK}${BOLD}"
echo "============================================================"
echo " Lab execution completed"
echo " © ePlus.DEV"
echo "============================================================"
echo "${RESET}"

echo
echo "${WHITE}${BOLD}Bucket:${RESET}"
echo "${CYAN}gs://${BUCKET_NAME}${RESET}"

echo
echo "${WHITE}${BOLD}Pub/Sub topic:${RESET}"
echo "${CYAN}${TOPIC_NAME}${RESET}"

echo
echo "${WHITE}${BOLD}Cloud Run Function:${RESET}"
echo "${CYAN}${FUNCTION_NAME}${RESET}"

echo
echo "${WHITE}${BOLD}Alert policy:${RESET}"
echo "${CYAN}Active Cloud Run Function Instances${RESET}"

echo
echo "${YELLOW}${BOLD}Now click Check my progress for all tasks.${RESET}"
echo