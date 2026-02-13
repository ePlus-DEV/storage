#!/bin/bash
set -euo pipefail

# ==============================================================================
#  ePlus.DEV - Qwiklabs Full Automation Script (Task 1 -> 7)
#  Copyright (c) 2026 ePlus.DEV. All rights reserved.
# ==============================================================================

# -------------------- ANSI Colors (no tput) --------------------
COLOR_RED=$'\033[0;31m'
COLOR_GREEN=$'\033[0;32m'
COLOR_YELLOW=$'\033[0;33m'
COLOR_BLUE=$'\033[0;34m'
COLOR_CYAN=$'\033[0;36m'
COLOR_MAGENTA=$'\033[0;35m'
COLOR_RESET=$'\033[0m'
BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'
DIM=$'\033[2m'

banner() {
  clear || true
  echo "${COLOR_CYAN}${BOLD}=======================================================${COLOR_RESET}"
  echo "${COLOR_CYAN}${BOLD}                 ePlus.DEV - EXECUTION                 ${COLOR_RESET}"
  echo "${COLOR_CYAN}${BOLD}=======================================================${COLOR_RESET}"
  echo "${DIM}Copyright (c) 2026 ePlus.DEV. All rights reserved.${COLOR_RESET}"
  echo
}

info() { echo "${COLOR_CYAN}${BOLD}==>${COLOR_RESET} $*"; }
ok()   { echo "${COLOR_GREEN}${BOLD}✔${COLOR_RESET} $*"; }
warn() { echo "${COLOR_YELLOW}${BOLD}⚠${COLOR_RESET} $*"; }
err()  { echo "${COLOR_RED}${BOLD}✖${COLOR_RESET} $*"; }
need() { command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }; }

