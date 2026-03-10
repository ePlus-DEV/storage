#!/bin/bash
set -euo pipefail

# =========================
# ePlus.DEV - All-in-One Script
# Continuous Delivery with Jenkins on GKE
# =========================

# ---------- Colors ----------
BLACK=$(tput setaf 0 || true)
RED=$(tput setaf 1 || true)
GREEN=$(tput setaf 2 || true)
YELLOW=$(tput setaf 3 || true)
BLUE=$(tput setaf 4 || true)
MAGENTA=$(tput setaf 5 || true)
CYAN=$(tput setaf 6 || true)
WHITE=$(tput setaf 7 || true)

BG_BLACK=$(tput setab 0 || true)
BG_RED=$(tput setab 1 || true)
BG_GREEN=$(tput setab 2 || true)
BG_YELLOW=$(tput setab 3 || true)
BG_BLUE=$(tput setab 4 || true)
BG_MAGENTA=$(tput setab 5 || true)
BG_CYAN=$(tput setab 6 || true)
BG_WHITE=$(tput setab 7 || true)

BOLD=$(tput bold || true)
RESET=$(tput sgr0 || true)

# ---------- Helpers ----------
log() {
  echo "${CYAN}${BOLD}[$(date '+%H:%M:%S')] $*${RESET}"
}

ok() {
  echo "${GREEN}${BOLD}[OK] $*${RESET}"
}

warn() {
  echo "${YELLOW}${BOLD}[WARN] $*${RESET}"
}

err() {
  echo "${RED}${BOLD}[ERROR] $*${RESET}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

echo "${BG_MAGENTA}${WHITE}${BOLD} Starting Execution - ePlus.DEV ${RESET}"

# ---------- Requirements ----------
for cmd in gcloud kubectl helm git curl unzip wget; do
  require_cmd "$cmd"
done

# ---------- Install GitHub CLI if missing ----------
if ! command -v gh >/dev/null 2>&1; then
  log "Installing GitHub CLI..."
  curl -fsSL https://webi.sh/gh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

require_cmd gh

# ---------- Fetch GCP config ----------
log "Fetching GCP project settings..."
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
ZONE="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)"
REGION="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null || true)"

if [[ -z "${PROJECT_ID:-}" || "${PROJECT_ID}" == "(unset)" ]]; then
  err "PROJECT_ID is empty. Please run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

if [[ -z "${ZONE:-}" ]]; then
  warn "Default zone metadata not found. Falling back to us-central1-c"
  ZONE="us-central1-c"
fi

if [[ -z "${REGION:-}" ]]; then
  warn "Default region metadata not found. Falling back to us-central1"
  REGION="us-central1"
fi

log "PROJECT_ID = ${PROJECT_ID}"
log "REGION     = ${REGION}"
log "ZONE       = ${ZONE}"

gcloud config set project "${PROJECT_ID}" >/dev/null
gcloud config set compute/region "${REGION}" >/dev/null
gcloud config set compute/zone "${ZONE}" >/dev/null

ok "gcloud config set successfully."

# ---------- Prepare workspace ----------
WORKDIR="${HOME}/continuous-deployment-on-kubernetes"
ZIP_FILE="${HOME}/continuous-deployment-on-kubernetes.zip"

if [[ ! -d "${WORKDIR}" ]]; then
  log "Downloading lab source..."
  gsutil cp gs://spls/gsp051/continuous-deployment-on-kubernetes.zip "${ZIP_FILE}"
  unzip -o "${ZIP_FILE}" -d "${HOME}"
else
  warn "Workspace already exists: ${WORKDIR}"
fi

cd "${WORKDIR}"

# ---------- Create GKE cluster ----------
if ! gcloud container clusters describe jenkins-cd --zone "${ZONE}" >/dev/null 2>&1; then
  log "Creating GKE cluster: jenkins-cd"
  gcloud container clusters create jenkins-cd \
    --num-nodes 2 \
    --machine-type e2-standard-2 \
    --zone "${ZONE}" \
    --scopes "https://www.googleapis.com/auth/source.read_write,cloud-platform"
  ok "Cluster created."
else
  warn "Cluster jenkins-cd already exists. Skipping creation."
fi

log "Getting cluster credentials..."
gcloud container clusters get-credentials jenkins-cd --zone "${ZONE}"

# ---------- Install Jenkins via Helm ----------
log "Configuring Helm repo..."
helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
helm repo update >/dev/null

if ! helm status cd >/dev/null 2>&1; then
  log "Installing Jenkins..."
  helm install cd jenkins/jenkins -f jenkins/values.yaml --wait
  ok "Jenkins installed."
else
  warn "Helm release 'cd' already exists. Skipping install."
fi

# ---------- Cluster role binding ----------
if ! kubectl get clusterrolebinding jenkins-deploy >/dev/null 2>&1; then
  log "Creating clusterrolebinding..."
  kubectl create clusterrolebinding jenkins-deploy \
    --clusterrole=cluster-admin \
    --serviceaccount=default:cd-jenkins
  ok "Cluster role binding created."
else
  warn "Cluster role binding jenkins-deploy already exists."
fi

# ---------- Port forward Jenkins ----------
log "Finding Jenkins pod..."
POD_NAME="$(kubectl get pods --namespace default \
  -l app.kubernetes.io/component=jenkins-master \
  -l app.kubernetes.io/instance=cd \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -n "${POD_NAME}" ]]; then
  log "Starting port-forward for Jenkins on 8080..."
  nohup kubectl port-forward "${POD_NAME}" 8080:8080 >/dev/null 2>&1 &
  ok "Jenkins port-forward started."
else
  err "Jenkins pod not found."
  exit 1
fi

# ---------- Deploy sample app ----------
cd "${WORKDIR}/sample-app"

if ! kubectl get namespace production >/dev/null 2>&1; then
  log "Creating namespace: production"
  kubectl create ns production
else
  warn "Namespace production already exists."
fi

log "Applying Kubernetes manifests..."
kubectl apply -f k8s/production -n production
kubectl apply -f k8s/canary -n production
kubectl apply -f k8s/services -n production

log "Scaling production frontend..."
kubectl scale deployment gceme-frontend-production -n production --replicas=4 || true

log "Checking frontend pods..."
kubectl get pods -n production -l app=gceme -l role=frontend || true

log "Checking backend pods..."
kubectl get pods -n production -l app=gceme -l role=backend || true

log "Checking service..."
kubectl get service gceme-frontend -n production || true

# ---------- GitHub login ----------
if ! gh auth status >/dev/null 2>&1; then
  warn "GitHub CLI is not authenticated yet."
  warn "Please complete GitHub login in the next step."
  gh auth login
fi

GITHUB_USERNAME="$(gh api user -q '.login')"
ok "GitHub username: ${GITHUB_USERNAME}"

# ---------- Git config ----------
if [[ -z "${USER_EMAIL:-}" ]]; then
  read -rp "Enter your GitHub email: " USER_EMAIL
fi

git config --global user.name "${GITHUB_USERNAME}"
git config --global user.email "${USER_EMAIL}"

ok "Git configured with:"
echo "  user.name  = ${GITHUB_USERNAME}"
echo "  user.email = ${USER_EMAIL}"

# ---------- GitHub repo ----------
REPO_NAME="default"
REPO_URL="https://github.com/${GITHUB_USERNAME}/${REPO_NAME}"

if gh repo view "${GITHUB_USERNAME}/${REPO_NAME}" >/dev/null 2>&1; then
  warn "GitHub repo ${GITHUB_USERNAME}/${REPO_NAME} already exists."
else
  log "Creating GitHub repo ${REPO_NAME}..."
  gh repo create "${REPO_NAME}" --private --confirm
  ok "GitHub repo created."
fi

# ---------- Git init / push ----------
if [[ ! -d .git ]]; then
  log "Initializing git repository..."
  git init
else
  warn ".git already exists."
fi

git config credential.helper gcloud.sh || true

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "${REPO_URL}"
else
  warn "Remote origin already exists."
fi

git add .

if ! git diff --cached --quiet || ! git diff --quiet; then
  git commit -m "Initial commit" || true
else
  warn "No changes to commit for initial commit."
fi

DEFAULT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo master)"

