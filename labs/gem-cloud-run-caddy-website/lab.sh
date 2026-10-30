#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# Deploy a static site with Caddy V2 on Google Cloud Run
# https://eplus.dev/deploy-a-static-site-with-caddy-v2-on-google-cloud-run-gem-cloud-run-caddy-website
set -Eeuo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; RED=$'\033[1;31m'; RESET=$'\033[0m'
else
  CYAN=''; GREEN=''; RED=''; RESET=''
fi
log() { printf '%s\n' "${CYAN}== $* ==${RESET}"; }
ok() { printf '%s\n' "${GREEN}$*${RESET}"; }
die() { printf '%s\n' "${RED}ERROR: $*${RESET}" >&2; exit 1; }

printf '%s\n' 'ePlus.DEV – Starting Execution' 'Copyright (c) 2026 ePlus.DEV | Unlicense'
command -v gcloud >/dev/null 2>&1 || die 'gcloud CLI is required.'
PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-}}"
[[ -n "$PROJECT_ID" ]] || PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Select or export the lab PROJECT_ID.'

REGION="${REGION:-}"
if [[ -z "$REGION" ]]; then
  REGION="$(gcloud compute project-info describe --project="$PROJECT_ID" \
    --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  ZONE="${ZONE:-$(gcloud compute project-info describe --project="$PROJECT_ID" \
    --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)}"
  if [[ "$ZONE" =~ ^[a-z]+(-[a-z]+)+[0-9]+-[a-z]$ ]]; then
    REGION="${ZONE%-*}"
  fi
fi
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  if [[ -t 0 ]]; then
    read -r -p 'Enter lab region: ' REGION
  else
    die 'Set REGION from the authorized lab instructions.'
  fi
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || die "Invalid region: $REGION"

REPO_NAME='caddy-repo'
IMAGE_NAME='caddy-static'
IMAGE_URL="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest"
log "Task 1: Enable APIs for $PROJECT_ID in $REGION"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com \
  --project="$PROJECT_ID"

log 'Task 2: Create or reuse Artifact Registry repository'
if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Reusing $REPO_NAME"
else
  gcloud artifacts repositories create "$REPO_NAME" --repository-format=docker \
    --location="$REGION" --description='Docker repository for Caddy images' \
    --project="$PROJECT_ID"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT
log 'Task 3: Create static website and Caddyfile in isolated workspace'
cat > "$WORK_DIR/index.html" <<'HTML'
<html>
<head><title>My Static Website</title></head>
<body>
  <div>Hello from Caddy on Cloud Run!</div>
  <p>This website is served by Caddy running in a Docker container on Google Cloud Run.</p>
</body>
</html>
HTML
cat > "$WORK_DIR/Caddyfile" <<'CADDY'
:8080
root * /usr/share/caddy
file_server
CADDY

log 'Task 4: Define the Caddy container image'
cat > "$WORK_DIR/Dockerfile" <<'DOCKER'
FROM caddy:2-alpine
WORKDIR /usr/share/caddy
COPY index.html .
COPY Caddyfile /etc/caddy/Caddyfile
DOCKER

log 'Task 5: Build and push the image using Cloud Build'
# Cloud Build performs the Docker build/push without altering the user's
# Docker credentials or requiring a local Docker daemon.
gcloud builds submit "$WORK_DIR" --tag="$IMAGE_URL" --project="$PROJECT_ID"

log 'Task 6: Deploy the public static site to Cloud Run'
gcloud run deploy "$IMAGE_NAME" --image="$IMAGE_URL" --platform=managed \
  --region="$REGION" --project="$PROJECT_ID" --allow-unauthenticated --quiet

log 'Task 7: Verify the deployed website'
SERVICE_URL="$(gcloud run services describe "$IMAGE_NAME" --region="$REGION" \
  --project="$PROJECT_ID" --format='value(status.url)')"
[[ "$SERVICE_URL" == https://* ]] || die 'Cloud Run service URL is missing.'
curl --fail --silent --show-error --location --retry 5 --retry-delay 3 "$SERVICE_URL" \
  | grep -q 'Hello from Caddy on Cloud Run!' || die 'Deployed site content did not match.'
ok "Caddy website verified: $SERVICE_URL"
ok 'Lab tasks completed. Google Skills grader not checked.'
