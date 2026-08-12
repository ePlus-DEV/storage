#!/usr/bin/env bash

# ============================================================
# User Authentication with IAP - Full Lab Automation
# © ePlus.DEV
# ============================================================

set -Eeuo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# ========================= COLORS ============================

RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ========================= HELPERS ===========================

line() {
  printf '%*s\n' 70 '' | tr ' ' '='
}

section() {
  echo
  echo "${CYAN}${BOLD}$1${RESET}"
  line
}

success() {
  echo "${GREEN}✓ $1${RESET}"
}

warn() {
  echo "${YELLOW}⚠ $1${RESET}"
}

error() {
  echo "${RED}✗ $1${RESET}" >&2
}

trap '
  RC=$?
  echo
  error "Script failed at line ${LINENO}."
  error "Exit code: ${RC}"
  echo
  echo "${YELLOW}Check the error printed above and run:${RESET}"
  echo "  bash ~/lab.sh"
  exit ${RC}
' ERR

# Run long commands while continuously showing progress.
run_progress() {
  local label="$1"
  shift

  local logfile
  logfile="$(mktemp)"

  echo "${BLUE}→ ${label}${RESET}"

  set +e
  "$@" >"$logfile" 2>&1 &
  local pid=$!
  set -e

  local elapsed=0
  local spin='|/-\'
  local i=0

  while kill -0 "$pid" 2>/dev/null; do
    printf "\r${YELLOW}  %s %s | elapsed: %3ds${RESET}" \
      "${spin:i++%4:1}" "$label" "$elapsed"
    sleep 2
    elapsed=$((elapsed + 2))
  done

  local rc=0

  set +e
  wait "$pid"
  rc=$?
  set -e

  printf "\r%-100s\r" ""

  if [[ $rc -ne 0 ]]; then
    error "${label} failed."
    echo
    cat "$logfile"
    rm -f "$logfile"
    return "$rc"
  fi

  success "${label}"

  # Print useful final lines only.
  if [[ -s "$logfile" ]]; then
    tail -n 8 "$logfile" 2>/dev/null || true
  fi

  rm -f "$logfile"
}

retry_cmd() {
  local description="$1"
  local attempts="$2"
  local delay="$3"
  shift 3

  local n=1

  while true; do
    echo "${BLUE}→ ${description} [attempt ${n}/${attempts}]${RESET}"

    if "$@"; then
      success "$description"
      return 0
    fi

    if (( n >= attempts )); then
      error "$description failed after ${attempts} attempts."
      return 1
    fi

    warn "Not ready yet. Retrying in ${delay}s..."

    local remaining="$delay"

    while (( remaining > 0 )); do
      printf "\r${YELLOW}  Retry countdown: %2ds${RESET}" "$remaining"
      sleep 1
      remaining=$((remaining - 1))
    done

    printf "\r%-60s\r" ""
    n=$((n + 1))
  done
}

iap_enable() {
  if gcloud run services update "$SERVICE" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --iap \
      --quiet; then
    return 0
  fi

  warn "Stable gcloud IAP command failed. Trying beta..."

  gcloud beta run services update "$SERVICE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --iap \
    --quiet
}

iap_disable() {
  if gcloud run services update "$SERVICE" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --no-iap \
      --quiet; then
    return 0
  fi

  warn "Stable gcloud IAP command failed. Trying beta..."

  gcloud beta run services update "$SERVICE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --no-iap \
    --quiet
}

grant_iap_invoker() {
  gcloud run services add-iam-policy-binding "$SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --member="serviceAccount:${IAP_SERVICE_AGENT}" \
    --role="roles/run.invoker" \
    --quiet >/dev/null
}

grant_iap_user() {
  gcloud iap web add-iam-policy-binding \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --resource-type=cloud-run \
    --service="$SERVICE" \
    --member="user:${ACCOUNT}" \
    --role="roles/iap.httpsResourceAccessor" \
    --quiet >/dev/null
}

get_url() {
  gcloud run services describe "$SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format='value(status.url)'
}

# ========================== BANNER ===========================

clear

echo "${MAGENTA}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║              USER AUTHENTICATION WITH IAP - LAB                  ║"
echo "║                         © ePlus.DEV                               ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo "${RESET}"

# ===================== ENVIRONMENT DETECTION =================

