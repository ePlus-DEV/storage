#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  ePlus.DEV © 2026 - GKE DISTRIBUTED TRACING (gke-tracing-demo)
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
printf "%s%s ePlus.DEV © 2026 - How to Use a Network Policy on Google Kubernetes Engine %s\n" "$MAGENTA" "$BOLD" "$RESET"
hr

# ---------- AUTO PROJECT / REGION / ZONE ----------
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  fail "No active project. Start lab -> Open Cloud Shell -> run again."
  exit 1
fi

ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
[[ -n "$ZONE" ]] || ZONE="us-central1-f"
[[ -n "$REGION" ]] || REGION="${ZONE%-*}"

gcloud config set compute/zone "$ZONE" --quiet >/dev/null
gcloud config set compute/region "$REGION" --quiet >/dev/null

ok "Project: $PROJECT_ID"
ok "Region:  $REGION"
ok "Zone:    $ZONE"

# ---------- CLONE REPO ----------
step "Clone repo (if missing)"
cd ~
if [[ ! -d gke-tracing-demo ]]; then
  git clone https://github.com/GoogleCloudPlatform/gke-tracing-demo
else
  warn "Repo exists, reusing: ~/gke-tracing-demo"
fi
cd ~/gke-tracing-demo

# ---------- TERRAFORM (NO PROMPT + ANTI-OUT) ----------
step "Terraform prep/apply (nohup -> terraform/tf.log)"
cd terraform

# Lab wants provider version removed
sed -i '/version *= *".*"/d' provider.tf || true

# tfvars (regenerate to avoid prompt / avoid 'already exists' issues)
rm -f terraform.tfvars
printf "project = \"%s\"\nzone    = \"%s\"\n" "$PROJECT_ID" "$ZONE" > terraform.tfvars

terraform init -input=false >/dev/null

# Start terraform apply in background (survives disconnect)
# If already running, do not start another.
if pgrep -f "terraform apply" >/dev/null 2>&1; then
  warn "terraform apply is already running. Watching existing log..."
else
  rm -f tf.log
  nohup terraform apply -auto-approve -input=false > tf.log 2>&1 &
  disown || true
  ok "Started terraform apply (background). Log: $(pwd)/tf.log"
fi

# Wait until Apply complete appears (poll log)
step "Waiting terraform apply to complete (polling tf.log)"
until grep -q "Apply complete" tf.log 2>/dev/null; do
  if grep -qE "^Error:|ERROR" tf.log 2>/dev/null; then
    fail "Terraform error. Open log: ~/gke-tracing-demo/terraform/tf.log"
    tail -n 80 tf.log || true
    exit 1
  fi
  sleep 10
done
ok "Terraform apply completed"

# Read cluster name from output (fallback)
CLUSTER_NAME="$(terraform output -raw cluster_name 2>/dev/null || echo tracing-demo-space)"
ok "Cluster: $CLUSTER_NAME"

# ---------- GET CREDENTIALS (ANTI-OUT) ----------
step "Get GKE credentials (nohup -> creds.log)"
rm -f creds.log
nohup gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" > creds.log 2>&1 &
disown || true

# wait kubeconfig generated
until grep -qi "kubeconfig entry generated\|configured" creds.log 2>/dev/null; do
  if grep -qi "ERROR\|Error" creds.log 2>/dev/null; then
    fail "get-credentials error. Log: ~/gke-tracing-demo/terraform/creds.log"
    tail -n 80 creds.log || true
    exit 1
  fi
  sleep 5
done
ok "kubeconfig configured"

cd ~/gke-tracing-demo

# ---------- FIND THE RIGHT YAML (NO HARDCODE) ----------
step "Find tracing deployment yaml automatically"

# Priority 1: yaml that defines Service named tracing-demo
YAML_FILE="$(grep -RIl --include='*.yaml' -E 'kind:\s*Service' . | while read -r f; do
  if grep -qE 'name:\s*tracing-demo(\s|$)' "$f" && grep -qE 'kind:\s*Deployment|kind:\s*Service' "$f"; then
    echo "$f"
    break
  fi
