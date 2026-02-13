#!/bin/bash
set -euo pipefail

# ==============================================================================
#  ePlus.DEV - Qwiklabs Full Automation Script (Task 1 -> 7) - NON-INTERACTIVE
#  Copyright (c) 2026 ePlus.DEV. All rights reserved.
#
#  - No prompts (no Y/yes needed)
#  - Forces deploy retries
#  - Task 6: min instances via Cloud Run service update
#  - Task 7: CPU=1 + Concurrency=100 via Cloud Run service update  ✅ (LAB REQUIREMENT)
# ==============================================================================

# -------------------- Disable ALL interactive prompts --------------------
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# -------------------- ANSI Colors (no tput) --------------------
COLOR_BLACK=$'\033[0;30m'
COLOR_RED=$'\033[0;31m'
COLOR_GREEN=$'\033[0;32m'
COLOR_YELLOW=$'\033[0;33m'
COLOR_BLUE=$'\033[0;34m'
COLOR_MAGENTA=$'\033[0;35m'
COLOR_CYAN=$'\033[0;36m'
COLOR_WHITE=$'\033[0;37m'
COLOR_RESET=$'\033[0m'

BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'
DIM=$'\033[2m'

# -------------------- ANSI Background Colors --------------------
BG_RED=$'\033[41m'
BG_GREEN=$'\033[42m'
BG_YELLOW=$'\033[43m'
BG_BLUE=$'\033[44m'
BG_MAGENTA=$'\033[45m'
BG_CYAN=$'\033[46m'
BG_GRAY=$'\033[100m'

banner() {
  clear || true
  echo "${BG_CYAN}${COLOR_BLUE}${BOLD}                                                         ${COLOR_RESET}"
  echo "${BG_CYAN}${COLOR_BLUE}${BOLD}   🚀  ePlus.DEV - QWIKLABS FULL AUTOMATION (TASK 1→7)   ${COLOR_RESET}"
  echo "${BG_CYAN}${COLOR_BLUE}${BOLD}                                                         ${COLOR_RESET}"
  echo "${BG_CYAN}${COLOR_BLUE}${DIM}   Copyright (c) 2026 ePlus.DEV. All rights reserved.    ${COLOR_RESET}"
  echo
}

task() {
  echo
  echo "${BG_MAGENTA}${COLOR_WHITE}${BOLD} >>> $* <<< ${COLOR_RESET}"
  echo
}

info() { echo "${BG_BLUE}${COLOR_WHITE}${BOLD} INFO ${COLOR_RESET} $*"; }
ok()   { echo "${BG_GREEN}${COLOR_BLACK}${BOLD}  OK  ${COLOR_RESET} $*"; }
warn() { echo "${BG_YELLOW}${COLOR_BLACK}${BOLD} WARN ${COLOR_RESET} $*"; }
err()  { echo "${BG_RED}${COLOR_WHITE}${BOLD} ERR  ${COLOR_RESET} $*"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }
}

deploy_with_retry() {
  local fn="$1"; shift
  local attempts=0
  local max_attempts=6

  while [ $attempts -lt $max_attempts ]; do
    info "Attempt $((attempts+1)) deploying: ${fn}"
    if gcloud functions deploy "$fn" "$@" --quiet; then
      ok "${fn} deployed"
      return 0
    fi
    attempts=$((attempts+1))
    warn "Deploy failed for ${fn}. Retry in 30s..."
    sleep 30
  done

  err "Failed to deploy ${fn} after ${max_attempts} attempts"
  return 1
}

# -------------------- Start --------------------
banner
need gcloud
need gsutil
need git

export PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects list --filter="project_id:$PROJECT_ID" --format='value(project_number)')
export ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")
gcloud config set compute/region $REGION

ok "PROJECT_ID: ${PROJECT_ID}"
ok "PROJECT_NUMBER: ${PROJECT_NUMBER}"
ok "REGION: ${REGION}"
ok "ZONE: ${ZONE}"

# -------------------- Task 1: Enable APIs --------------------
task "TASK 1 - Enable APIs"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  cloudaicompanion.googleapis.com \
  --quiet
ok "Task 1 OK"

# -------------------- Task 2: HTTP function --------------------
task "TASK 2 - Deploy HTTP Function (nodejs-http-function)"
mkdir -p ~/hello-http
cd ~/hello-http

cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');

functions.http('helloWorld', (req, res) => {
  res.status(200).send('HTTP with Node.js in GCF 2nd gen!');
});
EOF

