#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  ePlus.DEV © 2026 - GKE Distributed Tracing Lab
#  Full Automation | No manual input | Colored Output
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

clear
hr
printf "%s%s      ePlus.DEV © 2026 - GKE DISTRIBUTED TRACING LAB      %s\n" "$MAGENTA" "$BOLD" "$RESET"
hr

PROJECT_ID=$(gcloud config get-value project)
ZONE=$(gcloud config get-value compute/zone 2>/dev/null || true)
REGION=$(gcloud config get-value compute/region 2>/dev/null || true)

# Auto derive region if missing
if [[ -z "$ZONE" ]]; then
  ZONE="us-central1-f"
fi
if [[ -z "$REGION" ]]; then
  REGION="${ZONE%-*}"
fi

gcloud config set compute/zone "$ZONE" --quiet
gcloud config set compute/region "$REGION" --quiet

ok "Project: $PROJECT_ID"
ok "Region:  $REGION"
ok "Zone:    $ZONE"

# ---------------- CLONE DEMO ----------------
step "Cloning tracing demo repository"
[ -d gke-tracing-demo ] || git clone https://github.com/GoogleCloudPlatform/gke-tracing-demo
cd gke-tracing-demo

# ---------------- TERRAFORM SETUP ----------------
step "Preparing Terraform"

cd terraform

# Remove provider version line automatically
sed -i '/version *=/d' provider.tf

terraform init -input=false

# Generate tfvars automatically
echo "project = \"$PROJECT_ID\"" > terraform.tfvars
echo "zone    = \"$ZONE\"" >> terraform.tfvars

ok "Terraform initialized"

# ---------------- TERRAFORM APPLY ----------------
step "Deploying infrastructure with Terraform"
terraform apply -auto-approve -input=false

ok "Infrastructure deployed"

cd ..

# ---------------- DEPLOY APP ----------------
step "Deploying tracing demo application"
kubectl apply -f tracing-demo-deployment.yaml

step "Waiting for deployment"
kubectl rollout status deployment/tracing-demo --timeout=180s

ok "Application deployed"

# ---------------- GET ENDPOINT ----------------
IP=$(kubectl get svc tracing-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo
printf "%s%s🌐 Application URL:%s http://%s\n" "$GREEN" "$BOLD" "$RESET" "$IP"
echo

# ---------------- GENERATE SAMPLE TRAFFIC ----------------
step "Generating sample trace traffic"
for i in {1..5}; do
  curl -s "http://$IP?string=ePlusTrace$i" >/dev/null || true
done

ok "Sample traffic generated"

hr
printf "%s%s✔ LAB SETUP COMPLETE%s\n" "$GREEN" "$BOLD" "$RESET"
printf "%sNow open:%s Navigation Menu → Observability → Trace Explorer\n" "$YELLOW" "$RESET"
hr