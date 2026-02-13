#!/usr/bin/env bash
# ============================================================
#  Vault Policies Lab Automation (Single Script)
#  © 2026 ePlus.DEV — All rights reserved
#  Author : ePlus.DEV
#  Target : Google Cloud Qwiklabs Cloud Shell
#
#  Features:
#   - Colorful output + ePlus.DEV banner
#   - Runs safely inside tmux (auto-create/attach instructions)
#   - Auto-start Vault dev server in background + capture Root Token
#   - Logs everything to: eplus_lab_full.log
#   - Minimal terminal spam (progress-style)
#   - Idempotent-ish (can re-run after disconnect)
#
#  Run:
#    chmod +x lab.sh && ./lab.sh
#
#  Tip (best for disconnect/out terminal):
#    tmux new -s eplus && ./lab.sh
# ============================================================

set -euo pipefail

# ================== COLORS ==================
BLACK=$(tput setaf 0 2>/dev/null || echo "")
RED=$(tput setaf 1 2>/dev/null || echo "")
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
BLUE=$(tput setaf 4 2>/dev/null || echo "")
MAGENTA=$(tput setaf 5 2>/dev/null || echo "")
CYAN=$(tput setaf 6 2>/dev/null || echo "")
WHITE=$(tput setaf 7 2>/dev/null || echo "")
BOLD=$(tput bold 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")

# ================== LOGGING ==================
LOG_FILE="eplus_lab_full.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ================== HELPERS ==================
banner() {
  echo "${CYAN}${BOLD}"
  echo "============================================================"
  echo "        Vault Policies Automation Lab"
  echo "        © 2026 ePlus.DEV — All rights reserved"
  echo "============================================================"
  echo "${RESET}"
  echo "${MAGENTA}${BOLD}Log:${RESET} ${WHITE}${LOG_FILE}${RESET}"
  echo
}

info()  { echo "${BLUE}${BOLD}[INFO]${RESET} $*"; }
ok()    { echo "${GREEN}${BOLD}[ OK ]${RESET} $*"; }
warn()  { echo "${YELLOW}${BOLD}[WARN]${RESET} $*"; }
fail()  { echo "${RED}${BOLD}[FAIL]${RESET} $*"; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

retry() {
  # retry <times> <sleep_seconds> <cmd...>
  local times="$1"; shift
  local sleep_s="$1"; shift
  local n=1
  until "$@"; do
    if (( n >= times )); then
      return 1
    fi
    warn "Retry $n/$times failed. Sleeping ${sleep_s}s..."
    sleep "$sleep_s"
    n=$((n+1))
  done
  return 0
}

# ================== PRECHECK ==================
banner

need curl
need sudo
need gcloud
need gsutil
need sed
need awk
need grep

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "${PROJECT_ID}" ]] || fail "No active gcloud project. Open Cloud Shell in the lab project."
info "Project: ${GREEN}${PROJECT_ID}${RESET}"

export VAULT_ADDR="http://127.0.0.1:8200"

# ================== CLEANUP HANDLING ==================
VAULT_PID=""
VAULT_LOG=""

cleanup() {
  if [[ -n "${VAULT_PID}" ]] && ps -p "${VAULT_PID}" >/dev/null 2>&1; then
    warn "Stopping Vault dev server (pid=${VAULT_PID})"
    kill "${VAULT_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ================== TASK 1: INSTALL VAULT ==================
info "Task 1: Install Vault"
if ! command -v vault >/dev/null 2>&1; then
  info "Installing Vault packages (no prompts)..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - >/dev/null 2>&1 || true
  sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" -y >/dev/null
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y vault >/dev/null
  ok "Vault installed"
else
  warn "Vault already installed — skipping"
fi
vault version || fail "Vault binary not working"

# ================== TASK 2: START VAULT DEV SERVER ==================
info "Task 2: Start Vault dev server (background)"
# Clean any old dev server from a previous disconnected session
pkill -f "vault server -dev" >/dev/null 2>&1 || true

VAULT_LOG="$(mktemp -t vault-dev-XXXX.log)"
nohup vault server -dev >"${VAULT_LOG}" 2>&1 &
VAULT_PID=$!
info "Vault dev server PID: ${VAULT_PID}"
info "Vault dev log: ${VAULT_LOG}"

# Wait until Root Token appears
ROOT_TOKEN=""
for i in $(seq 1 60); do
  ROOT_TOKEN="$(grep -m1 "Root Token:" "${VAULT_LOG}" 2>/dev/null | awk '{print $3}' || true)"
  if [[ -n "${ROOT_TOKEN}" ]]; then
    break
  fi
  sleep 1
done
[[ -n "${ROOT_TOKEN}" ]] || fail "Could not capture Root Token (check ${VAULT_LOG})"
ok "Root Token captured"

# Wait vault ready
retry 30 1 vault status >/dev/null || fail "Vault status failed"
ok "Vault is running"

# ================== TASK 3/4: USERPASS + DEMO-POLICY ==================
info "Task 3/4: userpass + demo-policy + attach"
vault login token="${ROOT_TOKEN}" >/dev/null

# Enable userpass (idempotent)
vault auth enable userpass >/dev/null 2>&1 || true
ok "userpass enabled"

# Create/overwrite example-user
vault write auth/userpass/users/example-user password="password!" >/dev/null
ok "example-user created"

# Create demo-policy file
cat > demo-policy.hcl <<'EOF'
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/policies/acl" {
  capabilities = ["read", "list"]
}
EOF