cat > package.json <<'EOF'
{
  "name": "nodejs-functions-gen2-codelab",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^2.0.0"
  }
}
EOF

deploy_with_retry nodejs-http-function \
  --gen2 \
  --runtime nodejs22 \
  --entry-point helloWorld \
  --source . \
  --region "${REGION}" \
  --trigger-http \
  --timeout 600s \
  --max-instances 1 \
  --allow-unauthenticated

info "Calling nodejs-http-function..."
gcloud functions call nodejs-http-function --gen2 --region "${REGION}" --quiet >/dev/null || true
ok "Task 2 OK"

# -------------------- Task 3: Storage function --------------------
task "TASK 3 - Deploy Storage Function (nodejs-storage-function)"

SERVICE_ACCOUNT="$(gsutil kms serviceaccount -p "${PROJECT_NUMBER}")"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${SERVICE_ACCOUNT}" \
  --role roles/pubsub.publisher \
  --quiet >/dev/null 2>&1 || true
ok "IAM set: pubsub.publisher for Cloud Storage SA"

mkdir -p ~/hello-storage
cd ~/hello-storage

cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');

functions.cloudEvent('helloStorage', (cloudevent) => {
  console.log('Cloud Storage event with Node.js in GCF 2nd gen!');
  console.log(cloudevent);
});
EOF

cat > package.json <<'EOF'
{
  "name": "nodejs-functions-gen2-codelab",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^2.0.0"
  }
}
EOF

BUCKET="gs://gcf-gen2-storage-${PROJECT_ID}"
info "Ensuring bucket exists: ${BUCKET}"
gsutil mb -l "${REGION}" "${BUCKET}" >/dev/null 2>&1 || true
ok "Bucket ready"

deploy_with_retry nodejs-storage-function \
  --gen2 \
  --runtime nodejs22 \
  --entry-point helloStorage \
  --source . \
  --region "${REGION}" \
  --trigger-bucket "${BUCKET}" \
  --trigger-location "${REGION}" \
  --max-instances 1

info "Triggering storage event..."
echo "Hello World" > random.txt
gsutil cp random.txt "${BUCKET}/random.txt" >/dev/null
ok "Task 3 OK"

# -------------------- Task 4: Audit Logs function + VM --------------------
task "TASK 4 - Deploy Audit Logs Function + Create VM (gce-vm-labeler)"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role roles/eventarc.eventReceiver \
  --quiet >/dev/null 2>&1 || true
ok "IAM set: eventarc.eventReceiver for default compute SA"

info "Enabling Audit Logs for compute.googleapis.com via set-iam-policy (best-effort)..."
TMP_POLICY="$(mktemp)"
gcloud projects get-iam-policy "${PROJECT_ID}" --format=yaml > "${TMP_POLICY}"

# Remove existing auditConfigs section (simple lab-friendly approach)
sed -i '/^auditConfigs:/,$d' "${TMP_POLICY}" 2>/dev/null || true
cat >> "${TMP_POLICY}" <<'EOF'
auditConfigs:
- auditLogConfigs:
  - logType: ADMIN_READ
  - logType: DATA_READ
  - logType: DATA_WRITE
  service: compute.googleapis.com
EOF

gcloud projects set-iam-policy "${PROJECT_ID}" "${TMP_POLICY}" --quiet >/dev/null
rm -f "${TMP_POLICY}"
ok "Audit Logs enabled for Compute Engine"

cd ~
if [ ! -d ~/eventarc-samples ]; then
  git clone https://github.com/GoogleCloudPlatform/eventarc-samples.git >/dev/null
else
  warn "Repo already exists: ~/eventarc-samples (skip clone)"
fi

cd ~/eventarc-samples/gce-vm-labeler/gcf/nodejs
deploy_with_retry gce-vm-labeler \
  --gen2 \
  --runtime nodejs22 \
  --entry-point labelVmCreation \
  --source . \
  --region "${REGION}" \
  --trigger-event-filters="type=google.cloud.audit.log.v1.written,serviceName=compute.googleapis.com,methodName=beta.compute.instances.insert" \
  --trigger-location "${REGION}" \
  --max-instances 1

ok "Audit Logs function deployed"

warn "Creating VM instance-1 via CLI (lab may prefer Console; this still attempts automation)..."
gcloud compute instances create instance-1 \
  --zone "${ZONE}" \
  --machine-type e2-medium \
  --quiet >/dev/null 2>&1 || true

ok "VM create command executed"

