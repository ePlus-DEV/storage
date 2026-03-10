#!/bin/bash
set -euo pipefail

# =========================================================
# ePlus.DEV
# Continuous Delivery with Jenkins in Kubernetes Engine
# All-in-one helper script for lab gsp051
# =========================================================

# -------------------------
# Colors
# -------------------------
RED="$(tput setaf 1 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
BLUE="$(tput setaf 4 2>/dev/null || true)"
MAGENTA="$(tput setaf 5 2>/dev/null || true)"
CYAN="$(tput setaf 6 2>/dev/null || true)"
BOLD="$(tput bold 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"
BG_MAGENTA="$(tput setab 5 2>/dev/null || true)"
WHITE="$(tput setaf 7 2>/dev/null || true)"

log()    { echo "${CYAN}${BOLD}[$(date '+%H:%M:%S')] $*${RESET}"; }
ok()     { echo "${GREEN}${BOLD}[OK] $*${RESET}"; }
warn()   { echo "${YELLOW}${BOLD}[WARN] $*${RESET}"; }
error()  { echo "${RED}${BOLD}[ERROR] $*${RESET}"; }

echo "${BG_MAGENTA}${WHITE}${BOLD} Starting Execution - ePlus.DEV ${RESET}"

# -------------------------
# User configurable values
# -------------------------
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
CLUSTER_NAME="jenkins-cd"
APP_NAME="gceme"
REPO_NAME="default"

# Optional env vars:
# export USER_EMAIL="you@example.com"
# export GITHUB_USERNAME="your_github_username"

# -------------------------
# Check commands
# -------------------------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { error "Missing command: $1"; exit 1; }
}
for c in gcloud gsutil kubectl helm git curl unzip ssh-keygen ssh-keyscan; do
  need_cmd "$c"
done

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  error "No active Google Cloud project. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

log "PROJECT_ID = ${PROJECT_ID}"
log "REGION     = ${REGION}"
log "ZONE       = ${ZONE}"

# -------------------------
# Task 1 - Download source
# -------------------------
log "Setting compute zone..."
gcloud config set compute/zone "${ZONE}" >/dev/null

if [[ ! -f continuous-deployment-on-kubernetes.zip ]]; then
  log "Downloading source archive..."
  gsutil cp gs://spls/gsp051/continuous-deployment-on-kubernetes.zip .
else
  warn "Archive already exists, skipping download."
fi

if [[ ! -d continuous-deployment-on-kubernetes ]]; then
  log "Unzipping source archive..."
  unzip -o continuous-deployment-on-kubernetes.zip
else
  warn "Directory already exists, skipping unzip."
fi

cd continuous-deployment-on-kubernetes

# -------------------------
# Task 2 - Provision Jenkins cluster
# -------------------------
if ! gcloud container clusters describe "${CLUSTER_NAME}" --zone "${ZONE}" >/dev/null 2>&1; then
  log "Creating Kubernetes cluster ${CLUSTER_NAME}..."
  gcloud container clusters create "${CLUSTER_NAME}" \
    --num-nodes 2 \
    --machine-type e2-standard-2 \
    --scopes "https://www.googleapis.com/auth/source.read_write,cloud-platform"
  ok "Cluster created."
else
  warn "Cluster ${CLUSTER_NAME} already exists."
fi

log "Listing clusters..."
gcloud container clusters list

log "Getting cluster credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}"

log "Checking cluster info..."
kubectl cluster-info

# -------------------------
# Task 3 - Set up Helm
# -------------------------
log "Configuring Helm repo..."
helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
helm repo update

# -------------------------
# Task 4 - Install Jenkins
# -------------------------
if ! helm status cd >/dev/null 2>&1; then
  log "Installing Jenkins chart..."
  helm install cd jenkins/jenkins -f jenkins/values.yaml --wait
  ok "Jenkins installed."
else
  warn "Jenkins release 'cd' already exists."
fi

log "Checking Jenkins pods..."
kubectl get pods

if ! kubectl get clusterrolebinding jenkins-deploy >/dev/null 2>&1; then
  log "Creating clusterrolebinding for Jenkins..."
  kubectl create clusterrolebinding jenkins-deploy \
    --clusterrole=cluster-admin \
    --serviceaccount=default:cd-jenkins
else
  warn "clusterrolebinding jenkins-deploy already exists."
fi

log "Starting Jenkins port-forward..."
POD_NAME="$(kubectl get pods --namespace default \
  -l "app.kubernetes.io/component=jenkins-master" \
  -l "app.kubernetes.io/instance=cd" \
  -o jsonpath="{.items[0].metadata.name}")"

if [[ -n "${POD_NAME}" ]]; then
  pkill -f "kubectl port-forward.*8080:8080" >/dev/null 2>&1 || true
  nohup kubectl port-forward "${POD_NAME}" 8080:8080 >/dev/null 2>&1 &
  ok "Port-forward started on 8080."