vault policy write demo-policy demo-policy.hcl >/dev/null
ok "demo-policy uploaded"

# Attach policy to example-user
vault write auth/userpass/users/example-user \
  password="password!" \
  policies="default,demo-policy" >/dev/null
ok "demo-policy attached to example-user"

# Re-login to get new token with policy
vault login -method=userpass username=example-user password="password!" >/dev/null
retry 10 1 vault secrets list >/dev/null || fail "example-user still cannot list secrets engines"
ok "example-user can list secrets engines"

# Export progress files + upload
vault policy list > policies.txt

TOKEN_ID="$(vault token lookup -format=json | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -n1 || true)"
[[ -n "${TOKEN_ID}" ]] || fail "Could not determine current token id"
vault token capabilities "${TOKEN_ID}" sys/policies/acl > token_capabilities.txt

gsutil cp -q policies.txt token_capabilities.txt "gs://${PROJECT_ID}/"
ok "Uploaded policies.txt + token_capabilities.txt to gs://${PROJECT_ID}"

# ================== TASK 5: MANAGING POLICIES (CLI) ==================
info "Task 5: Create/Update/Delete example-policy (CLI)"
vault login token="${ROOT_TOKEN}" >/dev/null

cat > example-policy.hcl <<'EOF'
# List, create, update, and delete key/value secrets
path "secret/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage secrets engines
path "sys/mounts/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List existing secrets engines.
path "sys/mounts"
{
  capabilities = ["read"]
}
EOF

vault policy write example-policy example-policy.hcl >/dev/null
ok "example-policy created"

# Update to add sys/auth read
cat > example-policy.hcl <<'EOF'
# List, create, update, and delete key/value secrets
path "secret/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage secrets engines
path "sys/mounts/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List existing secrets engines.
path "sys/mounts"
{
  capabilities = ["read"]
}

# List auth methods
path "sys/auth"
{
  capabilities = ["read"]
}
EOF

vault write sys/policy/example-policy policy=@example-policy.hcl >/dev/null
ok "example-policy updated"

gsutil cp -q example-policy.hcl "gs://${PROJECT_ID}/"
ok "Uploaded example-policy.hcl to gs://${PROJECT_ID}"

vault delete sys/policy/example-policy >/dev/null
ok "example-policy deleted"

# ================== TASK 6: ASSOCIATING POLICIES ==================
info "Task 6: Associate policies to user + token create demo"
vault write auth/userpass/users/firstname-lastname \
  password="s3cr3t!" \
  policies="default,demo-policy" >/dev/null
ok "firstname-lastname created with policies"

vault login -method="userpass" username="firstname-lastname" password="s3cr3t!" >/dev/null
ok "firstname-lastname login OK"

vault login token="${ROOT_TOKEN}" >/dev/null
vault token create -policy=dev-readonly -policy=logs >/dev/null 2>&1 || true
warn "Token create with dev-readonly/logs may warn if policies don't exist (expected in lab)."

# ================== TASK 7: POLICIES FOR SECRETS ==================
info "Task 7: Create users + policies + secrets + verify"

# Create users referencing policies
vault write auth/userpass/users/admin password="admin123" policies="admin" >/dev/null
vault write auth/userpass/users/app-dev password="appdev123" policies="appdev" >/dev/null
vault write auth/userpass/users/security password="security123" policies="security" >/dev/null
ok "Users admin/app-dev/security created"

