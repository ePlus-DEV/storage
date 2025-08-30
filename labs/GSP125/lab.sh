#!/usr/bin/env bash
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ ePlus.DEV – Speaking with a Webpage (GCSB Codelab)                          │
# │ One-shot setup script: VM ➜ deps ➜ repo ➜ helper menu                      │
# │ For educational/lab use only. No warranty of any kind.                      │
# └─────────────────────────────────────────────────────────────────────────────┘

set -euo pipefail

# ====== Config (edit if you want) =============================================
VM_NAME="${VM_NAME:-speaking-with-a-webpage}"
REGION="${REGION:-us-east1}"
ZONE="${ZONE:-us-east1-d}"
MACHINE="${MACHINE:-e2-medium}"
FIREWALL_NAME="${FIREWALL_NAME:-dev-ports}"
PORT="${PORT:-8443}"
# ==============================================================================

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
say()  { printf "${CYAN}➜${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$*"; }
err()  { printf "${RED}✗${NC} %s\n" "$*" >&2; }

need() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing $1. Please install/activate Cloud Shell."; exit 1; }
}

need gcloud
need awk

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  # fallback to Cloud Shell’s env if available
  PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi
[[ -n "${PROJECT_ID}" ]] || { err "No PROJECT_ID detected. Run: gcloud config set project <YOUR_PROJECT_ID>"; exit 1; }

say "Project: ${PROJECT_ID}"
ok  "Region/Zone: ${REGION}/${ZONE}"

say "Enabling required APIs…"
gcloud services enable compute.googleapis.com speech.googleapis.com --project="${PROJECT_ID}" >/dev/null
ok "APIs enabled (compute, speech)."

# Create firewall rule for tcp:${PORT} if missing
if gcloud compute firewall-rules describe "${FIREWALL_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  warn "Firewall rule ${FIREWALL_NAME} already exists. Skipping."
else
  say "Creating firewall rule ${FIREWALL_NAME} (tcp:${PORT})…"
  gcloud compute firewall-rules create "${FIREWALL_NAME}" \
    --project="${PROJECT_ID}" \
    --allow="tcp:${PORT}" \
    --source-ranges="0.0.0.0/0" >/dev/null
  ok "Firewall rule created."
fi

# Create a startup script to provision the VM on first boot
TMP_STARTUP="$(mktemp -t startup.gce.XXXXXX.sh)"
cat > "${TMP_STARTUP}" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

LOGTAG="[startup]"

echo "$LOGTAG Begin provisioning…"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git maven openjdk-11-jdk curl

# Clone repo if missing
cd /home/$USER || cd ~
if [[ ! -d speaking-with-a-webpage ]]; then
  git clone https://github.com/googlecodelabs/speaking-with-a-webpage.git
fi
