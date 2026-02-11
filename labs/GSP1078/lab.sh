#!/usr/bin/env bash
set -e

# ==========================================================
#  ePlus.DEV © Cloud Run Progressive Delivery (Canary)
# ==========================================================
# NOTE:
# - This script will PROMPT for a GitHub EMAIL
# - This email is used for:
#     + git config user.email
#     + git commit author
# - This is NOT a Google Cloud email
# ==========================================================

# ===== COLORS =====
BLACK=$(tput setaf 0); RED=$(tput setaf 1); GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6); WHITE=$(tput setaf 7)
BOLD=$(tput bold); RESET=$(tput sgr0)

banner () {
echo "${MAGENTA}${BOLD}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   ePlus.DEV © Cloud Run Progressive Delivery Lab"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "${RESET}"
}

info () { echo "${CYAN}${BOLD}[INFO]${RESET} $1"; }
ok   () { echo "${GREEN}${BOLD}[OK]${RESET}   $1"; }
warn () { echo "${YELLOW}${BOLD}[WARN]${RESET} $1"; }
err  () { echo "${RED}${BOLD}[ERROR]${RESET} $1"; }

pause () {
  read -p "$(echo -e "${MAGENTA}${BOLD}Press ENTER to continue...${RESET}")"
}

banner

# ==========================================================
# INPUT: GITHUB EMAIL
# ==========================================================
echo "${YELLOW}${BOLD}"
echo "GitHub EMAIL is required!"
echo "- This must be your GitHub account email"
echo "- Used to set git commit author"
echo "- Check at: GitHub → Settings → Emails"
echo "${RESET}"

while true; do
  read -p "👉 Enter your GitHub email: " USER_EMAIL
  if [[ "$USER_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    break
  fi
  err "Invalid email format. Please try again."
done

ok "GitHub Email set: $USER_EMAIL"

# ==========================================================
# GCP PROJECT INFO
# ==========================================================
info "Reading Google Cloud project information"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
[[ -z "$PROJECT_ID" ]] && err "No active GCP project configured" && exit 1

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")

gcloud config set compute/region "$REGION" >/dev/null

ok "PROJECT_ID=$PROJECT_ID"
ok "PROJECT_NUMBER=$PROJECT_NUMBER"
ok "REGION=$REGION"

# ==========================================================
# ENABLE REQUIRED APIS
# ==========================================================
info "Enabling required Google Cloud APIs"
gcloud services enable \
 cloudresourcemanager.googleapis.com \
 cloudbuild.googleapis.com \
 run.googleapis.com \
 containerregistry.googleapis.com \
 secretmanager.googleapis.com

# ==========================================================
# IAM PERMISSIONS
# ==========================================================
info "Granting Secret Manager permission to Cloud Build"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
 --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com" \
 --role="roles/secretmanager.admin" >/dev/null

# ==========================================================
# GITHUB CLI SETUP
# ==========================================================
info "Installing GitHub CLI (gh)"
command -v gh >/dev/null || curl -sS https://webi.sh/gh | sh
export PATH="$HOME/.local/bin:$PATH"

warn "Please login to GitHub CLI"
gh auth login
pause

GITHUB_USERNAME=$(gh api user -q ".login")

git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$USER_EMAIL"

ok "GitHub user: $GITHUB_USERNAME"

# ==========================================================
# REPOSITORY SETUP
# ==========================================================
info "Creating GitHub repository"
gh repo create cloudrun-progression --private || true

git clone https://github.com/GoogleCloudPlatform/training-data-analyst
mkdir cloudrun-progression
cp -r training-data-analyst/self-paced-labs/cloud-run/canary/* cloudrun-progression
cd cloudrun-progression

sed -i "s/us-central1/$REGION/g" *.yaml

sed -e "s/PROJECT/$PROJECT_ID/g" -e "s/NUMBER/$PROJECT_NUMBER/g" \
 branch-trigger.json-tmpl > branch-trigger.json

sed -e "s/PROJECT/$PROJECT_ID/g" -e "s/NUMBER/$PROJECT_NUMBER/g" \
 master-trigger.json-tmpl > master-trigger.json

sed -e "s/PROJECT/$PROJECT_ID/g" -e "s/NUMBER/$PROJECT_NUMBER/g" \
 tag-trigger.json-tmpl > tag-trigger.json

git init
git branch -m master
git remote add gcp "https://github.com/$GITHUB_USERNAME/cloudrun-progression"
git add . && git commit -m "initial commit"
git push gcp master

# ==========================================================
# DEPLOY CLOUD RUN
# ==========================================================
info "Building and deploying Cloud Run service"
gcloud builds submit --tag "gcr.io/$PROJECT_ID/hello-cloudrun"

gcloud run deploy hello-cloudrun \
 --image "gcr.io/$PROJECT_ID/hello-cloudrun" \
 --region "$REGION" \
 --platform managed \
 --tag=prod -q

PROD_URL=$(gcloud run services describe hello-cloudrun \
 --region "$REGION" --format="value(status.url)")

ok "PROD_URL=$PROD_URL"

# ==========================================================
# CLOUD BUILD GITHUB CONNECTION
# ==========================================================
info "Creating Cloud Build GitHub connection"
gcloud builds connections create github cloud-build-connection \
 --region="$REGION" || true

warn "Install Cloud Build GitHub App and select repository: cloudrun-progression"
pause

gcloud builds repositories create cloudrun-progression \
 --remote-uri="https://github.com/$GITHUB_USERNAME/cloudrun-progression.git" \
 --connection="cloud-build-connection" \
 --region="$REGION" || true

# ==========================================================
# CLOUD BUILD TRIGGERS
# ==========================================================
info "Creating Cloud Build triggers"

REPO="projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression"

gcloud builds triggers create github --name=branch \
 --repository="$REPO" \
 --build-config=branch-cloudbuild.yaml \
 --branch-pattern='[^(?!.*master)].*' \
 --region="$REGION" || true

gcloud builds triggers create github --name=master \
 --repository="$REPO" \
 --build-config=master-cloudbuild.yaml \
 --branch-pattern=master \
 --region="$REGION" || true

gcloud builds triggers create github --name=tag \
 --repository="$REPO" \
 --build-config=tag-cloudbuild.yaml \
 --tag-pattern='.*' \
 --region="$REGION" || true

# ==========================================================
# FEATURE → CANARY → RELEASE
# ==========================================================
info "Running feature → canary → release flow"

git checkout -b new-feature-1
sed -i "s/v1.0/v1.1/g" app.py
git commit -am "v1.1"
git push gcp new-feature-1

git checkout master
git merge new-feature-1
git push gcp master

git tag 1.1
git push gcp 1.1

banner
ok "LAB COMPLETED SUCCESSFULLY – ePlus.DEV ©"