else
  error "Could not find Jenkins pod."
  exit 1
fi

log "Checking services..."
kubectl get svc

JENKINS_PASSWORD="$(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)"
echo
echo "${GREEN}${BOLD}Jenkins URL     : http://localhost:8080${RESET}"
echo "${GREEN}${BOLD}Jenkins Username: admin${RESET}"
echo "${GREEN}${BOLD}Jenkins Password: ${JENKINS_PASSWORD}${RESET}"
echo

# -------------------------
# Task 7 - Deploy application
# -------------------------
cd sample-app

if ! kubectl get ns production >/dev/null 2>&1; then
  log "Creating namespace: production"
  kubectl create ns production
else
  warn "Namespace production already exists."
fi

log "Applying production manifests..."
kubectl apply -f k8s/production -n production
kubectl apply -f k8s/canary -n production
kubectl apply -f k8s/services -n production

log "Scaling frontend production to 4 replicas..."
kubectl scale deployment gceme-frontend-production -n production --replicas 4

log "Checking frontend pods..."
kubectl get pods -n production -l app=gceme -l role=frontend

log "Checking backend pods..."
kubectl get pods -n production -l app=gceme -l role=backend

log "Checking external service..."
kubectl get service gceme-frontend -n production || true

log "Waiting briefly for external IP..."
sleep 20

FRONTEND_SERVICE_IP="$(kubectl get -o jsonpath="{.status.loadBalancer.ingress[0].ip}" --namespace=production services gceme-frontend 2>/dev/null || true)"
if [[ -n "${FRONTEND_SERVICE_IP}" ]]; then
  ok "Frontend external IP: ${FRONTEND_SERVICE_IP}"
  echo "Version check:"
  curl -sf "http://${FRONTEND_SERVICE_IP}/version" || warn "External IP not ready yet. Retry later."
else
  warn "External IP not ready yet. This is normal, load balancer may need more time."
fi

# -------------------------
# Task 8 - GitHub CLI / Repo
# -------------------------
if ! command -v gh >/dev/null 2>&1; then
  warn "GitHub CLI not found. Installing..."
  curl -sS https://webi.sh/gh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v gh >/dev/null 2>&1; then
  error "gh command still unavailable after install."
  exit 1
fi

echo
echo "${YELLOW}${BOLD}GitHub login is required in browser.${RESET}"
echo "${YELLOW}${BOLD}When prompted, complete authentication and come back.${RESET}"
echo

if ! gh auth status >/dev/null 2>&1; then
  gh auth login
fi

if [[ -z "${GITHUB_USERNAME:-}" ]]; then
  GITHUB_USERNAME="$(gh api user -q ".login")"
fi

if [[ -z "${USER_EMAIL:-}" ]]; then
  USER_EMAIL="$(gh api user -q ".email" 2>/dev/null || true)"
fi

if [[ -z "${USER_EMAIL:-}" || "${USER_EMAIL}" == "null" ]]; then
  warn "Could not detect GitHub email automatically."
  read -rp "Enter your GitHub email: " USER_EMAIL
fi

git config --global user.name "${GITHUB_USERNAME}"
git config --global user.email "${USER_EMAIL}"

echo "${GREEN}${BOLD}GITHUB_USERNAME=${GITHUB_USERNAME}${RESET}"
echo "${GREEN}${BOLD}USER_EMAIL=${USER_EMAIL}${RESET}"

if gh repo view "${GITHUB_USERNAME}/${REPO_NAME}" >/dev/null 2>&1; then
  warn "Repo ${GITHUB_USERNAME}/${REPO_NAME} already exists."
else
  log "Creating private GitHub repo: ${REPO_NAME}"
  gh repo create "${REPO_NAME}" --private --confirm
fi

# -------------------------
# Init repo and first push
# -------------------------
if [[ ! -d .git ]]; then
  log "Initializing git repo..."
  git init
else
  warn ".git already exists."
fi

git config credential.helper gcloud.sh || true

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "https://github.com/${GITHUB_USERNAME}/${REPO_NAME}"
else
  warn "Remote origin already exists."
fi

git add .
git commit -m "Initial commit" || warn "Nothing to commit."
git branch -M master
git push -u origin master || warn "Initial push may already exist."

# -------------------------
# SSH key for Jenkins <-> GitHub
# -------------------------
if [[ ! -f id_github ]]; then
  log "Generating SSH key for Jenkins/GitHub..."
  ssh-keygen -t rsa -b 4096 -N '' -f id_github -C "${USER_EMAIL}"
  ok "SSH key generated."
else
  warn "SSH key id_github already exists."
fi

log "Creating known_hosts.github..."
ssh-keyscan -t rsa github.com > known_hosts.github
chmod 600 known_hosts.github

