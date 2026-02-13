#!/usr/bin/env bash
# ============================================================
#  Vault Policy Lab Automation
#  © 2026 ePlus.DEV — All rights reserved
#  Author : ePlus.DEV
#  Usage  : bash lab.sh
#  Note   : For Google Cloud Qwiklabs (Cloud Shell)
# ============================================================

set -euo pipefail

# ================== COLORS ==================
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)

# ================== BANNER ==================
clear
echo "${CYAN}${BOLD}"
echo "============================================================"
echo "        Vault Policies Automation Lab"
echo "        © 2026 ePlus.DEV — All rights reserved"
echo "============================================================"
echo "${RESET}"

log() {
  echo "${BLUE}${BOLD}[INFO]${RESET} $1"
}

warn() {
  echo "${YELLOW}${BOLD}[WARN]${RESET} $1"
}

error() {
  echo "${RED}${BOLD}[ERROR]${RESET} $1"
  exit 1
}

# ================== PRECHECK ==================
command -v gcloud >/dev/null || error "gcloud not found"
command -v gsutil >/dev/null || error "gsutil not found"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
[[ -z "$PROJECT_ID" ]] && error "No GCP project set"

log "Project detected: ${GREEN}${PROJECT_ID}${RESET}"

# ================== TASK 1: INSTALL VAULT ==================
log "Installing Vault"

if ! command -v vault >/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - >/dev/null
  sudo apt-add-repository \
    "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" -y >/dev/null
  sudo apt-get update -y >/dev/null
  sudo apt-get install vault -y >/dev/null
else
  warn "Vault already installed — skipping"
fi

vault version

# ================== TASK 2: START DEV SERVER ==================
log "Starting Vault dev server"

export VAULT_ADDR="http://127.0.0.1:8200"
VAULT_LOG=$(mktemp /tmp/vault-dev.log.XXXX)
nohup vault server -dev > "$VAULT_LOG" 2>&1 &
VAULT_PID=$!

sleep 3

ROOT_TOKEN=$(grep -m1 "Root Token:" "$VAULT_LOG" | awk '{print $3}')
[[ -z "$ROOT_TOKEN" ]] && error "Failed to obtain Root Token"

log "Vault dev server running (PID=$VAULT_PID)"
log "Root Token captured"

vault status >/dev/null

# ================== TASK 3–4: POLICIES ==================
log "Configuring demo-policy"

vault login token="$ROOT_TOKEN" >/dev/null
vault auth enable userpass >/dev/null 2>&1 || true

vault write auth/userpass/users/example-user \
  password="password!" >/dev/null

cat > demo-policy.hcl <<EOF
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/policies/acl" {
  capabilities = ["read", "list"]
}
EOF

vault policy write demo-policy demo-policy.hcl >/dev/null

vault write auth/userpass/users/example-user \
  password="password!" \
  policies="default,demo-policy" >/dev/null

vault login -method=userpass username=example-user password=password! >/dev/null
vault secrets list >/dev/null

vault policy list > policies.txt

TOKEN_ID=$(vault token lookup -format=json | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -n1)
vault token capabilities "$TOKEN_ID" sys/policies/acl > token_capabilities.txt

gsutil cp policies.txt token_capabilities.txt gs://$PROJECT_ID >/dev/null

log "demo-policy validated and uploaded"

# ================== TASK 5: CLI POLICY ==================
log "Managing policies via CLI"

cat > example-policy.hcl <<EOF
path "secret/*" {
  capabilities = ["create","read","update","delete","list","sudo"]
}

path "sys/mounts/*" {
  capabilities = ["create","read","update","delete","list","sudo"]
}

path "sys/mounts" {
  capabilities = ["read"]
}
EOF

vault policy write example-policy example-policy.hcl >/dev/null
vault delete sys/policy/example-policy >/dev/null

# ================== TASK 6: ASSOCIATE ==================
log "Associating policies to users"

vault write auth/userpass/users/firstname-lastname \
  password="s3cr3t!" \
  policies="default,demo-policy" >/dev/null

vault login -method=userpass username=firstname-lastname password=s3cr3t! >/dev/null

# ================== TASK 7: FINAL POLICIES ==================
log "Creating admin / appdev / security users"

vault write auth/userpass/users/admin password=admin123 policies=admin >/dev/null
vault write auth/userpass/users/app-dev password=appdev123 policies=appdev >/dev/null
vault write auth/userpass/users/security password=security123 policies=security >/dev/null

vault kv put secret/security/first username=password >/dev/null
vault kv put secret/appdev/first username=password >/dev/null
vault kv put secret/admin/first admin=password >/dev/null

vault policy list > policies-update.txt
gsutil cp policies-update.txt gs://$PROJECT_ID >/dev/null

vault auth enable gcp >/dev/null 2>&1 || true
vault auth list >/dev/null

# ================== DONE ==================
echo
echo "${GREEN}${BOLD}============================================================${RESET}"
echo "${GREEN}${BOLD} ✔ LAB COMPLETED SUCCESSFULLY${RESET}"
echo "${GREEN}${BOLD} ✔ Vault Policies configured${RESET}"
echo "${GREEN}${BOLD} ✔ Files uploaded to Cloud Storage${RESET}"
echo "${GREEN}${BOLD} © 2026 ePlus.DEV — All rights reserved${RESET}"
echo "${GREEN}${BOLD}============================================================${RESET}"
