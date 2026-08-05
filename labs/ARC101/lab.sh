#!/bin/bash

# ============================================================
# Travel Thumbnail Challenge Lab
# © ePlus.DEV
#
# IMPORTANT:
# - No "set -e"
# - No infinite deployment loop
# - Required input is entered directly in the terminal
# ============================================================

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
# Display functions
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

# ============================================================
# Required terminal input
# ============================================================

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
      print_error "${LABEL} cannot be empty."
    fi
  done

  printf -v "$VARIABLE_NAME" '%s' "$VALUE"
  export "$VARIABLE_NAME"
}

# ============================================================
# Start
# ============================================================

echo
echo "${BG_MAGENTA}${WHITE}${BOLD}"
echo "============================================================"
echo " Travel Thumbnail Challenge Lab"
echo " © ePlus.DEV"
echo "============================================================"
echo "${RESET}"

# Always require terminal input
unset BUCKET_NAME
unset TOPIC_NAME
unset FUNCTION_NAME
unset BUCKET_USER

echo "${CYAN}${BOLD}Please enter the values from the lab instructions.${RESET}"
echo

prompt_required "BUCKET_NAME" "BUCKET_NAME"
prompt_required "TOPIC_NAME" "TOPIC_NAME"
prompt_required "FUNCTION_NAME" "FUNCTION_NAME"
prompt_required "BUCKET_USER" "BUCKET_USER"

echo
print_success "Input completed"
echo

echo "${WHITE}${BOLD}BUCKET_NAME   :${RESET} ${CYAN}${BUCKET_NAME}${RESET}"
echo "${WHITE}${BOLD}TOPIC_NAME    :${RESET} ${CYAN}${TOPIC_NAME}${RESET}"
echo "${WHITE}${BOLD}FUNCTION_NAME :${RESET} ${CYAN}${FUNCTION_NAME}${RESET}"
echo "${WHITE}${BOLD}BUCKET_USER   :${RESET} ${CYAN}${BUCKET_USER}${RESET}"

# ============================================================
# Project configuration
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  print_error "No Google Cloud project is configured."
  echo "Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
  --format="value(projectNumber)" \
  2>/dev/null)

if [[ -z "$PROJECT_NUMBER" ]]; then
  print_error "Unable to obtain the project number."
  exit 1
fi

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe--format="value(commonInstanceMetadata.items[google-compute-default-region])")

RUNTIME_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

EVENTARC_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com"

STORAGE_SERVICE_AGENT="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"

PUBSUB_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

ALERT_EMAIL=$(gcloud config get-value account 2>/dev/null)

WORK_DIR="$HOME/travel-thumbnail-function"

POLICY_NAME="Active Cloud Run Function Instances"

echo
echo "${BLUE}${BOLD}Project configuration:${RESET}"
echo "${WHITE}PROJECT_ID              :${RESET} ${CYAN}${PROJECT_ID}${RESET}"
echo "${WHITE}PROJECT_NUMBER          :${RESET} ${CYAN}${PROJECT_NUMBER}${RESET}"
echo "${WHITE}REGION                  :${RESET} ${CYAN}${REGION}${RESET}"
echo "${WHITE}ZONE                    :${RESET} ${CYAN}${ZONE}${RESET}"
echo "${WHITE}RUNTIME SERVICE ACCOUNT :${RESET} ${CYAN}${RUNTIME_SERVICE_ACCOUNT}${RESET}"
echo "${WHITE}EVENTARC SERVICE AGENT  :${RESET} ${CYAN}${EVENTARC_SERVICE_AGENT}${RESET}"
echo "${WHITE}ALERT EMAIL             :${RESET} ${CYAN}${ALERT_EMAIL}${RESET}"

# ============================================================
# 1. Enable required APIs
# ============================================================

print_step "[1/9] Enabling required APIs"

gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudresourcemanager.googleapis.com \
  eventarc.googleapis.com \
  iam.googleapis.com \
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
# 2. Create service identities
# ============================================================

print_step "[2/9] Creating Google-managed service identities"

echo "${YELLOW}Creating Eventarc service identity...${RESET}"

gcloud beta services identity create \
  --service="eventarc.googleapis.com" \
  --project="$PROJECT_ID" \
  --quiet

if [[ $? -eq 0 ]]; then
  print_success "Eventarc service identity is ready"
else
  print_warning "Eventarc service identity may already exist"
fi

echo
echo "${YELLOW}Creating Pub/Sub service identity...${RESET}"