deploy_with_retry() {
  local fn="$1"; shift
  local attempts=0 max_attempts=5
  while [ $attempts -lt $max_attempts ]; do
    info "Attempt $((attempts+1)) deploying: ${fn}"
    if gcloud functions deploy "$fn" "$@"; then
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

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[ -n "${PROJECT_ID}" ] || { err "No active project. Run: gcloud config set project <PROJECT_ID>"; exit 1; }

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
REGION="europe-west4"
ZONE="${REGION}-a"

ok "PROJECT_ID: ${PROJECT_ID}"
ok "PROJECT_NUMBER: ${PROJECT_NUMBER}"
ok "REGION: ${REGION}"
ok "ZONE: ${ZONE}"

# -------------------- Task 1: Enable APIs --------------------
info "Task 1: Enabling required APIs..."
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  cloudaicompanion.googleapis.com >/dev/null
ok "APIs enabled"

# -------------------- Task 2: HTTP function --------------------
info "Task 2: Deploy HTTP function (nodejs-http-function)"
mkdir -p ~/hello-http && cd ~/hello-http

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
  --max-instances 1

info "Calling nodejs-http-function..."
gcloud functions call nodejs-http-function --gen2 --region "${REGION}" >/dev/null
ok "Task 2 OK"

# -------------------- Task 3: Storage function --------------------
info "Task 3: Deploy Storage function (nodejs-storage-function)"

SERVICE_ACCOUNT="$(gsutil kms serviceaccount -p "${PROJECT_NUMBER}")"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${SERVICE_ACCOUNT}" \
  --role roles/pubsub.publisher \
  --quiet >/dev/null 2>&1 || true
ok "IAM set: pubsub.publisher for Cloud Storage SA"

mkdir -p ~/hello-storage && cd ~/hello-storage

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
gsutil mb -l "${REGION}" "${BUCKET}" >/dev/null 2>&1 || true
ok "Bucket ready: ${BUCKET}"

deploy_with_retry nodejs-storage-function \
  --gen2 \
  --runtime nodejs22 \
  --entry-point helloStorage \
  --source . \
  --region "${REGION}" \
  --trigger-bucket "${BUCKET}" \
  --trigger-location "${REGION}" \
  --max-instances 1

echo "Hello World" > random.txt
gsutil cp random.txt "${BUCKET}/random.txt" >/dev/null
ok "Task 3 OK (event triggered)"

# -------------------- Task 4: Audit logs function --------------------
info "Task 4: Deploy Audit Logs function (gce-vm-labeler)"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role roles/eventarc.eventReceiver \
  --quiet >/dev/null 2>&1 || true
ok "IAM set: eventarc.eventReceiver for default compute SA"

# Enable audit configs for compute.googleapis.com via set-iam-policy (best-effort)
info "Enabling Audit Logs for compute.googleapis.com (ADMIN/DATA READ/WRITE)..."
TMP_POLICY="$(mktemp)"
gcloud projects get-iam-policy "${PROJECT_ID}" --format=yaml > "${TMP_POLICY}"

# Drop previous auditConfigs section to avoid dup (simple, works for labs)
sed -i '/^auditConfigs:/,$d' "${TMP_POLICY}" 2>/dev/null || true
cat >> "${TMP_POLICY}" <<'EOF'
auditConfigs:
- auditLogConfigs:
  - logType: ADMIN_READ
  - logType: DATA_READ
  - logType: DATA_WRITE
  service: compute.googleapis.com
EOF
gcloud projects set-iam-policy "${PROJECT_ID}" "${TMP_POLICY}" >/dev/null
rm -f "${TMP_POLICY}"
ok "Audit logs config applied"

cd ~
[ -d ~/eventarc-samples ] || git clone https://github.com/GoogleCloudPlatform/eventarc-samples.git >/dev/null
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
ok "Task 4 function deployed"

# Create VM by CLI (lab đôi khi muốn tạo bằng Console, nhưng script vẫn làm hết)
warn "Creating VM instance-1 by CLI (lab may prefer Console, but we'll try)..."
gcloud compute instances create instance-1 \
  --zone "${ZONE}" \
  --machine-type e2-medium \
  --quiet || true

ok "VM create command executed. (If Task 'Create a VM instance' doesn't pass, create the VM once in Console.)"

# -------------------- Task 5: Deploy different revisions (FULL CLI) --------------------
info "Task 5: Deploy hello-world-colored revision #1 (orange) then revision #2 (yellow)"

mkdir -p ~/hello-world-colored && cd ~/hello-world-colored
cat > main.py <<'EOF'
import os
color = os.environ.get('COLOR')

def hello_world(request):
    return f'<body style="background-color:{color}"><h1>Hello World!</h1></body>'
EOF
: > requirements.txt

# Revision 1: orange
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

# Revision 2: yellow (deploy again -> new revision)
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

HELLO_URL="$(gcloud functions describe hello-world-colored --region "${REGION}" --gen2 --format="value(serviceConfig.uri)")"
ok "Task 5 done. URL:"
echo "  ${HELLO_URL}"

# Show revisions count (Cloud Run backing service)
warn "Revisions (Cloud Run backing service):"
gcloud run revisions list --service hello-world-colored --region "${REGION}" --format="table(metadata.name,status.conditions[0].status,metadata.creationTimestamp)" || true

# -------------------- Task 6: Minimum instances (FULL CLI) --------------------
info "Task 6: Deploy slow-function then set min instances=1 via CLI"

mkdir -p ~/min-instances && cd ~/min-instances
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

# Deploy (min defaults to 0)
deploy_with_retry slow-function \
  --gen2 \
  --runtime go123 \
  --entry-point HelloWorld \
  --source . \
  --region "${REGION}" \
  --trigger-http \
  --allow-unauthenticated \
  --max-instances 4

# Force min instances via Cloud Run service update (replaces UI)
info "Updating Cloud Run service for slow-function: min=1, max=4..."
gcloud run services update slow-function \
  --region "${REGION}" \
  --min-instances 1 \
  --max-instances 4 \
  --quiet

info "Calling slow-function..."
gcloud functions call slow-function --gen2 --region "${REGION}" >/dev/null
ok "Task 6 done"

# -------------------- Task 7: Concurrency (FULL CLI) --------------------
info "Task 7: Deploy slow-concurrent-function then set concurrency=100 + cpu=1 via CLI"

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

SLOW_CONCURRENT_URL="$(gcloud functions describe slow-concurrent-function --region "${REGION}" --gen2 --format="value(serviceConfig.uri)")"
ok "Function deployed. URL:"
echo "  ${SLOW_CONCURRENT_URL}"

info "Updating Cloud Run service for slow-concurrent-function: cpu=1, concurrency=100, max=4..."
gcloud run services update slow-concurrent-function \
  --region "${REGION}" \
  --cpu 1 \
  --concurrency 100 \
  --max-instances 4 \
  --quiet

ok "Task 7 done"

echo
ok "ALL DONE (Task 1 -> 7 via script). Now click 'Check my progress' for each task."
echo "${COLOR_RED}${BOLD}${UNDERLINE}https://eplus.dev${COLOR_RESET}"