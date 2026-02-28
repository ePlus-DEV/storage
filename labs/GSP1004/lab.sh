#!/bin/bash
set -euo pipefail

# ==========================================================
#  ePlus.DEV - Vault Policies Lab (FULL SCRIPT - FIXED)
#  Fixes:
#   - No apt-key (uses /etc/apt/keyrings)
#   - Handles new token formats (hvs.* / s.*)
#   - Auto (re)start Vault dev server + writes log to ~/vault-policy-lab/vault-dev.log
#   - Safe to rerun after "out terminal" (idempotent)
#   - Creates + tests Vault policies (Task 3-7) and uploads required files to bucket
# ==========================================================

# ---------- colors ----------
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[38;5;196m'
GREEN=$'\033[38;5;46m'
YELLOW=$'\033[38;5;226m'
BLUE=$'\033[38;5;33m'
MAGENTA=$'\033[38;5;201m'
CYAN=$'\033[38;5;51m'
RESET=$'\033[0m'

banner() {
  clear || true
  echo "${BLUE}${BOLD}============================================================${RESET}"
  echo "${GREEN}${BOLD}   ePlus.DEV | Interacting with Vault Policies - GSP1004   ${RESET}"
  echo "${CYAN}${BOLD}   Copyright (c) ePlus.DEV                                   ${RESET}"
  echo "${BLUE}${BOLD}============================================================${RESET}"
  echo
}

log()  { echo "${GREEN}${BOLD}✅ $*${RESET}"; }
warn() { echo "${YELLOW}${BOLD}⚠️  $*${RESET}"; }
err()  { echo "${RED}${BOLD}❌ $*${RESET}"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }; }

# ---------- preflight ----------
banner
mkdir -p ~/.cloudshell && touch ~/.cloudshell/no-apt-get-warning || true

need_cmd curl
need_cmd sudo
need_cmd gcloud
need_cmd gsutil

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  err "Cannot detect PROJECT_ID. Authorize Cloud Shell first."
  exit 1
fi
log "PROJECT_ID = ${PROJECT_ID}"

WORKDIR="${HOME}/vault-policy-lab"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_ADDR
VAULT_LOG="${WORKDIR}/vault-dev.log"

# ==========================================================
# Task 1: Install Vault (NO apt-key; use keyring)
# ==========================================================
log "Task 1: Install Vault (keyring method)"
if command -v vault >/dev/null 2>&1; then
  log "Vault already installed: $(vault version || true)"
else
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates gnupg lsb-release

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
  sudo chmod a+r /etc/apt/keyrings/hashicorp.gpg

  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  sudo apt-get update -y
  sudo apt-get install -y vault
  log "Installed Vault: $(vault version || true)"
fi

# ==========================================================
# Task 2: Ensure Vault dev server is running (restart if needed)
# ==========================================================
log "Task 2: Ensure Vault dev server running on ${VAULT_ADDR}"
if curl -sS "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1; then
  log "Vault is UP"
else
  warn "Vault is DOWN -> (re)starting dev server"
  pkill -f "vault server -dev" >/dev/null 2>&1 || true
  rm -f "${VAULT_LOG}" || true
  nohup vault server -dev > "${VAULT_LOG}" 2>&1 &
  sleep 2
  curl -sS "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1 || { err "Vault still DOWN. Tail log:"; tail -n 80 "${VAULT_LOG}"; exit 1; }
  log "Vault is UP after restart"
fi

# Always refresh ROOT_TOKEN from log if possible
# Works for both: Root Token: s.xxx OR Root Token: hvs.xxx
ROOT_TOKEN="$(awk '/Root Token:/ {print $3; exit}' "${VAULT_LOG}" 2>/dev/null || true)"

if [[ -z "${ROOT_TOKEN}" ]]; then
  warn "ROOT_TOKEN not found in ${VAULT_LOG}."
  warn "If you started Vault in another tab, restart it using:"
  echo "  pkill -f 'vault server -dev' || true"
  echo "  nohup vault server -dev > ${VAULT_LOG} 2>&1 &"
  echo "  sleep 2"
  echo "  ROOT_TOKEN=\$(awk '/Root Token:/ {print \$3; exit}' ${VAULT_LOG})"
  echo "  vault login \"\$ROOT_TOKEN\""
  exit 1
fi

log "Logging in as root (token format supported): ${ROOT_TOKEN:0:4}****"
vault login "${ROOT_TOKEN}" >/dev/null
log "Root login OK"

# ==========================================================
# Task 3/4: userpass + demo-policy + example-user + artifacts upload
# ==========================================================
log "Task 3/4: Create demo-policy + example-user and upload artifacts"
vault auth enable userpass >/dev/null 2>&1 || true
vault write auth/userpass/users/example-user password="password!" >/dev/null || true

cat > demo-policy.hcl <<'EOF'
path "sys/mounts" { capabilities = ["read"] }
path "sys/policies/acl" { capabilities = ["read","list"] }
EOF
vault policy write demo-policy demo-policy.hcl >/dev/null || true
vault write auth/userpass/users/example-user password="password!" policies="default,demo-policy" >/dev/null || true

