#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  ePlus.DEV © 2026 - GKE Network Policy Lab (Auto Region/Zone)
#  Full Automation | No manual input | Colored Output
# ============================================================

# ------------------- COLORS -------------------
BOLD="$(tput bold 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"
RED="$(tput setaf 1 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
BLUE="$(tput setaf 4 2>/dev/null || true)"
MAGENTA="$(tput setaf 5 2>/dev/null || true)"
CYAN="$(tput setaf 6 2>/dev/null || true)"

hr(){ printf "%s%s============================================================%s\n" "$BLUE" "$BOLD" "$RESET"; }
step(){ printf "%s%s➜ %s%s\n" "$CYAN" "$BOLD" "$*" "$RESET"; }
ok(){ printf "%s%s✔ %s%s\n" "$GREEN" "$BOLD" "$*" "$RESET"; }
warn(){ printf "%s%s⚠ %s%s\n" "$YELLOW" "$BOLD" "$*" "$RESET"; }
fail(){ printf "%s%s✘ %s%s\n" "$RED" "$BOLD" "$*" "$RESET"; }

clear
hr
printf "%s%s        ePlus.DEV © 2026 - GKE NETWORK POLICY AUTO         %s\n" "$MAGENTA" "$BOLD" "$RESET"
hr

# ------------------- AUTO DETECT REGION / ZONE -------------------
ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"

# If zone exists but region empty -> derive region
if [[ -n "$ZONE" && -z "$REGION" ]]; then
  REGION="${ZONE%-*}"
fi

# If both empty -> fallback to lab default
if [[ -z "$ZONE" ]]; then
  ZONE="europe-west1-d"
fi

if [[ -z "$REGION" ]]; then
  REGION="${ZONE%-*}"
fi

gcloud config set compute/zone "$ZONE" --quiet >/dev/null
gcloud config set compute/region "$REGION" --quiet >/dev/null

ok "Using Region: $REGION"
ok "Using Zone:   $ZONE"

PROJECT_ID="$(gcloud config get-value project)"
ok "Project: $PROJECT_ID"

# ------------------- CONSTANTS -------------------
DEMO_BUCKET="gs://spls/gsp480/gke-network-policy-demo"
DEMO_DIR="gke-network-policy-demo"
BASTION="gke-demo-bastion"
CLUSTER="gke-demo-cluster"

# ------------------- CLONE DEMO -------------------
step "Clone demo"
[ -d "$DEMO_DIR" ] || gsutil -m cp -r "$DEMO_BUCKET" .
cd "$DEMO_DIR"
chmod -R 755 .

# ------------------- FIX TFVARS -------------------
rm -f terraform/terraform.tfvars

# ------------------- SETUP PROJECT -------------------
step "Run make setup-project"
bash -lc "
gcloud config set compute/zone '$ZONE' --quiet
gcloud config set compute/region '$REGION' --quiet
yes y | make setup-project
"
ok "setup-project done"

# ------------------- TERRAFORM APPLY -------------------
step "Terraform apply"
cd terraform
terraform init -input=false >/dev/null
terraform apply -auto-approve -input=false
cd ..
ok "Infrastructure ready"

# ------------------- COPY TO BASTION -------------------
step "Copy demo to bastion"
cd ..
tar -czf /tmp/eplus_demo.tgz "$DEMO_DIR"
gcloud compute scp --quiet /tmp/eplus_demo.tgz "$BASTION":~/eplus_demo.tgz
ok "Copied"

# ------------------- BASTION STEPS -------------------
step "Configure bastion"

gcloud compute ssh --quiet "$BASTION" --command "
set -e
sudo apt-get update -y >/dev/null
sudo apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin >/dev/null
echo 'export USE_GKE_GCLOUD_AUTH_PLUGIN=True' >> ~/.bashrc
source ~/.bashrc

tar -xzf ~/eplus_demo.tgz -C ~/
cd ~/$DEMO_DIR

gcloud container clusters get-credentials $CLUSTER --zone $ZONE

kubectl apply -f ./manifests/hello-app/
kubectl apply -f ./manifests/network-policy.yaml
kubectl delete -f ./manifests/network-policy.yaml || true
kubectl apply -f ./manifests/network-policy-namespaced.yaml
kubectl -n hello-apps apply -f ./manifests/hello-app/hello-client.yaml

kubectl get pods -A
"

ok "All tasks executed successfully"

hr
printf "%s%s✔ DONE - Click 'Check my progress'%s\n" "$GREEN" "$BOLD" "$RESET"
hr