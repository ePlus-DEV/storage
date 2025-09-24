#!/usr/bin/env bash
set -euo pipefail

# ================================
# ePlus.DEV Branding + Colors
# ================================
# Palette
#   Primary   #0EA5E9  (cyan)
#   Secondary #22C55E  (green)
#   Accent    #F59E0B  (yellow)
#   Dark      #0F172A  (background/heading)
#   Light     #F8FAFC  (default bg)

C_PRIMARY="\033[36m"   # cyan
C_SECOND="\033[32m"    # green
C_ACCENT="\033[33m"    # yellow
C_BOLD="\033[1m"
C_RESET="\033[0m"

banner() {
  echo -e "${C_PRIMARY}${C_BOLD}"
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║             ePlus.DEV – Redis Enterprise Lab         ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo -e "${C_RESET}"
}

section() {
  echo -e "\n${C_ACCENT}${C_BOLD}>>> $*${C_RESET}"
}

ok() {
  echo -e "${C_SECOND}${C_BOLD}✔${C_RESET} $*"
}

banner

# -------------------------
# Step 1. Clone repository
# -------------------------
section "Clone the lab repository"
git clone https://github.com/Redislabs-Solution-Architects/gcp-microservices-demo-qwiklabs.git
cd gcp-microservices-demo-qwiklabs
ok "Repository cloned"

# -------------------------
# Step 2. Create terraform.tfvars
# -------------------------
section "Create terraform.tfvars"
cat <<EOF > terraform.tfvars
gcp_project_id = "$(gcloud config list project --format='value(core.project)')"
gcp_region = "europe-west4"
EOF
ok "terraform.tfvars created"

# -------------------------
# Step 3. Terraform init/apply
# -------------------------
section "Initialize & apply Terraform"
terraform init
terraform apply -auto-approve
ok "Terraform finished"

# -------------------------
# Step 4. Export Redis Enterprise outputs
# -------------------------
section "Export outputs"
export REDIS_DEST=$(terraform output -raw db_private_endpoint)
export REDIS_DEST_PASS=$(terraform output -raw db_password)
export REDIS_ENDPOINT="${REDIS_DEST},user=default,password=${REDIS_DEST_PASS}"
ok "Redis Enterprise vars set"

# -------------------------
# Step 5. Connect kubectl
# -------------------------
section "Connect kubectl to GKE"
gcloud container clusters get-credentials \
  $(terraform output -raw gke_cluster_name) \
  --region $(terraform output -raw region)
ok "kubectl connected"

# -------------------------
# Step 6. Get External IP
# -------------------------
section "Get External IP"
kubectl get service frontend-external -n redis
echo -e "${C_ACCENT}Open: http://<EXTERNAL-IP>${C_RESET}"