log "Pushing source to ${DEFAULT_BRANCH}..."
git push -u origin "${DEFAULT_BRANCH}" || true

# ---------- Update lab files ----------
cd "${WORKDIR}/sample-app"

# Create / switch new-feature
if git show-ref --verify --quiet refs/heads/new-feature; then
  git checkout new-feature
else
  git checkout -b new-feature
fi

rm -f Jenkinsfile html.go main.go

wget -O Jenkinsfile "https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/GSP051/step1.shJenkinsfile"
wget -O html.go "https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/GSP051/step1.shhtml.go"
wget -O main.go "https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/GSP051/step1.shmain.go"

sed -i "s/qwiklabs-gcp-01-2848c53eb4b6/${PROJECT_ID}/g" Jenkinsfile
sed -i "s/us-central1-c/${ZONE}/g" Jenkinsfile

git add Jenkinsfile html.go main.go
git commit -m "Version 2.0.0" || warn "No changes to commit on new-feature."

git push -u origin new-feature || true

# Create / switch canary
if git show-ref --verify --quiet refs/heads/canary; then
  git checkout canary
else
  git checkout -b canary
fi

git push -u origin canary || true

# Merge canary to default branch
git checkout "${DEFAULT_BRANCH}"
git merge canary || true
git push origin "${DEFAULT_BRANCH}" || true

echo
echo "${BG_GREEN}${BLACK}${BOLD} Script completed successfully - ePlus.DEV ${RESET}"
echo "${BOLD}Summary:${RESET}"
echo "  Project ID : ${PROJECT_ID}"
echo "  Region     : ${REGION}"
echo "  Zone       : ${ZONE}"
echo "  GitHub     : ${REPO_URL}"
echo "  Jenkins    : http://localhost:8080"
