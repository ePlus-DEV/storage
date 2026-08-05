#!/bin/bash

# ============================================================
# Define color variables
# ============================================================

BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)

# ============================================================
# Start
# ============================================================

clear

echo "${BG_MAGENTA}${WHITE}${BOLD}"
echo "============================================================"
echo " Travel Thumbnail Challenge Lab - © ePlus.DEV"
echo "============================================================"
echo "${RESET}"

# ============================================================
# Required input
# ============================================================

echo "${CYAN}${BOLD}Enter the values from the Lab Details:${RESET}"
echo

while [[ -z "${BUCKET_NAME:-}" ]]; do
  read -r -p "Enter BUCKET_NAME: " BUCKET_NAME </dev/tty

  if [[ -z "$BUCKET_NAME" ]]; then
    echo "${RED}BUCKET_NAME cannot be empty.${RESET}"
  fi
done

while [[ -z "${TOPIC_NAME:-}" ]]; do
  read -r -p "Enter TOPIC_NAME: " TOPIC_NAME </dev/tty

  if [[ -z "$TOPIC_NAME" ]]; then
    echo "${RED}TOPIC_NAME cannot be empty.${RESET}"
  fi
done

while [[ -z "${FUNCTION_NAME:-}" ]]; do
  read -r -p "Enter FUNCTION_NAME: " FUNCTION_NAME </dev/tty

  if [[ -z "$FUNCTION_NAME" ]]; then
    echo "${RED}FUNCTION_NAME cannot be empty.${RESET}"
  fi
done

while [[ -z "${BUCKET_USER:-}" ]]; do
  read -r -p "Enter BUCKET_USER: " BUCKET_USER </dev/tty

  if [[ -z "$BUCKET_USER" ]]; then
    echo "${RED}BUCKET_USER cannot be empty.${RESET}"
  fi
done

export BUCKET_NAME
export TOPIC_NAME
export FUNCTION_NAME
export BUCKET_USER

# ============================================================
# Project information
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
  --format="value(projectNumber)" 2>/dev/null)

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe--format="value(commonInstanceMetadata.items[google-compute-default-region])")

RUNTIME_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
STORAGE_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
PUBSUB_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

# Use the currently signed-in account for the monitoring email channel.
# This does not require a fifth terminal input.
ALERT_EMAIL=$(gcloud config get-value account 2>/dev/null)

echo
echo "${BLUE}${BOLD}Configuration:${RESET}"
echo "PROJECT_ID    : $PROJECT_ID"
echo "REGION        : $REGION"
echo "BUCKET_NAME   : $BUCKET_NAME"
echo "TOPIC_NAME    : $TOPIC_NAME"
echo "FUNCTION_NAME : $FUNCTION_NAME"
echo "BUCKET_USER   : $BUCKET_USER"
echo "ALERT_EMAIL   : $ALERT_EMAIL"
echo

# ============================================================
# Enable APIs
# ============================================================

echo "${CYAN}${BOLD}[1/8] Enabling required APIs...${RESET}"

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

gcloud config set compute/region "$REGION" --quiet
gcloud config set compute/zone "$ZONE" --quiet

echo "${GREEN}✓ Required APIs enabled.${RESET}"

# ============================================================
# Task 1 - Create bucket
# ============================================================

echo
echo "${CYAN}${BOLD}[2/8] Creating Cloud Storage bucket...${RESET}"

if gcloud storage buckets describe "gs://$BUCKET_NAME" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  echo "${YELLOW}⚠ Bucket already exists: gs://$BUCKET_NAME${RESET}"

else

  gcloud storage buckets create "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --quiet

fi

echo "${GREEN}✓ Bucket is ready.${RESET}"

echo
echo "${CYAN}${BOLD}Granting Storage Object Viewer to $BUCKET_USER...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:$BUCKET_USER" \
  --role="roles/storage.objectViewer" \
  --condition=None \
  --quiet >/dev/null

echo "${GREEN}✓ Storage Object Viewer granted.${RESET}"

# ============================================================
# Task 2 - Create Pub/Sub topic
# ============================================================

echo
echo "${CYAN}${BOLD}[3/8] Creating Pub/Sub topic...${RESET}"

if gcloud pubsub topics describe "$TOPIC_NAME" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  echo "${YELLOW}⚠ Topic already exists: $TOPIC_NAME${RESET}"

else

  gcloud pubsub topics create "$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --quiet

fi

echo "${GREEN}✓ Pub/Sub topic is ready.${RESET}"

# ============================================================
# Prepare service account permissions
# ============================================================

echo
echo "${CYAN}${BOLD}[4/8] Preparing IAM permissions...${RESET}"

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

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$PUBSUB_SERVICE_ACCOUNT" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --condition=None \
  --quiet >/dev/null

echo "${GREEN}✓ IAM permissions prepared.${RESET}"