EXAMPLE_TOKEN="$(vault login -method=userpass username="example-user" password="password!" -format=json \
  | sed -n 's/.*"client_token":"\([^"]*\)".*/\1/p' | head -n1)"
[[ -n "${EXAMPLE_TOKEN}" ]] || { err "Failed to get example-user token"; exit 1; }

VAULT_TOKEN="${EXAMPLE_TOKEN}" vault policy list | tee policies.txt >/dev/null
VAULT_TOKEN="${EXAMPLE_TOKEN}" vault token capabilities "${EXAMPLE_TOKEN}" sys/policies/acl | tee token_capabilities.txt >/dev/null
gsutil cp policies.txt token_capabilities.txt "gs://${PROJECT_ID}/" >/dev/null
log "Uploaded: policies.txt, token_capabilities.txt"

# ==========================================================
# Task 5: policy CLI management + upload example-policy.hcl
# ==========================================================
log "Task 5: Create/update/delete example-policy + upload file"
cat > example-policy.hcl <<'EOF'
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
path "sys/auth" { capabilities = ["read"] }
EOF

vault policy write example-policy example-policy.hcl >/dev/null 2>&1 || true
vault write sys/policy/example-policy policy=@example-policy.hcl >/dev/null 2>&1 || true
gsutil cp example-policy.hcl "gs://${PROJECT_ID}/" >/dev/null
vault delete sys/policy/example-policy >/dev/null 2>&1 || true
log "Uploaded: example-policy.hcl"

# ==========================================================
# Task 6: Associate policies userpass
# ==========================================================
log "Task 6: Create firstname-lastname user with policies"
vault write auth/userpass/users/firstname-lastname \
  password="s3cr3t!" \
  policies="default,demo-policy" >/dev/null 2>&1 || true

# ==========================================================
# Task 7: Policies for secrets (admin/appdev/security) + secrets + upload policies-update.txt
# ==========================================================
log "Task 7: Create policies admin/appdev/security + create secrets + upload policies-update.txt"

# Create users mapped to policies
vault write auth/userpass/users/admin    password="admin123"    policies="admin"    >/dev/null 2>&1 || true
vault write auth/userpass/users/app-dev  password="appdev123"   policies="appdev"   >/dev/null 2>&1 || true
vault write auth/userpass/users/security password="security123" policies="security" >/dev/null 2>&1 || true

# Policies
cat > admin.hcl <<'EOF'
path "sys/health" { capabilities = ["read","sudo"] }
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "auth/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/auth/*" { capabilities = ["create","update","delete","sudo"] }
path "sys/auth" { capabilities = ["read"] }
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
EOF

cat > appdev.hcl <<'EOF'
path "secret/+/appdev/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update"] }
path "sys/mounts" { capabilities = ["read"] }
EOF

cat > security.hcl <<'EOF'
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
# Deny secret/admin for KV v2
path "secret/data/admin" { capabilities = ["deny"] }
path "secret/data/admin/*" { capabilities = ["deny"] }
path "secret/metadata/admin" { capabilities = ["deny"] }
path "secret/metadata/admin/*" { capabilities = ["deny"] }
EOF

vault policy write admin admin.hcl >/dev/null 2>&1 || true
vault policy write appdev appdev.hcl >/dev/null 2>&1 || true
vault policy write security security.hcl >/dev/null 2>&1 || true

# Create secrets
vault kv put secret/security/first username=password >/dev/null 2>&1 || true
vault kv put secret/security/second username=password >/dev/null 2>&1 || true

vault kv put secret/appdev/first username=password >/dev/null 2>&1 || true
vault kv put secret/appdev/beta-app/second username=password >/dev/null 2>&1 || true

vault kv put secret/admin/first admin=password >/dev/null 2>&1 || true
vault kv put secret/admin/supersecret/second admin=password >/dev/null 2>&1 || true

# Admin proof file + upload
ADMIN_TOKEN="$(vault login -method=userpass username="admin" password="admin123" -format=json \
  | sed -n 's/.*"client_token":"\([^"]*\)".*/\1/p' | head -n1)"
[[ -n "${ADMIN_TOKEN}" ]] || { err "Failed to get admin token"; exit 1; }

VAULT_TOKEN="${ADMIN_TOKEN}" vault policy list | tee policies-update.txt >/dev/null
gsutil cp policies-update.txt "gs://${PROJECT_ID}/" >/dev/null
log "Uploaded: policies-update.txt"

# Enable gcp auth + list auth methods (matches lab flow; safe to ignore if already enabled)
VAULT_TOKEN="${ADMIN_TOKEN}" vault auth enable gcp >/dev/null 2>&1 || true
VAULT_TOKEN="${ADMIN_TOKEN}" vault auth list >/dev/null 2>&1 || true

# ==========================================================
# Final checks
# ==========================================================
log "Final bucket listing:"
gsutil ls "gs://${PROJECT_ID}" || true

echo
echo "${MAGENTA}${BOLD}============================================================${RESET}"
echo "${GREEN}${BOLD}DONE ✅${RESET} Now go back to Qwiklabs and click 'Check my progress'."
echo "${DIM}If terminal outs again, just rerun this script: it is safe to rerun.${RESET}"
echo "${MAGENTA}${BOLD}============================================================${RESET}"
echo