gcloud beta services identity create \
  --service="pubsub.googleapis.com" \
  --project="$PROJECT_ID" \
  --quiet

if [[ $? -eq 0 ]]; then
  print_success "Pub/Sub service identity is ready"
else
  print_warning "Pub/Sub service identity may already exist"
fi

# ============================================================
# 3. Create bucket
# ============================================================

print_step "[3/9] Creating Cloud Storage bucket"

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
echo "${YELLOW}${BOLD}Granting Storage Object Viewer to:${RESET}"
echo "${CYAN}${BUCKET_USER}${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:$BUCKET_USER" \
  --role="roles/storage.objectViewer" \
  --condition=None \
  --quiet >/dev/null

if [[ $? -eq 0 ]]; then
  print_success "Storage Object Viewer granted"
else
  print_warning "Unable to grant Storage Object Viewer"
fi

# ============================================================
# 4. Create Pub/Sub topic
# ============================================================

print_step "[4/9] Creating Pub/Sub topic"

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
# 5. Configure IAM
# ============================================================

print_step "[5/9] Configuring Eventarc and Function IAM permissions"

echo "${YELLOW}Granting Eventarc Service Agent role...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$EVENTARC_SERVICE_AGENT" \
  --role="roles/eventarc.serviceAgent" \
  --condition=None \
  --quiet >/dev/null

if [[ $? -eq 0 ]]; then
  print_success "Eventarc Service Agent role granted"
else
  print_warning "Eventarc Service Agent role may already exist"
fi

echo
echo "${YELLOW}Granting Eventarc Event Receiver to runtime account...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/eventarc.eventReceiver" \
  --condition=None \
  --quiet >/dev/null

echo "${YELLOW}Granting Cloud Run Invoker to runtime account...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/run.invoker" \
  --condition=None \
  --quiet >/dev/null

echo "${YELLOW}Granting Storage Object Admin to runtime account...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/storage.objectAdmin" \
  --condition=None \
  --quiet >/dev/null

echo "${YELLOW}Granting Pub/Sub Publisher to runtime account...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/pubsub.publisher" \
  --condition=None \
  --quiet >/dev/null

echo "${YELLOW}Granting Logging Writer to runtime account...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/logging.logWriter" \
  --condition=None \
  --quiet >/dev/null

echo "${YELLOW}Granting Pub/Sub Publisher to Cloud Storage service agent...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$STORAGE_SERVICE_AGENT" \
  --role="roles/pubsub.publisher" \
  --condition=None \
  --quiet >/dev/null

echo "${YELLOW}Granting Service Account Token Creator to Pub/Sub service agent...${RESET}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$PUBSUB_SERVICE_AGENT" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --condition=None \
  --quiet >/dev/null

print_success "IAM permissions configured"

echo
echo "${YELLOW}${BOLD}Waiting 90 seconds for Eventarc IAM propagation...${RESET}"

for SECOND in 90 75 60 45 30 15; do
  echo "${YELLOW}Eventarc IAM propagation: approximately ${SECOND} seconds remaining...${RESET}"
  sleep 15
done

print_success "IAM propagation wait completed"

# ============================================================
# 6. Create function source
# ============================================================

print_step "[6/9] Creating Cloud Run Function source"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

cd "$WORK_DIR" || {
  print_error "Unable to open working directory"
  exit 1
}

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

  const nameParts = fileName.split(".");
  const extension = nameParts.pop().toLowerCase();

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
# 7. Remove stale triggers and deploy function
# ============================================================

print_step "[7/9] Deploying Cloud Run Function Gen2"

echo "${YELLOW}Checking for stale Eventarc triggers...${RESET}"

STALE_TRIGGERS=$(gcloud eventarc triggers list \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --format="value(name)" \
  2>/dev/null |
  grep "^${FUNCTION_NAME}-")

if [[ -n "$STALE_TRIGGERS" ]]; then

  while IFS= read -r TRIGGER_NAME; do
    if [[ -n "$TRIGGER_NAME" ]]; then
      echo "${YELLOW}Deleting stale trigger: ${TRIGGER_NAME}${RESET}"

      gcloud eventarc triggers delete "$TRIGGER_NAME" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --quiet
    fi
  done <<< "$STALE_TRIGGERS"

  echo "${YELLOW}Waiting 20 seconds after removing stale triggers...${RESET}"
  sleep 20

else
  print_success "No stale Eventarc trigger found"
fi

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

