#!/usr/bin/env bash
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ ePlus.DEV – Speaking with a Webpage (GCSB Codelab)                          │
# │ One-shot setup script with interactive config (no REGION prompt)            │
# │ For educational/lab use only. No warranty of any kind.                      │
# └─────────────────────────────────────────────────────────────────────────────┘
set -euo pipefail

# ===== Colors & helpers =======================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
say()  { printf "${CYAN}➜${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$*"; }
err()  { printf "${RED}✗${NC} %s\n" "$*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || { err "Missing $1"; exit 1; }; }

prompt() {
  local label="$1" def="${2:-}" ans
  if [[ -n "$def" ]]; then
    read -r -p "$label [$def]: " ans
    echo "${ans:-$def}"
  else
    read -r -p "$label: " ans
    echo "$ans"
  fi
}

# ===== Pre-flight =============================================================
need gcloud

# Auto-detect project if possible
AUTO_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
[[ "$AUTO_PROJECT" == "(unset)" ]] && AUTO_PROJECT="${DEVSHELL_PROJECT_ID:-}"

say "Enter configuration (press Enter to accept defaults):"
PROJECT_ID="$(prompt 'PROJECT_ID' "${AUTO_PROJECT}")"
[[ -z "$PROJECT_ID" ]] && { err "PROJECT_ID is required"; exit 1; }

ZONE="$(prompt 'ZONE (e.g., us-east1-d)' 'us-east1-d')"
REGION="${ZONE%-*}"   # derive region from zone (e.g., us-east1 from us-east1-d)
VM_NAME="$(prompt 'VM_NAME' 'speaking-with-a-webpage')"
MACHINE="$(prompt 'MACHINE (machine-type)' 'e2-medium')"
FIREWALL_NAME="$(prompt 'FIREWALL_NAME' 'dev-ports')"
PORT="$(prompt 'PORT to open in firewall (sample Jetty listens on 8443)' '8443')"

say "Confirmation:"
echo "  PROJECT_ID   = $PROJECT_ID"
echo "  ZONE         = $ZONE"
echo "  REGION       = $REGION (derived from ZONE)"
echo "  VM_NAME      = $VM_NAME"
echo "  MACHINE      = $MACHINE"
echo "  FIREWALL     = $FIREWALL_NAME (tcp:$PORT)"
echo "  NOTE: The sample Jetty listens on 8443. Changing PORT requires updating Jetty config."
read -r -p "Continue? (Y/n): " go; go="${go:-Y}"
[[ ! "$go" =~ ^[Yy]$ ]] && { warn "Aborted."; exit 0; }

# ===== Enable APIs ============================================================
say "Enabling required APIs (compute, speech)…"
gcloud services enable compute.googleapis.com speech.googleapis.com --project="$PROJECT_ID" >/dev/null
ok "APIs enabled."

# Optional: validate zone
if ! gcloud compute zones describe "$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  err "ZONE '$ZONE' is invalid or not accessible for this project."
  exit 1
fi

# ===== Firewall ===============================================================
if gcloud compute firewall-rules describe "$FIREWALL_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  warn "Firewall rule $FIREWALL_NAME already exists. Skipping."
else
  say "Creating firewall rule $FIREWALL_NAME (tcp:$PORT)…"
  gcloud compute firewall-rules create "$FIREWALL_NAME" \
    --project="$PROJECT_ID" \
    --allow="tcp:$PORT" \
    --source-ranges="0.0.0.0/0" >/dev/null
  ok "Firewall rule created."
fi

# ===== Files we need (startup + helper) ======================================
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
cd speaking-with-a-webpage

# Create the interactive helper menu
cat > run-speak.sh <<'MENU'
#!/usr/bin/env bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
say() { printf "${CYAN}➜${NC} %s\n" "$*"; }
ok()  { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}!${NC} %s\n" "$*"; }
err() { printf "${RED}✗${NC} %s\n" "$*" >&2; }

external_ip() {
  curl -s -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" || true
}
print_url() {
  local ip; ip="$(external_ip)"
  if [[ -n "$ip" ]]; then
    say "Open this in your browser (self-signed cert; accept the warning):"
    printf "   https://%s:8443\n" "$ip"
  else
    warn "Cannot detect external IP. Check the VM details page."
  fi
}
ensure_prereqs() {
  java -version >/dev/null 2>&1 || { err "Java not found"; exit 1; }
  mvn -v >/dev/null 2>&1   || { err "Maven not found"; exit 1; }
}
run_step() {
  local step="$1"
  [[ -d "$step" ]] || { err "Directory $step not found"; exit 1; }
  say "Starting Jetty for ${step}… (CTRL+C to stop)"
  ( cd "$step" && mvn -q clean jetty:run )
}
menu() {
  cat <<'M'
[01] 01-hello-https   — minimal Jetty servlet over HTTPS
[02] 02-webaudio      — capture mic audio + visualization
[03] 03-websockets    — client/server websocket messaging
[04] 04-speech        — stream audio to Cloud Speech API
[q]  quit
M
}
main() {
  ensure_prereqs
  while true; do
    menu
    read -rp "Pick a step (01/02/03/04 or q): " choice
    case "$choice" in
      01|1) print_url; run_step 01-hello-https ;;
      02|2) print_url; run_step 02-webaudio ;;
      03|3) print_url; run_step 03-websockets ;;
      04|4) print_url; run_step 04-speech ;;
      q|Q)  ok "Bye!"; exit 0 ;;
      *)    warn "Unknown choice: $choice" ;;
    esac
    say "Stopped. Returning to menu…"
  done
}
main "$@"
MENU

