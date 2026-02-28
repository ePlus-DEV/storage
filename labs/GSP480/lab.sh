#!/bin/bash
set -euo pipefail

# =========================
#  ePlus.DEV - GKE Network Policy Lab (gsp480)
#  Full automation: Task 1 -> Task 8
# =========================

# ---------- colors ----------
BOLD=$'\033[1m'
RESET=$'\033[0m'
RED=$'\033[38;5;196m'
GREEN=$'\033[38;5;46m'
YELLOW=$'\033[38;5;226m'
BLUE=$'\033[38;5;27m'
CYAN=$'\033[38;5;51m'
MAGENTA=$'\033[38;5;201m'
GRAY=$'\033[38;5;245m'

hr() { echo "${BLUE}${BOLD}============================================================${RESET}"; }
ok() { echo "${GREEN}${BOLD}✔${RESET} $*"; }
warn() { echo "${YELLOW}${BOLD}⚠${RESET} $*"; }
err() { echo "${RED}${BOLD}✘${RESET} $*"; }
info() { echo "${CYAN}${BOLD}➜${RESET} $*"; }

# ---------- spinner ----------
spinner() {
  local pid=$1
  local delay=0.12
  local spin='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    printf "  ${MAGENTA}[%c]${RESET} " "$spin"
    spin=${spin#?}${spin%${spin#?}}
    sleep "$delay"
    printf "\b\b\b\b\b\b"
  done
  printf "       \b\b\b\b\b\b\b"
}

# ---------- banner ----------
clear
hr
echo "${GREEN}${BOLD} ePlus.DEV ${RESET}${GRAY}- Full Script: GKE Network Policy Demo (gsp480)${RESET}"
echo "${GRAY} Principle of Least Privilege | Private GKE + Bastion + NetworkPolicy${RESET}"
hr

# ---------- config (edit if needed) ----------
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
DEMO_BUCKET="gs://spls/gsp480/gke-network-policy-demo"
DEMO_DIR="gke-network-policy-demo"
BASTION="gke-demo-bastion"
CLUSTER="gke-demo-cluster"

# ---------- preflight ----------
info "Detecting Project ID..."
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  err "No active project found. Please start the lab, open Cloud Shell, then re-run."
  exit 1
fi
ok "Project: ${PROJECT_ID}"

info "Setting region/zone..."
gcloud config set compute/region "${REGION}" >/dev/null
gcloud config set compute/zone "${ZONE}" >/dev/null
ok "Region=${REGION}, Zone=${ZONE}"

# ---------- fetch demo ----------
if [[ -d "${DEMO_DIR}" ]]; then
  warn "Directory ${DEMO_DIR} already exists. Reusing it."
else
  info "Cloning demo assets from ${DEMO_BUCKET} ..."
  (gsutil -m cp -r "${DEMO_BUCKET}" .) &
  pid=$!; spinner "$pid"; wait "$pid"
  ok "Downloaded demo directory"
fi

cd "${DEMO_DIR}"
chmod -R 755 . || true
ok "Entered $(pwd)"

# ---------- make setup-project ----------
info "Running: make setup-project (auto 'y') ..."
( yes y | make setup-project ) &
pid=$!; spinner "$pid"; wait "$pid"
ok "setup-project completed"

info "terraform.tfvars:"
cat terraform/terraform.tfvars || true
hr

# ---------- terraform apply ----------
info "Running: make tf-apply (auto 'yes') ..."
( yes yes | make tf-apply ) &
pid=$!; spinner "$pid"; wait "$pid"
ok "Terraform apply completed (cluster+bastion should be ready)"
hr

# ---------- SSH to bastion and run remaining steps ----------
info "Connecting to bastion: ${BASTION}"
warn "If SSH asks for confirmation, script will auto-accept host key."

# Build a remote script for bastion
REMOTE_SCRIPT="$(cat <<'EOS'
set -euo pipefail

BOLD=$'\033[1m'
RESET=$'\033[0m'
GREEN=$'\033[38;5;46m'
YELLOW=$'\033[38;5;226m'
CYAN=$'\033[38;5;51m'
MAGENTA=$'\033[38;5;201m'
BLUE=$'\033[38;5;27m'
GRAY=$'\033[38;5;245m'

hr(){ echo "${BLUE}${BOLD}------------------------------------------------------------${RESET}"; }
ok(){ echo "${GREEN}${BOLD}✔${RESET} $*"; }
info(){ echo "${CYAN}${BOLD}➜${RESET} $*"; }
warn(){ echo "${YELLOW}${BOLD}⚠${RESET} $*"; }

# We are now on bastion; demo folder should exist (home is shared? actually bastion has its own disk)
# The demo repo is local on Cloud Shell, not on bastion. We'll re-copy manifests via gcloud scp.
EOS
)"