DEPLOY_SUCCESS=false

for ATTEMPT in 1 2 3; do
  echo
  echo "${CYAN}${BOLD}Deployment attempt ${ATTEMPT}/3${RESET}"

  deploy_function

  DEPLOY_STATUS=$?

  if [[ $DEPLOY_STATUS -eq 0 ]]; then
    DEPLOY_SUCCESS=true
    break
  fi

  print_warning "Deployment attempt ${ATTEMPT} failed"

  if [[ $ATTEMPT -lt 3 ]]; then
    echo "${YELLOW}Refreshing Eventarc service identity and permissions...${RESET}"

    gcloud beta services identity create \
      --service="eventarc.googleapis.com" \
      --project="$PROJECT_ID" \
      --quiet >/dev/null 2>&1

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:$EVENTARC_SERVICE_AGENT" \
      --role="roles/eventarc.serviceAgent" \
      --condition=None \
      --quiet >/dev/null

    echo "${YELLOW}Waiting 60 seconds before retrying...${RESET}"

    for SECOND in 60 45 30 15; do
      echo "${YELLOW}Approximately ${SECOND} seconds remaining...${RESET}"
      sleep 15
    done
  fi
done

if [[ "$DEPLOY_SUCCESS" == "true" ]]; then
  print_success "Cloud Run Function deployed successfully"
else
  print_error "Function deployment failed after three attempts"
  print_warning "The script will continue and will not close the terminal"
fi

# ============================================================
# 8. Upload test image
# ============================================================

print_step "[8/9] Uploading test image"

cd "$WORK_DIR" || exit 1

rm -f travel.jpg

wget -q \
  "https://storage.googleapis.com/cloud-training/arc101/travel.jpg" \
  -O travel.jpg

if [[ -f travel.jpg && -s travel.jpg ]]; then
  print_success "travel.jpg downloaded"

  # Delete the old image before upload so a new finalize event is generated.
  gcloud storage rm \
    "gs://$BUCKET_NAME/travel.jpg" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1

  gcloud storage rm \
    "gs://$BUCKET_NAME/travel.64x64_thumbnail.jpg" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1

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
# 9. Create alert policy
# ============================================================

print_step "[9/9] Creating Monitoring alert policy"

echo "${WHITE}Notification email:${RESET} ${CYAN}${ALERT_EMAIL}${RESET}"

NOTIFICATION_CHANNEL=""

if [[ "$ALERT_EMAIL" == *"@"* ]]; then

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

fi

if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
  print_success "Email notification channel is ready"
  CHANNEL_JSON="\"$NOTIFICATION_CHANNEL\""
else
  print_warning "Email notification channel could not be created"
  CHANNEL_JSON=""
fi

echo "${YELLOW}Checking for an existing alert policy...${RESET}"

EXISTING_POLICIES=$(gcloud monitoring policies list \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$POLICY_NAME\"" \
  --format="value(name)" \
  2>/dev/null)

if [[ -n "$EXISTING_POLICIES" ]]; then

  while IFS= read -r EXISTING_POLICY; do
    if [[ -n "$EXISTING_POLICY" ]]; then
      echo "${YELLOW}Deleting existing policy: ${EXISTING_POLICY}${RESET}"

      gcloud monitoring policies delete \
        "$EXISTING_POLICY" \
        --project="$PROJECT_ID" \
        --quiet >/dev/null 2>&1
    fi
  done <<< "$EXISTING_POLICIES"

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
  print_error "Unable to create the alert policy"
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
echo "${WHITE}${BOLD}Bucket user:${RESET}"
echo "${CYAN}${BUCKET_USER}${RESET}"

echo
echo "${WHITE}${BOLD}Pub/Sub topic:${RESET}"
echo "${CYAN}${TOPIC_NAME}${RESET}"

echo
echo "${WHITE}${BOLD}Cloud Run Function:${RESET}"
echo "${CYAN}${FUNCTION_NAME}${RESET}"

echo
echo "${WHITE}${BOLD}Function deployment:${RESET}"

if [[ "$DEPLOY_SUCCESS" == "true" ]]; then
  echo "${GREEN}SUCCESS${RESET}"
else
  echo "${RED}FAILED${RESET}"
fi

echo
echo "${WHITE}${BOLD}Alert policy:${RESET}"
echo "${CYAN}${POLICY_NAME}${RESET}"

echo
echo "${YELLOW}${BOLD}Now click Check my progress for all tasks.${RESET}"
echo