chmod +x run-speak.sh
chown "$USER":"$USER" run-speak.sh || true
echo "$LOGTAG Provisioning completed."
EOS

# Local copy of run-speak.sh for SCP if the VM already exists
TMP_RUN="$(mktemp -t run-speak.XXXXXX.sh)"
cat > "${TMP_RUN}" <<'MENU2'
#!/usr/bin/env bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
say() { printf "${CYAN}➜${NC} %s\n" "$*"; }
ok()  { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}!${NC} %s\n" "$*"; }
err() { printf "${RED}✗${NC} %s\n" "$*" >&2; }

external_ip() {
  curl -s -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" || true
}
print_url() {
  local ip; ip="$(external_ip)"
  if [[ -n "$ip" ]]; then
    printf "   https://%s:8443\n" "$ip"
  else
    warn "Cannot detect external IP. Check the VM details page."
  fi
}
ensure_prereqs() {
  java -version >/dev/null 2>&1 || { err "Java not found"; exit 1; }
  mvn -v >/dev/null 2>&1   || { err "Maven not found"; exit 1; }
}
run_step() { local step="$1"; [[ -d "$step" ]] || { err "Dir $step not found"; exit 1; }; ( cd "$step" && mvn -q clean jetty:run ); }
menu() { cat <<'M'
[01] 01-hello-https   — minimal Jetty servlet over HTTPS
[02] 02-webaudio      — capture mic audio + visualization
[03] 03-websockets    — client/server websocket messaging
[04] 04-speech        — stream audio to Cloud Speech API
[q]  quit
M
}
main() {
  ensure_prereqs
  while true; do
    menu
    read -rp "Pick a step (01/02/03/04 or q): " choice
    case "$choice" in
      01|1) print_url; run_step 01-hello-https ;;
      02|2) print_url; run_step 02-webaudio ;;
      03|3) print_url; run_step 03-websockets ;;
      04|4) print_url; run_step 04-speech ;;
      q|Q)  ok "Bye!"; exit 0 ;;
      *)    warn "Unknown choice: $choice" ;;
    esac
  done
}
main "$@"
MENU2
chmod +x "${TMP_RUN}"

# ===== Create or reuse VM =====================================================
VM_EXISTS=0
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  VM_EXISTS=1
  warn "VM $VM_NAME already exists."
fi

if [[ $VM_EXISTS -eq 0 ]]; then
  say "Creating VM $VM_NAME (Debian 11, $MACHINE)…"
  gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE" \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --scopes=cloud-platform \
    --metadata-from-file startup-script="$TMP_STARTUP" >/dev/null
  ok "VM created."
else
  read -r -p "Re-provision helper (install Java/Maven, clone repo, copy menu) on the existing VM? (y/N): " repro
  if [[ "$repro" =~ ^[Yy]$ ]]; then
    say "Installing deps + cloning repo + copying menu to the existing VM…"
    gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command \
      "sudo apt-get update -y && sudo apt-get install -y git maven openjdk-11-jdk curl && \
       test -d ~/speaking-with-a-webpage || git clone https://github.com/googlecodelabs/speaking-with-a-webpage.git" >/dev/null
    gcloud compute scp "$TMP_RUN" "$VM_NAME:~/speaking-with-a-webpage/run-speak.sh" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null
    gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command "chmod +x ~/speaking-with-a-webpage/run-speak.sh" >/dev/null
    ok "Re-provisioned."
  else
    warn "Skipping re-provision."
  fi
fi

# ===== Wait for SSH, print URL, open menu =====================================
say "Waiting for SSH to become ready…"
for i in {1..30}; do
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command="echo up" >/dev/null 2>&1; then
    ok "SSH is ready."
    break
  fi
  sleep 5
  [[ $i -eq 30 ]] && { err "SSH not ready. Try again later."; exit 1; }
done

IP="$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"
say "External IP: $IP"
say "Open this URL (self-signed cert → Advanced → Continue):"
echo "  https://$IP:$PORT"
[[ "$PORT" != "8443" ]] && warn "The sample Jetty listens on 8443. If you change PORT, update Jetty config accordingly."

read -r -p "Launch the menu on the VM now? (Y/n): " runnow; runnow="${runnow:-Y}"
if [[ "$runnow" =~ ^[Yy]$ ]]; then
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" \
    -- -t "bash -lc '~/speaking-with-a-webpage/run-speak.sh'"
else
  ok "You can open the menu later with:"
  echo "  gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID -- -t \"bash -lc '~/speaking-with-a-webpage/run-speak.sh'\""
fi