section "[1/8] Detecting Google Cloud environment"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
ACCOUNT="$(gcloud auth list \
  --filter=status:ACTIVE \
  --format='value(account)' 2>/dev/null | head -n1 || true)"

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
SERVICE="user-auth-lab"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  error "Unable to detect Project ID."
  exit 1
fi

if [[ -z "$ACCOUNT" ]]; then
  error "Unable to detect active Google Cloud account."
  exit 1
fi

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" \
  --format='value(projectNumber)')"

BUCKET="${PROJECT_ID}-bucket"
WORKDIR="$HOME/user-authentication-with-iap"
ZIPFILE="$HOME/user-authentication-with-iap.zip"

IAP_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcp-sa-iap.iam.gserviceaccount.com"

# Current Cloud Run direct-IAP JWT audience.
IAP_AUDIENCE="/projects/${PROJECT_NUMBER}/locations/${REGION}/services/${SERVICE}"

gcloud config set project "$PROJECT_ID" >/dev/null
gcloud config set run/region "$REGION" >/dev/null

echo "Project ID     : $PROJECT_ID"
echo "Project number : $PROJECT_NUMBER"
echo "Account        : $ACCOUNT"
echo "Region         : $REGION"
echo "Service        : $SERVICE"
echo "Source bucket  : gs://${BUCKET}"
echo "JWT audience   : $IAP_AUDIENCE"

success "Google Cloud environment detected."

# ========================= ENABLE APIS =======================

section "[2/8] Enabling required APIs"

run_progress \
  "Enabling Cloud Run, Cloud Build, Artifact Registry and IAP APIs" \
  gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    iap.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

# Attempt to force-create the IAP service identity.
gcloud beta services identity create \
  --service=iap.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet >/dev/null 2>&1 || true

# ======================== DOWNLOAD CODE ======================

section "[3/8] Downloading lab source code"

rm -f "$ZIPFILE"

retry_cmd \
  "Downloading user-authentication-with-iap.zip" \
  6 \
  5 \
  gcloud storage cp \
    "gs://${BUCKET}/user-authentication-with-iap.zip" \
    "$ZIPFILE"

rm -rf "$WORKDIR"

unzip -q -o "$ZIPFILE" -d "$HOME"

if [[ ! -d "$WORKDIR/1-HelloWorld" ]]; then
  error "1-HelloWorld source directory was not found."
  exit 1
fi

if [[ ! -d "$WORKDIR/2-HelloUser" ]]; then
  error "2-HelloUser source directory was not found."
  exit 1
fi

if [[ ! -d "$WORKDIR/3-HelloVerifiedUser" ]]; then
  error "3-HelloVerifiedUser source directory was not found."
  exit 1
fi

success "Lab source code is ready."

# ============================================================
# TASK 1
# ============================================================

section "[4/8] TASK 1 - Deploy Hello World"

cd "$WORKDIR/1-HelloWorld"

run_progress \
  "Deploying 1-HelloWorld to Cloud Run" \
  gcloud run deploy "$SERVICE" \
    --source=. \
    --allow-unauthenticated \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --quiet

SERVICE_URL="$(get_url)"

echo
echo "Cloud Run URL : ${CYAN}${SERVICE_URL}${RESET}"

success "TASK 1A - Cloud Run service deployed."

# ========================= ENABLE IAP ========================

section "[5/8] TASK 1 - Enable IAP and grant student access"

run_progress \
  "Enabling IAP on ${SERVICE}" \
  iap_enable

retry_cmd \
  "Granting Cloud Run Invoker to IAP service agent" \
  12 \
  5 \
  grant_iap_invoker

retry_cmd \
  "Granting IAP-Secured Web App User to ${ACCOUNT}" \
  12 \
  5 \
  grant_iap_user

echo
echo "IAP principal : user:${ACCOUNT}"
echo "IAP role      : roles/iap.httpsResourceAccessor"
echo "Invoker       : ${IAP_SERVICE_AGENT}"

success "TASK 1B - IAP enabled and policy added."

# ============================================================
# TASK 2
# ============================================================

section "[6/8] TASK 2 - Access user identity information"

cd "$WORKDIR/2-HelloUser"

run_progress \
  "Deploying 2-HelloUser" \
  gcloud run deploy "$SERVICE" \
    --source=. \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --quiet

SERVICE_URL="$(get_url)"

