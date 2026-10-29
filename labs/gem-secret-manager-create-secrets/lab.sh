#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# Google Skills: Developer Essentials: Creating Secrets with Secret Manager
# https://www.skills.google/focuses/127766
set -Eeuo pipefail

if [[ -t 1 && -z "\${NO_COLOR:-}" ]]; then
  GREEN=$'\033[1;32m'; CYAN=$'\033[1;36m'; RED=$'\033[1;31m'; RESET=$'\033[0m'
else
  GREEN=''; CYAN=''; RED=''; RESET=''
fi
log() { printf '%s\n' "\${CYAN}== $* ==\${RESET}"; }
ok() { printf '%s\n' "\${GREEN}$*\${RESET}"; }
die() { printf '%s\n' "\${RED}ERROR: $*\${RESET}" >&2; exit 1; }

printf '%s\n' 'ePlus.DEV – Starting Execution' 'Copyright (c) 2026 ePlus.DEV | Unlicense'
command -v gcloud >/dev/null 2>&1 || die 'gcloud CLI is required.'
PROJECT_ID="\${PROJECT_ID:-\${DEVSHELL_PROJECT_ID:-}}"
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Set PROJECT_ID to the assigned lab project.'
SECRET_ID='my-secret'
LAB_VALUE='super-secret-password'

log 'Task 1: Enable Secret Manager API'
gcloud services enable secretmanager.googleapis.com --project="$PROJECT_ID"

log 'Task 2: Create the lab secret if missing'
if gcloud secrets describe "$SECRET_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Reusing existing $SECRET_ID"
else
  gcloud secrets create "$SECRET_ID" --replication-policy=automatic --project="$PROJECT_ID"
fi

log 'Task 3: Add the prescribed value only when needed'
LATEST=''
if gcloud secrets versions describe latest --secret="$SECRET_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  LATEST="$(gcloud secrets versions access latest --secret="$SECRET_ID" --project="$PROJECT_ID")"
fi
if [[ "$LATEST" != "$LAB_VALUE" ]]; then
  printf %s "$LAB_VALUE" | gcloud secrets versions add "$SECRET_ID" --data-file=- --project="$PROJECT_ID" >/dev/null
  ok 'Secret version added.'
else
  ok 'Existing latest secret version already matches the lab value.'
fi

log 'Task 4: Access the secret and verify the environment value'
# The lab demonstrates printing the secret. Do not disclose credentials in
# automation logs; the equality check verifies both retrieval and assignment.
MY_SECRET="$(gcloud secrets versions access latest --secret="$SECRET_ID" --project="$PROJECT_ID")"
export MY_SECRET
[[ "$MY_SECRET" == "$LAB_VALUE" ]] || die 'Secret value does not match the lab requirement.'
ok 'Secret access and MY_SECRET environment assignment verified (value hidden).'
ok 'Tasks complete. Check progress in the authorized Google Skills lab.'