echo
echo "${MAGENTA}${BOLD}====================================================${RESET}"
echo "${MAGENTA}${BOLD}MANUAL STEPS REQUIRED IN GITHUB + JENKINS UI${RESET}"
echo "${MAGENTA}${BOLD}====================================================${RESET}"
echo "1. Open GitHub > Settings > SSH and GPG keys > New SSH key"
echo "2. Add title: SSH_KEY_LAB"
echo "3. Paste the content of: $(pwd)/id_github.pub"
echo
echo "4. Open Jenkins: http://localhost:8080"
echo "5. Login with admin / password shown above"
echo "6. Add Google Service Account from metadata credential"
echo "   - ID = ${PROJECT_ID}"
echo "7. Configure Cloud:"
echo "   - Jenkins URL    = http://cd-jenkins:8080"
echo "   - Jenkins tunnel = cd-jenkins-agent:50000"
echo "8. Add SSH Username with private key credential:"
echo "   - ID       = ${PROJECT_ID}_ssh_key"
echo "   - Username = ${GITHUB_USERNAME}"
echo "   - Private key = content of file: $(pwd)/id_github"
echo "9. Jenkins Security > Git Host Key Verification"
echo "   - Strategy = Manually provided keys"
echo "   - Paste content of: $(pwd)/known_hosts.github"
echo "10. Create Multibranch Pipeline job:"
echo "   - Name = sample-app"
echo "   - Branch source = Git"
echo "   - Repo = git@github.com:${GITHUB_USERNAME}/${REPO_NAME}.git"
echo "   - Credentials = ${PROJECT_ID}_ssh_key"
echo "   - Scan trigger = every 1 minute"
echo "${MAGENTA}${BOLD}====================================================${RESET}"
echo

# -------------------------
# Task 9 - Create development branch
# -------------------------
if git show-ref --verify --quiet refs/heads/new-feature; then
  git checkout new-feature
else
  git checkout -b new-feature
fi

log "Updating Jenkinsfile with PROJECT_ID and ZONE..."
sed -i "s/REPLACE_WITH_YOUR_PROJECT_ID/${PROJECT_ID}/g" Jenkinsfile
sed -i 's/CLUSTER_ZONE = ".*"/CLUSTER_ZONE = "'"${ZONE}"'"/g' Jenkinsfile || true

log "Updating site color blue -> orange..."
sed -i 's/<div class="card blue">/<div class="card orange">/g' html.go

log "Updating version 1.0.0 -> 2.0.0..."
sed -i 's/const version string = "1.0.0"/const version string = "2.0.0"/g' main.go

git add Jenkinsfile html.go main.go
git commit -m "Version 2.0.0" || warn "No changes to commit for new-feature."
git push -u origin new-feature

# -------------------------
# Task 10 - kubectl proxy and test
# -------------------------
log "Starting kubectl proxy..."
pkill -f "kubectl proxy" >/dev/null 2>&1 || true
nohup kubectl proxy >/dev/null 2>&1 &

sleep 5
echo
echo "${GREEN}${BOLD}Try this after Jenkins builds new-feature successfully:${RESET}"
echo "curl http://localhost:8001/api/v1/namespaces/new-feature/services/gceme-frontend:80/proxy/version"
echo

# -------------------------
# Task 11 - Canary
# -------------------------
if git show-ref --verify --quiet refs/heads/canary; then
  git checkout canary
else
  git checkout -b canary
fi

git push -u origin canary

# -------------------------
# Task 12 - Production
# -------------------------
git checkout master
git merge canary || true
git push origin master

echo
echo "${BG_MAGENTA}${WHITE}${BOLD} Completed - ePlus.DEV ${RESET}"
echo
echo "${GREEN}${BOLD}Summary${RESET}"
echo "Project ID          : ${PROJECT_ID}"
echo "Zone                : ${ZONE}"
echo "Region              : ${REGION}"
echo "Cluster             : ${CLUSTER_NAME}"
echo "GitHub Username     : ${GITHUB_USERNAME}"
echo "Repo                : git@github.com:${GITHUB_USERNAME}/${REPO_NAME}.git"
echo "Jenkins URL         : http://localhost:8080"
echo "SSH public key file : $(pwd)/id_github.pub"
echo "SSH private key file: $(pwd)/id_github"
echo "Known hosts file    : $(pwd)/known_hosts.github"
echo
echo "${YELLOW}${BOLD}Important:${RESET} Jenkins UI / GitHub SSH key steps still need to be completed manually."
echo "${YELLOW}${BOLD}After Jenkins jobs finish, verify:${RESET}"
echo "kubectl get service gceme-frontend -n production"
echo 'export FRONTEND_SERVICE_IP=$(kubectl get -o jsonpath="{.status.loadBalancer.ingress[0].ip}" --namespace=production services gceme-frontend)'
echo 'while true; do curl http://$FRONTEND_SERVICE_IP/version; sleep 1; done'