done || true)"

# Priority 2: any yaml containing tracing-demo and kind: Deployment
if [[ -z "${YAML_FILE}" ]]; then
  YAML_FILE="$(grep -RIl --include='*.yaml' -E 'tracing-demo' . | while read -r f; do
    if grep -qE 'kind:\s*Deployment' "$f"; then
      echo "$f"
      break
    fi
  done || true)"
fi

# Priority 3: common locations/name patterns
if [[ -z "${YAML_FILE}" ]]; then
  for f in \
    ./tracing-demo-deployment.yaml \
    ./kubernetes/tracing-demo-deployment.yaml \
    ./manifests/tracing-demo-deployment.yaml \
    ./deploy/tracing-demo-deployment.yaml \
    ./tracing-demo.yaml \
    ./kubernetes/tracing-demo.yaml \
    ./manifests/tracing-demo.yaml; do
    if [[ -f "$f" ]]; then YAML_FILE="$f"; break; fi
  done
fi

if [[ -z "${YAML_FILE}" || ! -f "${YAML_FILE}" ]]; then
  fail "Cannot find tracing demo yaml automatically."
  echo "Run this to see candidates:"
  echo "  cd ~/gke-tracing-demo && find . -maxdepth 3 -type f -name '*.yaml' | sort"
  exit 1
fi

ok "Using YAML: ${YAML_FILE}"

# ---------- DEPLOY APP (ANTI-OUT) ----------
step "Deploy tracing demo app (nohup -> deploy.log)"
rm -f deploy.log
nohup kubectl apply -f "${YAML_FILE}" > deploy.log 2>&1 &
disown || true

# Wait until service exists (any svc containing tracing-demo)
step "Waiting Service to appear"
for _ in {1..60}; do
  if kubectl get svc -n default 2>/dev/null | grep -q "tracing-demo"; then
    break
  fi
  sleep 5
done

# Show what got created
ok "Services:"
kubectl get svc -n default || true
ok "Pods:"
kubectl get pods -n default || true

# Determine service name (prefer exact tracing-demo)
SVC_NAME="$(kubectl get svc -n default -o name 2>/dev/null | sed 's|service/||' | grep -E '^tracing-demo$' || true)"
if [[ -z "$SVC_NAME" ]]; then
  SVC_NAME="$(kubectl get svc -n default -o name 2>/dev/null | sed 's|service/||' | grep 'tracing-demo' | head -n1 || true)"
fi

if [[ -z "$SVC_NAME" ]]; then
  fail "No tracing-demo service found yet. Check deploy.log and run: kubectl get svc -n default"
  tail -n 120 deploy.log || true
  exit 1
fi

ok "Service detected: $SVC_NAME"

# Wait for external IP
step "Waiting for LoadBalancer EXTERNAL-IP"
IP=""
for _ in {1..80}; do
  IP="$(kubectl get svc "$SVC_NAME" -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [[ -n "$IP" ]] && break
  sleep 5
done

if [[ -z "$IP" ]]; then
  warn "EXTERNAL-IP still pending. Recheck with: kubectl get svc $SVC_NAME"
else
  ok "URL: http://${IP}"
fi

# Generate sample traffic (optional)
if [[ -n "$IP" ]]; then
  step "Generate trace traffic"
  for i in {1..8}; do
    curl -fsS "http://${IP}?string=ePlusTrace${i}" >/dev/null || true
    sleep 1
  done
  ok "Traffic generated"
fi

# Pull Pub/Sub messages (optional)
step "Optional: pull Pub/Sub messages (limit 5)"
gcloud pubsub subscriptions pull --auto-ack --limit 5 tracing-demo-cli || true

hr
ok "DONE. Open: Navigation Menu → Observability → Trace → Trace Explorer"
hr