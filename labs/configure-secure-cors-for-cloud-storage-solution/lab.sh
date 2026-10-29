#!/usr/bin/env bash
# Configure Secure CORS for Cloud Storage (Arcade lab)
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  CYAN=$'\033[1;36m'; YELLOW=$'\033[0;33m'; RESET=$'\033[0m'
else
  CYAN=''; YELLOW=''; RESET=''
fi
printf '%s\n' "${CYAN}ePlus.DEV - Starting Execution | Secure Cloud Storage CORS${RESET}" \
  "${YELLOW}Copyright (c) 2026 ePlus.DEV | Unlicense${RESET}"

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
step() { printf '\n[TASK %s] %s\n' "$1" "$2"; }
command -v gcloud >/dev/null 2>&1 || die 'gcloud CLI is required (Google Cloud Shell).'
PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == '(unset)' ]]; then
  [[ -t 0 ]] || die 'Set PROJECT_ID to your temporary lab project.'
  read -r -p 'Lab project ID: ' PROJECT_ID
fi
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || die 'Invalid project ID.'
BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-bucket}"
[[ "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$ ]] || die 'Invalid bucket name.'
BUCKET_URI="gs://$BUCKET_NAME"

step 1 "Confirm lab bucket exists: $BUCKET_URI"
gcloud storage buckets describe "$BUCKET_URI" --project="$PROJECT_ID" >/dev/null ||
  die "Bucket missing or inaccessible: $BUCKET_URI. Do not create a replacement bucket."

step 2 'Apply only GET from http://example.com (Content-Type header)'
CORS_FILE="$(mktemp)"
trap 'rm -f "$CORS_FILE"' EXIT
cat > "$CORS_FILE" <<'JSON'
[
  {
    "origin": ["http://example.com"],
    "method": ["GET"],
    "responseHeader": ["Content-Type"],
    "maxAgeSeconds": 3600
  }
]
JSON
gcloud storage buckets update "$BUCKET_URI" --project="$PROJECT_ID" --cors-file="$CORS_FILE"

step 3 'Read back the CORS configuration'
CORS_RESULT="$(gcloud storage buckets describe "$BUCKET_URI" --project="$PROJECT_ID" --format='default(cors_config)')"
printf '%s\n' "$CORS_RESULT"
grep -Fq 'http://example.com' <<< "$CORS_RESULT" || die 'CORS origin was not returned.'
grep -Fq 'GET' <<< "$CORS_RESULT" || die 'CORS GET method was not returned.'
printf '\nConfigured CORS for %s. Click Check my progress in Google Skills.\n' "$BUCKET_URI"