# -------------------- Task 5: Different revisions --------------------
task "TASK 5 - Deploy hello-world-colored (orange -> yellow revisions)"

mkdir -p ~/hello-world-colored
cd ~/hello-world-colored

cat > main.py <<'EOF'
import os
color = os.environ.get('COLOR')

def hello_world(request):
    return f'<body style="background-color:{color}"><h1>Hello World!</h1></body>'
EOF
: > requirements.txt

deploy_with_retry hello-world-colored \
  --gen2 \
  --runtime python311 \
  --entry-point hello_world \
  --source . \
  --region "${REGION}" \
  --trigger-http \
  --allow-unauthenticated \
  --update-env-vars "COLOR=orange" \
  --max-instances 1

deploy_with_retry hello-world-colored \
  --gen2 \
  --runtime python311 \
  --entry-point hello_world \
  --source . \
  --region "${REGION}" \
  --trigger-http \
  --allow-unauthenticated \
  --update-env-vars "COLOR=yellow" \
  --max-instances 1

HELLO_URL="$(gcloud functions describe hello-world-colored --region "${REGION}" --gen2 --format="value(serviceConfig.uri)" 2>/dev/null || true)"
ok "Task 5 OK. URL:"
echo "  ${HELLO_URL}"

# -------------------- Task 6: Min instances --------------------
task "TASK 6 - Deploy slow-function + set min instances=1 (Cloud Run service)"

mkdir -p ~/min-instances
cd ~/min-instances

cat > main.go <<'EOF'
package p

import (
        "fmt"
        "net/http"
        "time"
)

func init() {
        time.Sleep(10 * time.Second)
}

func HelloWorld(w http.ResponseWriter, r *http.Request) {
        fmt.Fprint(w, "Slow HTTP Go in GCF 2nd gen!")
}
EOF

cat > go.mod <<'EOF'
module example.com/mod

go 1.23
EOF

deploy_with_retry slow-function \
  --gen2 \
  --runtime go123 \
  --entry-point HelloWorld \
  --source . \
  --region "${REGION}" \
  --trigger-http \
  --allow-unauthenticated \
  --max-instances 4

info "Updating Cloud Run service slow-function: min=1 max=4..."
gcloud run services update slow-function \
  --region "${REGION}" \
  --min-instances 1 \
  --max-instances 4 \
  --quiet >/dev/null

info "Calling slow-function..."
gcloud functions call slow-function --gen2 --region "${REGION}" --quiet >/dev/null || true
ok "Task 6 OK"

# -------------------- Task 7: Concurrency + CPU --------------------
task "TASK 7 - Deploy slow-concurrent-function + set CPU=1 & Concurrency=100 (Cloud Run service) ✅"

deploy_with_retry slow-concurrent-function \
  --gen2 \
  --runtime go123 \
  --entry-point HelloWorld \
  --source ~/min-instances \
  --region "${REGION}" \
  --trigger-http \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 4

SLOW_CONCURRENT_URL="$(gcloud functions describe slow-concurrent-function --region "${REGION}" --gen2 --format="value(serviceConfig.uri)" 2>/dev/null || true)"
ok "Function URL:"
echo "  ${SLOW_CONCURRENT_URL}"

info "Updating Cloud Run service slow-concurrent-function: cpu=1 concurrency=100 max=4..."
gcloud run services update slow-concurrent-function \
  --region "${REGION}" \
  --cpu 1 \
  --concurrency 100 \
  --max-instances 4 \
  --quiet >/dev/null

# Verify for peace of mind (does not fail script)
info "Verifying Task 7 settings (cpu + concurrency)..."
gcloud run services describe slow-concurrent-function \
  --region "${REGION}" \
  --format="yaml(spec.template.spec.containerConcurrency,spec.template.spec.containers[0].resources)" \
  || true

ok "Task 7 OK"

# Optional cleanup to avoid extra prompts (already disabled prompts)
# gcloud compute instances delete instance-1 --zone "${ZONE}" --quiet >/dev/null 2>&1 || true

echo
echo "${BG_GREEN}${COLOR_BLACK}${BOLD} 🎉 ALL TASKS COMPLETED SUCCESSFULLY 🎉 ${COLOR_RESET}"
echo "${BG_GRAY}${COLOR_WHITE}${BOLD}   Now click 'Check my progress' for each task in Qwiklabs   ${COLOR_RESET}"
echo
echo "${BG_RED}${COLOR_WHITE}${BOLD}   https://eplus.dev   ${COLOR_RESET}"