echo "${YELLOW}Waiting for IAM propagation...${RESET}"
sleep 15

# ============================================================
# Create function source
# ============================================================

echo
echo "${CYAN}${BOLD}[5/8] Creating Cloud Run Function source...${RESET}"

WORK_DIR="$HOME/travel-thumbnail-function"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || return

cat > index.js <<EOF_INDEX
/* globals exports, require */
// jshint strict: false
// jshint esversion: 6
"use strict";

const {Storage} = require("@google-cloud/storage");
const {PubSub} = require("@google-cloud/pubsub");
const sharp = require("sharp");

const gcs = new Storage();
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

  const fileNameWithoutExtension =
    fileName.substring(
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

  const bucket = gcs.bucket(bucketName);
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

echo "${GREEN}✓ Function source created.${RESET}"

# ============================================================
# Deploy Cloud Run Function Gen2
# ============================================================

echo
echo "${CYAN}${BOLD}[6/8] Deploying Cloud Run Function Gen2...${RESET}"

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
DEPLOY_RESULT=$?

if [[ $DEPLOY_RESULT -ne 0 ]]; then
  echo
  echo "${YELLOW}First deployment failed. Waiting and retrying once...${RESET}"

  sleep 20
  deploy_function

  DEPLOY_RESULT=$?
fi

if [[ $DEPLOY_RESULT -eq 0 ]]; then
  echo "${GREEN}✓ Cloud Run Function deployed successfully.${RESET}"
else
  echo "${RED}✗ Function deployment failed.${RESET}"
  echo "${YELLOW}The script will continue with the remaining tasks.${RESET}"
fi

# ============================================================
# Upload test image
# ============================================================

echo
echo "${CYAN}${BOLD}[7/8] Uploading test image...${RESET}"

cd "$WORK_DIR" || return

wget -q \
  "https://storage.googleapis.com/cloud-training/arc101/travel.jpg" \
  -O travel.jpg

if [[ -f travel.jpg ]]; then

  gcloud storage cp \
    travel.jpg \
    "gs://$BUCKET_NAME/travel.jpg" \
    --project="$PROJECT_ID" \
    --quiet

  echo "${GREEN}✓ travel.jpg uploaded.${RESET}"

else
  echo "${RED}✗ Unable to download travel.jpg.${RESET}"
fi

# ============================================================
# Task 4 - Alert notification channel
# ============================================================

echo
echo "${CYAN}${BOLD}[8/8] Creating Monitoring alert policy...${RESET}"

NOTIFICATION_CHANNEL=""

if [[ "$ALERT_EMAIL" == *"@"* ]]; then

  NOTIFICATION_CHANNEL=$(gcloud beta monitoring channels list \
    --project="$PROJECT_ID" \
    --filter="type=email AND labels.email_address=\"$ALERT_EMAIL\"" \
    --format="value(name)" \
    --limit=1 \
    2>/dev/null)

  if [[ -z "$NOTIFICATION_CHANNEL" ]]; then

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

fi

if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
  CHANNEL_JSON="\"$NOTIFICATION_CHANNEL\""
  echo "${GREEN}✓ Email notification channel is ready.${RESET}"
else
  CHANNEL_JSON=""
  echo "${YELLOW}⚠ Email channel could not be created. Creating policy without a channel.${RESET}"
fi

EXISTING_POLICY=$(gcloud monitoring policies list \
  --project="$PROJECT_ID" \
  --filter='displayName="Active Cloud Run Function Instances"' \
  --format="value(name)" \
  --limit=1 \
  2>/dev/null)

if [[ -n "$EXISTING_POLICY" ]]; then

  echo "${YELLOW}An existing alert policy was found. Recreating it...${RESET}"

  gcloud monitoring policies delete "$EXISTING_POLICY" \
    --project="$PROJECT_ID" \
    --quiet

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

POLICY_RESULT=$?

if [[ $POLICY_RESULT -eq 0 ]]; then
  echo "${GREEN}✓ Alert policy created successfully.${RESET}"
else
  echo "${RED}✗ Unable to create the alert policy.${RESET}"
fi

# ============================================================
# Final result
# ============================================================

echo
echo "${BG_GREEN}${BLACK}${BOLD}"
echo "============================================================"
echo " Lab execution completed - © ePlus.DEV"
echo "============================================================"
echo "${RESET}"

echo "${WHITE}Bucket:${RESET}"
echo "  gs://$BUCKET_NAME"

echo "${WHITE}Pub/Sub topic:${RESET}"
echo "  $TOPIC_NAME"

echo "${WHITE}Cloud Run Function:${RESET}"
echo "  $FUNCTION_NAME"

echo "${WHITE}Alert policy:${RESET}"
echo "  Active Cloud Run Function Instances"

echo
echo "${YELLOW}Now click Check my progress for all tasks.${RESET}"
echo