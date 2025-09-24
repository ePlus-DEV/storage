#!/usr/bin/env bash
# ==============================================================================
#  ePlus.DEV – Deploy Online Boutique with Redis Enterprise on GKE (Qwiklabs)
# ==============================================================================
#  Branding (ePlus.DEV)
#  ┌───────────────────────────────────────────────────────────────────────────┐
#  │ Brand Name : ePlus.DEV                                                    │
#  │ Palette    :                                                              │
#  │   • Primary   #0EA5E9  (ANSI cyan)                                        │
#  │   • Secondary #22C55E  (ANSI green)                                       │
#  │   • Accent    #F59E0B  (ANSI yellow)                                      │
#  │   • Dark      #0F172A  (near ANSI bold/white on dark bg)                  │
#  │   • Light     #F8FAFC  (terminal default background)                      │
#  └───────────────────────────────────────────────────────────────────────────┘
#
#  What this script does (end-to-end):
#    1) Provision infra via Terraform: VPC, GKE, Redis Enterprise Operator, App
#    2) Export Redis Enterprise outputs & connect kubectl to GKE
#    3) Run RIOT migration (OSS Redis → Redis Enterprise)
#    4) Patch cartservice to Redis Enterprise (prod)
#    5) (Optional) Roll back to OSS Redis, then switch back to Redis Enterprise
#    6) (Optional) Show how to remove OSS Redis deployment
#
#  Requirements: Run inside Google Cloud Shell with the lab’s student account.
#  NOTE: This script is safe to re-run; it uses idempotent applies/patches where
#        possible and prints helpful status along the way.
# ==============================================================================

set -euo pipefail

# ----- ePlus.DEV ANSI Colors -----
# Primary (cyan), Secondary (green), Accent (yellow), Muted (grey), Reset
C_PRIMARY="\033[36m"
C_SECOND="\033[32m"
C_ACCENT="\033[33m"
C_MUTED="\033[90m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

banner() {
  echo -e "${C_PRIMARY}${C_BOLD}"
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║                         ePlus.DEV – Cloud                       ║"
  echo "║  Online Boutique + Redis Enterprise on GKE (Qwiklabs Automation)║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo -e "${C_RESET}"
}

section() {
  echo -e "\n${C_ACCENT}${C_BOLD}>>> $*${C_RESET}"
}

ok() {
  echo -e "${C_SECOND}${C_BOLD}✔${C_RESET} $*"
}

warn() {
  echo -e "${C_ACCENT}${C_BOLD}!${C_RESET} $*"
}

info() {
  echo -e "${C_MUTED}i${C_RESET} $*"
}

banner

# ----- Quick Config (you may change if needed) -----
REPO_URL="https://github.com/Redislabs-Solution-Architects/gcp-microservices-demo-qwiklabs.git"
REPO_DIR="gcp-microservices-demo-qwiklabs"
GCP_REGION_VAR=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
K8S_NAMESPACE="redis"
# Set ROLLBACK_TEST=true to run rollback tests; set false to skip.
ROLLBACK_TEST="${ROLLBACK_TEST:-true}"

section "Checking prerequisites"
sudo apt-get update -y >/dev/null 2>&1 || true
sudo apt-get install -y jq >/dev/null 2>&1 || true
ok "jq installed/available"

section "Verifying active Google Cloud project"
gcloud config list project
PROJECT_ID="$(gcloud config get-value core/project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "Project is not set in gcloud. Please use the lab student account."
  exit 1
fi
ok "Project: ${PROJECT_ID}"

section "Cloning lab repository"
if [[ ! -d "${REPO_DIR}" ]]; then
  git clone "${REPO_URL}"
  ok "Repository cloned"
else
  info "Repository already exists - skipping clone"
fi
cd "${REPO_DIR}"

section "Writing terraform.tfvars"
cat > terraform.tfvars <<EOF
gcp_project_id = "$(gcloud config list project --format='value(core.project)')"
gcp_region     = "${GCP_REGION_VAR}"
EOF
ok "terraform.tfvars created"

section "Terraform init"
terraform init -input=false
ok "Terraform initialized"

section "Terraform apply (may take ~5–10 minutes)"
terraform apply -auto-approve
ok "Terraform apply finished"

section "Fetching Terraform outputs (Redis Enterprise & GKE)"
REDIS_DEST="$(terraform output -raw db_private_endpoint)"
REDIS_DEST_PASS="$(terraform output -raw db_password)"
GKE_CLUSTER="$(terraform output -raw gke_cluster_name)"
REGION="$(terraform output -raw region)"
REDIS_ENDPOINT="${REDIS_DEST},user=default,password=${REDIS_DEST_PASS}"

info "REDIS_DEST   : ${REDIS_DEST}"
info "GKE_CLUSTER  : ${GKE_CLUSTER}"
info "REGION       : ${REGION}"

section "Connecting kubectl to GKE"
gcloud container clusters get-credentials "${GKE_CLUSTER}" --region "${REGION}"
ok "kubectl context configured"

section "Ensuring Kubernetes namespace: ${K8S_NAMESPACE}"
kubectl get ns "${K8S_NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${K8S_NAMESPACE}"
ok "Namespace ready"

