#!/usr/bin/env bash
set -euo pipefail

# ================================
# ePlus.DEV Branding + Colors
# ================================
# Palette
#   Primary   #0EA5E9  (cyan)
#   Secondary #22C55E  (green)
#   Accent    #F59E0B  (yellow)
#   Dark      #0F172A
#   Light     #F8FAFC

C_PRIMARY="\033[36m"
C_SECOND="\033[32m"
C_ACCENT="\033[33m"
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
# Task 1: Provision infra
# -------------------------
section "Clone the lab repository"
git clone https://github.com/Redislabs-Solution-Architects/gcp-microservices-demo-qwiklabs.git
cd gcp-microservices-demo-qwiklabs
ok "Repository cloned"

section "Create terraform.tfvars"
cat <<EOF > terraform.tfvars
gcp_project_id = "$(gcloud config list project --format='value(core.project)')"
gcp_region = "$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-region])')"
EOF
ok "terraform.tfvars created"

section "Initialize & apply Terraform"
terraform init
terraform apply -auto-approve
ok "Terraform finished"

section "Export outputs"
export REDIS_DEST=$(terraform output -raw db_private_endpoint)
export REDIS_DEST_PASS=$(terraform output -raw db_password)
export REDIS_ENDPOINT="${REDIS_DEST},user=default,password=${REDIS_DEST_PASS}"
ok "Redis Enterprise vars set"

section "Connect kubectl to GKE"
gcloud container clusters get-credentials \
  $(terraform output -raw gke_cluster_name) \
  --region $(terraform output -raw region)
ok "kubectl connected"

section "Get External IP of frontend"
kubectl get service frontend-external -n redis
echo -e "${C_ACCENT}Open: http://<EXTERNAL-IP>${C_RESET}"
echo "Add items to cart before migration."
# End of Task 1

# -------------------------
# Task 2: Migrate to Redis Enterprise
# -------------------------
section "Switch namespace to redis"
kubectl config set-context --current --namespace=redis
ok "Namespace set"

section "Show current cartservice env (OSS Redis)"
kubectl get deployment cartservice -o jsonpath='{.spec.template.spec.containers[0].env}' | jq

section "Create Secret with Redis creds"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: redis-creds
type: Opaque
stringData:
  REDIS_SOURCE: redis://redis-cart:6379
  REDIS_DEST: redis://${REDIS_DEST}
  REDIS_DEST_PASS: ${REDIS_DEST_PASS}
EOF
ok "Secret applied"

section "Run migration job (RIOT)"
kubectl apply -f https://raw.githubusercontent.com/Redislabs-Solution-Architects/gcp-microservices-demo-qwiklabs/main/util/redis-migrator-job.yaml
ok "Migration job started"

section "Patch cartservice → Redis Enterprise"
kubectl patch deployment cartservice --patch \
  "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"server\",\"env\":[{\"name\":\"REDIS_ADDR\",\"value\":\"${REDIS_ENDPOINT}\"}]}]}}}}"
ok "Cartservice patched"

section "Verify env (now Redis Enterprise)"
kubectl get deployment cartservice -o jsonpath='{.spec.template.spec.containers[0].env}' | jq
echo "Refresh browser and verify cart items are still there."
# End of Task 2

# -------------------------
# Task 3: Rollback to OSS Redis
# -------------------------
section "Rollback cartservice → OSS Redis"
kubectl patch deployment cartservice --patch \
  '{"spec":{"template":{"spec":{"containers":[{"name":"server","env":[{"name":"REDIS_ADDR","value":"redis-cart:6379"}]}]}}}}'
ok "Cartservice rolled back"

section "Verify rollback env"
kubectl get deployment cartservice -o jsonpath='{.spec.template.spec.containers[0].env}' | jq
echo "Refresh browser: new items from Redis Enterprise will NOT appear now."
# End of Task 3

# -------------------------
# Task 4: Switch back to Redis Enterprise
# -------------------------
section "Patch cartservice → Redis Enterprise (PRODUCTION)"
kubectl patch deployment cartservice --patch \
  "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"server\",\"env\":[{\"name\":\"REDIS_ADDR\",\"value\":\"${REDIS_ENDPOINT}\"}]}]}}}}"
ok "Cartservice switched back to Redis Enterprise"

section "Verify final env"
kubectl get deployment cartservice -o jsonpath='{.spec.template.spec.containers[0].env}' | jq

section "Optional: delete OSS Redis deployment"
echo "kubectl delete deploy redis-cart"
echo -e "${C_SECOND}${C_BOLD}✔ DONE. Cartservice now runs on Redis Enterprise (production).${C_RESET}"
