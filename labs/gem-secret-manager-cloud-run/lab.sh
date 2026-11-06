#!/usr/bin/env bash
# Developer Essentials: Application Development with Secret Manager
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -euo pipefail
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  CYAN=$'\033[1;36m'; YELLOW=$'\033[0;33m'; RESET=$'\033[0m'
else
  CYAN=''; YELLOW=''; RESET=''
fi
printf '%s\n' "${CYAN}ePlus.DEV - Starting Execution | Secret Manager + Cloud Run${RESET}" \
  "${YELLOW}Copyright (c) 2026 ePlus.DEV | Unlicense${RESET}"
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
step() { printf '\n[TASK %s] %s\n' "$1" "$2"; }
for cmd in gcloud mktemp curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
done
PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == '(unset)' ]]; then
  [[ -t 0 ]] || die 'Set PROJECT_ID to your temporary lab project.'
  read -r -p 'Lab project ID: ' PROJECT_ID
fi
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || die 'Invalid project ID.'
REGION="${REGION:-$(gcloud compute project-info describe --project="$PROJECT_ID" \
  --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  REGION="$(gcloud config get-value run/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  [[ -t 0 ]] || die 'Set REGION to the lab-assigned region.'
  read -r -p 'Lab region: ' REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || die 'Invalid region.'
SECRET_ID=arcade-secret
REPOSITORY=arcade-images
SERVICE=arcade-service
SA_EMAIL="arcade-service@$PROJECT_ID.iam.gserviceaccount.com"
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPOSITORY/arcade-secret:latest"

step 1 "Enable required APIs in $PROJECT_ID"
gcloud services enable secretmanager.googleapis.com run.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com --project="$PROJECT_ID"

step 2 "Create/reuse Secret Manager secret $SECRET_ID"
if gcloud secrets describe "$SECRET_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  printf 'Secret already exists.\n'
else
  gcloud secrets create "$SECRET_ID" --replication-policy=automatic --project="$PROJECT_ID"
fi
EXISTING_VERSION="$(gcloud secrets versions list "$SECRET_ID" --project="$PROJECT_ID" \
  --filter='state=ENABLED' --limit=1 --format='value(name)')"
if [[ -n "$EXISTING_VERSION" ]]; then
  printf 'Enabled secret version already exists; not rotating it on rerun.\n'
else
  if [[ -z "${LAB_SECRET_VALUE:-}" ]]; then
    [[ -t 0 ]] || die 'Set LAB_SECRET_VALUE to the lab-provided demonstration secret.'
    read -r -s -p 'Lab demonstration secret value: ' LAB_SECRET_VALUE
    printf '\n'
  fi
  [[ -n "${LAB_SECRET_VALUE:-}" ]] || die 'Secret value cannot be empty.'
  printf '%s' "$LAB_SECRET_VALUE" | gcloud secrets versions add "$SECRET_ID" \
    --data-file=- --project="$PROJECT_ID" >/dev/null
  unset LAB_SECRET_VALUE
  printf 'Created a secret version (value not printed).\n'
fi

step 3 'Create isolated Python application and build container'
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cat > "$WORKDIR/app.py" <<'PYTHON'
import logging
import os

from flask import Flask, jsonify
from google.cloud import secretmanager

app = Flask(__name__)
PROJECT_ID = os.environ["PROJECT_ID"]
SECRET_ID = os.environ.get("SECRET_ID", "arcade-secret")

@app.get("/")
def get_secret():
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{PROJECT_ID}/secrets/{SECRET_ID}/versions/latest"
        result = client.access_secret_version(request={"name": name})
        value = result.payload.data.decode("utf-8")
        response = jsonify(secret_id=SECRET_ID, secret_value=value)
        response.headers["Cache-Control"] = "no-store"
        return response
    except Exception:
        logging.exception("Secret Manager access failed")
        return jsonify(error="Unable to access configured secret"), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
PYTHON
cat > "$WORKDIR/requirements.txt" <<'REQUIREMENTS'
Flask>=3.1,<4
google-cloud-secret-manager>=2.20,<3
REQUIREMENTS
cat > "$WORKDIR/Dockerfile" <<'DOCKER'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
DOCKER
python3 -m py_compile "$WORKDIR/app.py"
if ! gcloud artifacts repositories describe "$REPOSITORY" \
  --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$REPOSITORY" --repository-format=docker \
    --location="$REGION" --description='Arcade lab container images' --project="$PROJECT_ID"
fi
gcloud builds submit "$WORKDIR" --tag="$IMAGE" --project="$PROJECT_ID"

step 4 'Create service identity and deploy authenticated Cloud Run service'
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create arcade-service --display-name='Arcade Service Account' \
    --project="$PROJECT_ID"
fi
gcloud secrets add-iam-policy-binding "$SECRET_ID" --project="$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" --role=roles/secretmanager.secretAccessor >/dev/null
gcloud run deploy "$SERVICE" --image="$IMAGE" --region="$REGION" \
  --project="$PROJECT_ID" --service-account="$SA_EMAIL" \
  --set-env-vars="PROJECT_ID=$PROJECT_ID,SECRET_ID=$SECRET_ID" \
  --set-secrets="SECRET_ENV_VAR=$SECRET_ID:latest" \
  --no-allow-unauthenticated --quiet

step 5 'Verify deployment URL and authenticated Secret Manager access'
URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT_ID" \
  --format='value(status.url)')"
[[ "$URL" == https://* ]] || die 'Cloud Run did not return a valid HTTPS URL.'
printf 'Cloud Run URL: %s (authentication required)\n' "$URL"
TOKEN="$(gcloud auth print-identity-token 2>/dev/null || true)"
[[ -n "$TOKEN" ]] || die 'Cannot obtain identity token; verify manually with a Cloud Run Invoker identity.'
if ! curl -fsS --retry 2 -H "Authorization: Bearer $TOKEN" "$URL" | \
  python3 -c 'import json,sys; r=json.load(sys.stdin); assert r.get("secret_id")=="arcade-secret" and bool(r.get("secret_value")); print("Authenticated secret retrieval verified (value hidden).")'; then
  die 'Authenticated check failed. The caller may need roles/run.invoker; no secret was printed.'
fi
printf 'Cloud Run and Secret Manager integration verified. Check my progress in Google Skills.\n'