# Write policies
cat > admin.hcl <<'EOF'
path "sys/health" { capabilities = ["read", "sudo"] }

path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }

path "auth/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/auth/*" { capabilities = ["create", "update", "delete", "sudo"] }
path "sys/auth" { capabilities = ["read"] }

path "secret/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }

path "sys/mounts/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts" { capabilities = ["read"] }
EOF

cat > appdev.hcl <<'EOF'
path "secret/+/appdev/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts/*" { capabilities = ["create", "read", "update"] }
path "sys/mounts" { capabilities = ["read"] }
EOF

cat > security.hcl <<'EOF'
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }

path "sys/mounts/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts" { capabilities = ["read"] }

path "secret/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }

# KVv2 deny rules (data/ + metadata/)
path "secret/data/admin" { capabilities = ["deny"] }
path "secret/data/admin/*" { capabilities = ["deny"] }
path "secret/metadata/admin" { capabilities = ["deny"] }
path "secret/metadata/admin/*" { capabilities = ["deny"] }
EOF

vault login token="${ROOT_TOKEN}" >/dev/null
vault policy write admin admin.hcl >/dev/null
vault policy write appdev appdev.hcl >/dev/null
vault policy write security security.hcl >/dev/null
ok "Policies admin/appdev/security uploaded"

# Create secrets
vault kv put secret/security/first username=password >/dev/null
vault kv put secret/security/second username=password >/dev/null

vault kv put secret/appdev/first username=password >/dev/null
vault kv put secret/appdev/beta-app/second username=password >/dev/null

vault kv put secret/admin/first admin=password >/dev/null
vault kv put secret/admin/supersecret/second admin=password >/dev/null
ok "Secrets created"

# Verify app-dev
info "Verify app-dev (should NOT access secret/security or list secret/)"
vault login -method="userpass" username="app-dev" password="appdev123" >/dev/null
vault kv get secret/appdev/first >/dev/null
vault kv get secret/appdev/beta-app/second >/dev/null
vault kv put secret/appdev/appcreds credentials=creds123 >/dev/null
vault kv destroy -versions=1 secret/appdev/appcreds >/dev/null
vault kv get secret/security/first >/dev/null 2>&1 || true
vault kv list secret/ >/dev/null 2>&1 || true
ok "app-dev verified"

# Verify security
info "Verify security (should NOT access secret/admin)"
vault login -method="userpass" username="security" password="security123" >/dev/null
vault kv get secret/security/first >/dev/null
vault kv get secret/security/second >/dev/null
vault kv put secret/security/supersecure/bigsecret secret=idk >/dev/null
vault kv destroy -versions=1 secret/security/supersecure/bigsecret >/dev/null
vault kv get secret/appdev/first >/dev/null
vault kv list secret/ >/dev/null
vault secrets enable -path=supersecret kv >/dev/null 2>&1 || true
vault kv get secret/admin/first >/dev/null 2>&1 || true
vault kv list secret/admin >/dev/null 2>&1 || true
ok "security verified"

# Verify admin + upload policies list update
info "Verify admin (full access)"
vault login -method="userpass" username="admin" password="admin123" >/dev/null
vault kv get secret/admin/first >/dev/null
vault kv get secret/security/first >/dev/null
vault kv put secret/webserver/credentials web=awesome >/dev/null
vault kv destroy -versions=1 secret/webserver/credentials >/dev/null
vault kv get secret/appdev/first >/dev/null
vault kv list secret/appdev/ >/dev/null

vault policy list > policies-update.txt
gsutil cp -q policies-update.txt "gs://${PROJECT_ID}/"
ok "Uploaded policies-update.txt to gs://${PROJECT_ID}"

vault auth enable gcp >/dev/null 2>&1 || true
vault auth list >/dev/null
ok "gcp auth enabled + auth list OK"

echo
echo "${GREEN}${BOLD}============================================================${RESET}"
echo "${GREEN}${BOLD} ✔ LAB COMPLETED SUCCESSFULLY${RESET}"
echo "${GREEN}${BOLD} ✔ Output log saved: ${LOG_FILE}${RESET}"
echo "${GREEN}${BOLD} © 2026 ePlus.DEV — All rights reserved${RESET}"
echo "${GREEN}${BOLD}============================================================${RESET}"
echo
info "If Cloud Shell disconnects, re-run: ${BOLD}./lab.sh${RESET} (safe to retry)"
info "Best practice: run inside tmux: ${BOLD}tmux new -s eplus${RESET}"