# We need to copy demo dir from Cloud Shell to bastion, because bastion is a different VM.
info "Copying demo folder to bastion via gcloud scp..."
cd ..
tar -czf /tmp/gke-network-policy-demo.tgz "${DEMO_DIR}"
gcloud compute scp --quiet /tmp/gke-network-policy-demo.tgz "${BASTION}:~/gke-network-policy-demo.tgz" >/dev/null
ok "Copied archive to bastion"

info "Running remote tasks on bastion (install auth plugin, kubectl apply, policies, logs checks)..."

gcloud compute ssh "${BASTION}" --quiet --command "
  set -euo pipefail

  BOLD=\$'\033[1m'
  RESET=\$'\033[0m'
  GREEN=\$'\033[38;5;46m'
  YELLOW=\$'\033[38;5;226m'
  CYAN=\$'\033[38;5;51m'
  BLUE=\$'\033[38;5;27m'
  MAGENTA=\$'\033[38;5;201m'

  hr(){ echo \"\${BLUE}\${BOLD}------------------------------------------------------------\${RESET}\"; }
  ok(){ echo \"\${GREEN}\${BOLD}✔\${RESET} \$*\"; }
  info(){ echo \"\${CYAN}\${BOLD}➜\${RESET} \$*\"; }
  warn(){ echo \"\${YELLOW}\${BOLD}⚠\${RESET} \$*\"; }

  hr
  echo \"\${GREEN}\${BOLD} ePlus.DEV \${RESET} - Bastion Steps\"
  hr

  info \"Unpacking demo archive...\"
  tar -xzf ~/gke-network-policy-demo.tgz -C ~/
  ok \"Demo unpacked at ~/gke-network-policy-demo\"

  cd ~/gke-network-policy-demo

  info \"Installing gke-gcloud-auth-plugin...\"
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin >/dev/null
  ok \"Auth plugin installed\"

  info \"Enabling USE_GKE_GCLOUD_AUTH_PLUGIN...\"
  echo \"export USE_GKE_GCLOUD_AUTH_PLUGIN=True\" >> ~/.bashrc
  source ~/.bashrc
  ok \"Env set\"

  info \"Fetching cluster credentials...\"
  gcloud container clusters get-credentials ${CLUSTER} --zone ${ZONE} >/dev/null
  ok \"kubeconfig updated\"

  hr
  info \"Task 3: Deploy hello-app workloads...\"
  kubectl apply -f ./manifests/hello-app/ >/dev/null
  ok \"hello-app applied\"
  kubectl get pods -o wide

  hr
  info \"Task 4: Quick confirm default access (show last 5 lines from each client)...\"
  ALLOWED_POD=\$(kubectl get pods -l app=hello -o jsonpath='{.items[0].metadata.name}')
  BLOCKED_POD=\$(kubectl get pods -l app=not-hello -o jsonpath='{.items[0].metadata.name}')
  warn \"Allowed pod: \$ALLOWED_POD\"
  warn \"Blocked pod: \$BLOCKED_POD\"
  echo
  echo \"\${MAGENTA}\${BOLD}[allowed client logs]\${RESET}\"
  kubectl logs --tail 5 \"\$ALLOWED_POD\" || true
  echo
  echo \"\${MAGENTA}\${BOLD}[blocked client logs]\${RESET}\"
  kubectl logs --tail 5 \"\$BLOCKED_POD\" || true

  hr
  info \"Task 5: Apply label-based NetworkPolicy...\"
  kubectl apply -f ./manifests/network-policy.yaml >/dev/null
  ok \"NetworkPolicy applied\"

  info \"Checking blocked client should start timing out (tail 8)...\"
  kubectl logs --tail 8 \"\$BLOCKED_POD\" || true

  hr
  info \"Task 6: Switch to namespace-based policy...\"
  kubectl delete -f ./manifests/network-policy.yaml >/dev/null
  ok \"Old policy deleted\"

  kubectl apply -f ./manifests/network-policy-namespaced.yaml >/dev/null
  ok \"Namespaced policy applied\"

  info \"Deploy hello-clients into hello-apps namespace...\"
  kubectl -n hello-apps apply -f ./manifests/hello-app/hello-client.yaml >/dev/null
  ok \"Clients deployed in hello-apps namespace\"

  hr
  info \"Task 7: Validate logs in hello-apps namespace (tail 8)...\"
  HELLO_NS_POD=\$(kubectl get pods -n hello-apps -l app=hello -o jsonpath='{.items[0].metadata.name}')
  warn \"hello-apps allowed pod: \$HELLO_NS_POD\"
  kubectl logs --tail 8 -n hello-apps \"\$HELLO_NS_POD\" || true

  hr
  ok \"Bastion tasks complete. Returning to Cloud Shell.\"
"

ok "Remote steps finished"

# ---------- optional teardown ----------
hr
warn "Task 8 cleanup:"
echo "${GRAY}If you want to teardown NOW (recommended after check progress), run:${RESET}"
echo "${YELLOW}  cd ~/${DEMO_DIR} && make teardown${RESET}"
echo
ok "DONE. Now go back to the lab page and click 'Check my progress' for each task."
hr