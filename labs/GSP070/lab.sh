#!/usr/bin/env bash
set -euo pipefail

# ============================
#  App Engine Go HelloWorld
#  © ePlus.DEV
# ============================

# Colors
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[0;92m"
YELLOW="\033[0;93m"
RED="\033[0;91m"
CYAN="\033[0;96m"

log()  { echo -e "${CYAN}${BOLD}▶${RESET} $*"; }
ok()   { echo -e "${GREEN}${BOLD}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*"; }
die()  { echo -e "${RED}${BOLD}✖${RESET} $*"; exit 1; }

# ---- Pre-checks
command -v gcloud >/dev/null 2>&1 || die "gcloud not found (are you in Cloud Shell?)"
command -v git >/dev/null 2>&1 || die "git not found"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"

log "Project: ${PROJECT_ID:-unknown}"
log "Account: ${ACTIVE_ACCOUNT:-unknown}"

# ---- Task: set region
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
log "Setting compute/region to ${REGION} ..."
gcloud config set compute/region "${REGION}" -q
ok "Region set."

# ---- Task: clone repo
REPO_DIR="golang-samples"
APP_DIR="${REPO_DIR}/appengine/go11x/helloworld"

if [[ -d "${REPO_DIR}" ]]; then
  warn "Repo ${REPO_DIR} already exists, skipping clone."
else
  log "Cloning golang-samples ..."
  git clone https://github.com/GoogleCloudPlatform/golang-samples.git
  ok "Cloned."
fi

[[ -d "${APP_DIR}" ]] || die "App dir not found: ${APP_DIR}"

log "Changing directory: ${APP_DIR}"
cd "${APP_DIR}"

# ---- Task: install App Engine Go component
# (Lab instruction uses apt-get; we keep it, but try without sudo if needed)
log "Installing google-cloud-sdk-app-engine-go ..."
if command -v sudo >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y google-cloud-sdk-app-engine-go
else
  apt-get update -y
  apt-get install -y google-cloud-sdk-app-engine-go
fi
ok "Installed component."

# ---- Task: deploy (auto answer region prompt + continue prompt)
# App Engine region selection prompt usually expects a number. We auto-pick "europe-west" if present.
warn "Deploy will create App Engine application if not created yet."
log "Deploying (auto-select europe-west if prompted) ..."

# Feed:
# 1) If gcloud asks region number -> we parse list in output and pick europe-west if visible
# 2) Continue prompt -> Y
TMP_OUT="$(mktemp)"

# Run deploy once, capture prompts
set +e
gcloud app deploy --quiet 2>&1 | tee "${TMP_OUT}"
RC=${PIPESTATUS[0]}
set -e

if [[ $RC -ne 0 ]]; then
  # If failure likely due to region selection prompt not handled by --quiet,
  # rerun interactively by piping chosen selection and 'Y'
  warn "First deploy attempt did not complete. Trying interactive auto-select..."

  # Try to find europe-west in prompt list and get its number.
  # If not found, default to '9'?? (avoid guessing wildly) -> fallback to manual input.
  EURO_NUM="$(grep -n -E 'europe-west' "${TMP_OUT}" | head -n 1 | awk -F: '{print $1}' || true)"

  if [[ -z "${EURO_NUM}" ]]; then
    warn "Could not auto-detect region selection number from output."
    warn "Running deploy normally now. If prompted, choose europe-west and type Y."
    gcloud app deploy
  else
    # This is a best-effort: many gcloud prompts print a numbered list like "1. us-central"
    # Grep number from the same line if present
    EURO_SEL="$(grep -E 'europe-west' "${TMP_OUT}" | head -n 1 | sed -n 's/^[[:space:]]*\([0-9]\+\).*/\1/p' || true)"

    if [[ -z "${EURO_SEL}" ]]; then
      warn "Could not parse region number; running deploy normally."
      gcloud app deploy
    else
      printf "%s\nY\n" "${EURO_SEL}" | gcloud app deploy
    fi
  fi
else
  ok "Deployed."
fi

# ---- Task: browse
log "Opening app in browser (prints URL) ..."
gcloud app browse
ok "Done. --- ePlus.DEV"