section "Getting External IP for frontend-external (LoadBalancer)"
EXTERNAL_IP=""
for i in {1..30}; do
  SVC_JSON="$(kubectl -n "${K8S_NAMESPACE}" get svc frontend-external -o json 2>/dev/null || true)"
  if [[ -n "${SVC_JSON}" ]]; then
    EXTERNAL_IP="$(echo "${SVC_JSON}" | jq -r '.status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // empty')"
    if [[ -n "${EXTERNAL_IP}" && "${EXTERNAL_IP}" != "null" ]]; then
      break
    fi
  fi
  echo "Waiting for External IP (retry $i/30)..."
  sleep 10
done
if [[ -z "${EXTERNAL_IP}" ]]; then
  warn "External IP not ready yet. You can check later with:"
  echo "kubectl -n ${K8S_NAMESPACE} get svc frontend-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}' && echo"
else
  ok  "App URL: http://${EXTERNAL_IP}"
fi

section "Switching default context to namespace ${K8S_NAMESPACE}"
kubectl config set-context --current --namespace="${K8S_NAMESPACE}" >/dev/null
ok "Context updated"

section "Cartservice env BEFORE migration (should point to OSS Redis)"
kubectl get deployment cartservice -o jsonpath='{.spec.template.spec.containers[0].env}' | jq

section "Creating Secret: redis-creds (source & destination)"
kubectl -n "${K8S_NAMESPACE}" create secret generic redis-creds \
  --from-literal=REDIS_SOURCE="redis://redis-cart:6379" \
  --from-literal=REDIS_DEST="redis://${REDIS_DEST}" \
  --from-literal=REDIS_DEST_PASS="${REDIS_DEST_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -
ok "Secret applied"

section "Running RIOT migration job (OSS Redis → Redis Enterprise)"
kubectl apply -n "${K8S_NAMESPACE}" -f https://raw.githubusercontent.com/Redislabs-Solution-Architects/gcp-microservices-demo-qwiklabs/main/util/redis-migrator-job.yaml

section "Waiting for redis-migrator job to complete (timeout 2m)"
kubectl -n "${K8S_NAMESPACE}" wait --for=condition=complete --timeout=120s job/redis-migrator || true
info "redis-migrator logs (for reference):"
kubectl -n "${K8S_NAMESPACE}" logs job/redis-migrator || true

section "Patching cartservice to use Redis Enterprise (PRODUCTION)"
kubectl -n "${K8S_NAMESPACE}" patch deployment cartservice \
  --type=merge \
  -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"server\",\"env\":[{\"name\":\"REDIS_ADDR\",\"value\":\"${REDIS_ENDPOINT}\"}]}]}}}}"
kubectl -n "${K8S_NAMESPACE}" rollout status deployment/cartservice --timeout=180s
ok "Cartservice now targets Redis Enterprise"

section "Cartservice env AFTER patch"
kubectl -n "${K8S_NAMESPACE}" get deployment cartservice -o jsonpath='{.spec.template.spec.containers[0].env}' | jq

if [[ "${ROLLBACK_TEST}" == "true" ]]; then
  section "[Rollback Test] Switch back temporarily to OSS Redis"
  kubectl -n "${K8S_NAMESPACE}" patch deployment cartservice \
    --type=merge \
    -p '{"spec":{"template":{"spec":{"containers":[{"name":"server","env":[{"name":"REDIS_ADDR","value":"redis-cart:6379"}]}]}}}}'
  kubectl -n "${K8S_NAMESPACE}" rollout status deployment/cartservice --timeout=180s
  ok "Cartservice now targets OSS Redis (test)"

  section "Cartservice env while on OSS Redis"
  kubectl -n "${K8S_NAMESPACE}" get deployment cartservice -o jsonpath='{.spec.template.spec.containers[0].env}' | jq

  section "[Rollback Test] Switch back to Redis Enterprise (PRODUCTION)"
  kubectl -n "${K8S_NAMESPACE}" patch deployment cartservice \
    --type=merge \
    -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"server\",\"env\":[{\"name\":\"REDIS_ADDR\",\"value\":\"${REDIS_ENDPOINT}\"}]}]}}}}"
  kubectl -n "${K8S_NAMESPACE}" rollout status deployment/cartservice --timeout=180s
  ok "Cartservice back on Redis Enterprise"
else
  warn "Rollback test skipped (set ROLLBACK_TEST=true to enable)."
fi

section "(Optional) Remove OSS Redis deployment (production only)"
info "If you want to remove it now, run:"
echo "kubectl -n ${K8S_NAMESPACE} delete deploy redis-cart"

echo -e "\n${C_BOLD}======================= SUMMARY (ePlus.DEV) =======================${C_RESET}"
if [[ -n "${EXTERNAL_IP:-}" ]]; then
  echo -e "Visit the app: ${C_PRIMARY}http://${EXTERNAL_IP}${C_RESET}"
else
  echo "App IP not ready yet. Check later with the jsonpath command printed above."
fi
echo "• Infrastructure provisioned with Terraform (VPC, GKE, Operator, App)"
echo "• Data migrated via RIOT (OSS Redis → Redis Enterprise)"
echo "• Cartservice pointed to Redis Enterprise (prod)"
echo "• Rollback test executed: ${ROLLBACK_TEST}"
echo "==================================================================="