success "TASK 2 application deployed."

echo
echo "Cloud Run URL : ${CYAN}${SERVICE_URL}${RESET}"
echo "The application now reads:"
echo "  X-Goog-Authenticated-User-Email"
echo "  X-Goog-Authenticated-User-ID"

# The lab next asks to disable IAP before Task 3.

run_progress \
  "Disabling IAP for spoofing demonstration" \
  iap_disable

# Explicitly guarantee public access as required by lab Task 2.
gcloud run services add-iam-policy-binding "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --quiet >/dev/null 2>&1 || true

HTTP_CODE="$(curl -L -s \
  -o /tmp/iap-task2-test.html \
  -w '%{http_code}' \
  -H 'X-Goog-Authenticated-User-Email: totally fake email' \
  "$SERVICE_URL" || true)"

echo
echo "Public spoof test HTTP status : $HTTP_CODE"

if grep -q "totally fake email" /tmp/iap-task2-test.html 2>/dev/null; then
  success "Fake IAP header test succeeded as expected."
else
  warn "Spoof response was not visible yet; deployment may still be propagating."
fi

# ============================================================
# TASK 3
# ============================================================

section "[7/8] TASK 3 - Cryptographic verification"

cd "$WORKDIR/3-HelloVerifiedUser"

echo "Calculated IAP_AUDIENCE:"
echo "${CYAN}${IAP_AUDIENCE}${RESET}"
echo

run_progress \
  "Deploying 3-HelloVerifiedUser with IAP_AUDIENCE" \
  gcloud run deploy "$SERVICE" \
    --source=. \
    --set-env-vars="IAP_AUDIENCE=${IAP_AUDIENCE}" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --quiet

SERVICE_URL="$(get_url)"

success "Cryptographic verification application deployed."

# Turn IAP back on as required by final lab state.
run_progress \
  "Re-enabling IAP" \
  iap_enable

retry_cmd \
  "Granting Cloud Run Invoker to IAP service agent" \
  12 \
  5 \
  grant_iap_invoker

retry_cmd \
  "Verifying student IAP access policy" \
  12 \
  5 \
  grant_iap_user

# ======================= FINAL VALIDATION ====================

section "[8/8] Final validation"

SERVICE_JSON="/tmp/user-auth-lab-service.json"

gcloud run services describe "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format=json > "$SERVICE_JSON"

DEPLOYED_AUDIENCE="$(
  jq -r '
    .spec.template.spec.containers[0].env[]?
    | select(.name=="IAP_AUDIENCE")
    | .value
  ' "$SERVICE_JSON" 2>/dev/null | head -n1
)"

echo "Project             : $PROJECT_ID"
echo "Service             : $SERVICE"
echo "Region              : $REGION"
echo "URL                 : $SERVICE_URL"
echo "Student             : $ACCOUNT"
echo "IAP service agent   : $IAP_SERVICE_AGENT"
echo "Expected audience   : $IAP_AUDIENCE"
echo "Deployed audience   : ${DEPLOYED_AUDIENCE:-unknown}"

echo
echo "Cloud Run IAP status:"
gcloud run services describe "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" 2>/dev/null |
  grep -i -E 'Iap Enabled|iap-enabled' || true

echo
echo "IAP IAM policy:"
gcloud iap web get-iam-policy \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --resource-type=cloud-run \
  --service="$SERVICE" \
  --format='table(bindings.role,bindings.members)' 2>/dev/null || true

echo
line
echo "${GREEN}${BOLD}ALL LAB DEPLOYMENT STEPS COMPLETED${RESET}"
line

echo
echo "${GREEN}✓ TASK 1 - Deploy a Cloud Run service${RESET}"
echo "${GREEN}✓ TASK 1 - Enable and add policy to IAP${RESET}"
echo "${GREEN}✓ TASK 2 - Access User Identity Information${RESET}"
echo "${GREEN}✓ TASK 3 - Use Cryptographic Verification${RESET}"

echo
echo "${CYAN}${BOLD}Application URL:${RESET}"
echo "$SERVICE_URL"

echo
echo "${CYAN}${BOLD}Clear IAP login cookie if required:${RESET}"
echo "${SERVICE_URL}/_gcp_iap/clear_login_cookie"

echo
echo "${MAGENTA}${BOLD}© ePlus.DEV${RESET}"
echo