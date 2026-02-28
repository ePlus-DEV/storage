#!/usr/bin/env bash
set -euo pipefail

# ===== Anti-out: auto run inside tmux =====
if [[ -z "${TMUX:-}" ]]; then
  tmux has-session -t tracing 2>/dev/null || tmux new-session -d -s tracing "bash $0"
  echo "Running inside tmux session: tracing"
  echo "If Cloud Shell disconnects, run: tmux attach -t tracing"
  tmux attach -t tracing
  exit 0
fi

# ============================================================
#  ePlus.DEV © 2026 - GKE Distributed Tracing Lab (gke-tracing-demo)
#  Full Automation | No manual input | Colored Output | Anti-out
# ============================================================

# ---------- COLORS ----------
BOLD=$(tput bold 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
MAGENTA=$(tput setaf 5 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)

hr(){ printf "%s%s============================================================%s\n" "$BLUE" "$BOLD" "$RESET"; }
step(){ printf "%s%s➜ %s%s\n" "$CYAN" "$BOLD" "$*" "$RESET"; }
ok(){ printf "%s%s✔ %s%s\n" "$GREEN" "$BOLD" "$*" "$RESET"; }
warn(){ printf "%s%s⚠ %s%s\n" "$YELLOW" "$BOLD" "$*" "$RESET"; }
fail(){ printf "%s%s✘ %s%s\n" "$RED" "$BOLD" "$*" "$RESET"; }

clear || true
hr
printf "%s%s      ePlus.DEV © 2026 - GKE DISTRIBUTED TRACING LAB      %s\n" "$MAGENTA" "$BOLD" "$RESET"
hr

# ---------- AUTO PROJECT / REGION / ZONE ----------
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  fail "No active project. Start lab -> Open Cloud Shell -> rerun."
  exit 1
fi

ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"

# Fallback defaults from lab
[[ -n "$ZONE" ]] || ZONE="us-central1-f"
[[ -n "$REGION" ]] || REGION="${ZONE%-*}"

gcloud config set compute/zone "$ZONE" --quiet >/dev/null
gcloud config set compute/region "$REGION" --quiet >/dev/null

ok "Project: $PROJECT_ID"
ok "Region:  $REGION"
ok "Zone:    $ZONE"

# ---------- CLONE DEMO ----------
step "Cloning tracing demo repository"
if [[ ! -d gke-tracing-demo ]]; then
  git clone https://github.com/GoogleCloudPlatform/gke-tracing-demo
else
  warn "Repo exists, reusing: gke-tracing-demo"
fi
cd gke-tracing-demo

# ---------- TERRAFORM SETUP ----------
step "Preparing Terraform"
cd terraform

# Remove provider version constraint (lab requirement)
# (Remove any line containing 'version = "..."' under required_providers)
sed -i '/version *= *".*"/d' provider.tf

step "Terraform init"
terraform init -input=false

# Generate tfvars (remove if exists to avoid lab error)
rm -f terraform.tfvars
{
  echo "project = \"${PROJECT_ID}\""
  echo "zone    = \"${ZONE}\""
} > terraform.tfvars
ok "terraform.tfvars generated"

# ---------- TERRAFORM APPLY ----------
step "Deploying infrastructure with Terraform (no prompt)"
terraform apply -auto-approve -input=false
ok "Infrastructure deployed"

cd ..

# ---------- DEPLOY APP ----------
step "Deploying tracing demo application"
kubectl apply -f tracing-demo-deployment.yaml

step "Waiting for deployment rollout"
kubectl rollout status deployment/tracing-demo --timeout=240s
ok "Application deployed"

# ---------- WAIT FOR LOAD BALANCER IP ----------
step "Waiting for Service external IP (LoadBalancer)"
IP=""
for _ in {1..60}; do
  IP="$(kubectl get svc tracing-demo -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [[ -n "$IP" ]] && break
  sleep 5
done

if [[ -z "$IP" ]]; then
  warn "EXTERNAL-IP not assigned yet. Check with: kubectl get svc tracing-demo"
else
  ok "Service IP: $IP"
fi

echo
printf "%s%s🌐 Application URL:%s http://%s\n" "$GREEN" "$BOLD" "$RESET" "${IP:-<PENDING>}"
echo

# ---------- GENERATE SAMPLE TRAFFIC ----------
if [[ -n "$IP" ]]; then
  step "Generating sample trace traffic"
  for i in {1..8}; do
    curl -fsS "http://$IP?string=ePlusTrace$i" >/dev/null || true
    sleep 1
  done
  ok "Sample traffic generated"
else
  warn "Skip traffic generation because IP is pending."
fi

# ---------- OPTIONAL: Pull Pub/Sub messages (verification) ----------
step "Optional verify: pull Pub/Sub messages (limit 5)"
gcloud pubsub subscriptions pull --auto-ack --limit 5 tracing-demo-cli || true

hr
printf "%s%s✔ LAB SETUP COMPLETE%s\n" "$GREEN" "$BOLD" "$RESET"
printf "%sNow open:%s Navigation Menu → Observability → Trace → Trace Explorer\n" "$YELLOW" "$RESET"
printf "%sTip:%s Turn on Auto Reload to see newest traces.\n" "$YELLOW" "$RESET"
hr