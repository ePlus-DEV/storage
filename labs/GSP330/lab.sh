#!/bin/bash
set -e

# =========================
# Colors
# =========================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}====================================================${NC}"
echo -e "${GREEN} Implement DevOps Workflows in Google Cloud: Challenge Lab - GSP330 - ePlus.DEV${NC}"
echo -e "${CYAN}====================================================${NC}"

# =========================
# Variables
# =========================
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REPO_NAME="sample-app"
AR_REPO="my-repository"
CLUSTER="hello-cluster"
IMAGE_BASE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${REPO_NAME}"

echo -e "${YELLOW}Project ID:${NC} $PROJECT_ID"
echo -e "${YELLOW}Region:${NC} $REGION"
echo -e "${YELLOW}Zone:${NC} $ZONE"
echo -e "${YELLOW}Image:${NC} $IMAGE_BASE"

# =========================
# Task 1: Enable APIs
# =========================
echo -e "${CYAN}Enabling required APIs...${NC}"
gcloud services enable \
  container.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  sourcerepo.googleapis.com

echo -e "${CYAN}Granting Cloud Build Kubernetes Developer role...${NC}"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/container.developer" \
  --quiet

# Some labs also need this for image pull/deploy
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/artifactregistry.writer" \
  --quiet || true

# =========================
# Artifact Registry
# =========================
echo -e "${CYAN}Creating Artifact Registry repository...${NC}"
gcloud artifacts repositories create "$AR_REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker repository for sample app" \
  --quiet || echo -e "${YELLOW}Artifact Registry repo already exists, skipping.${NC}"

gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# =========================
# GKE Cluster
# =========================
echo -e "${CYAN}Creating GKE cluster. This may take several minutes...${NC}"
gcloud container clusters create "$CLUSTER" \
  --zone="$ZONE" \
  --release-channel=regular \
  --num-nodes=3 \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=6 \
  --quiet || echo -e "${YELLOW}Cluster already exists, skipping create.${NC}"

gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE"

echo -e "${CYAN}Creating namespaces...${NC}"
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

# =========================
# GitHub CLI
# =========================
if ! command -v gh >/dev/null 2>&1; then
  echo -e "${CYAN}Installing GitHub CLI...${NC}"
  curl -sS https://webi.sh/gh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

echo -e "${YELLOW}Login GitHub if not logged in.${NC}"
if ! gh auth status >/dev/null 2>&1; then
  gh auth login
fi

GITHUB_USERNAME=$(gh api user -q ".login")
USER_EMAIL=$(gh api user -q ".email")

if [ -z "$USER_EMAIL" ] || [ "$USER_EMAIL" = "null" ]; then
  USER_EMAIL="${GITHUB_USERNAME}@users.noreply.github.com"
fi

git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$USER_EMAIL"

echo -e "${GREEN}GitHub user:${NC} $GITHUB_USERNAME"
echo -e "${GREEN}Git email:${NC} $USER_EMAIL"

# =========================
# Task 2: GitHub repo + sample code
# =========================
cd ~

echo -e "${CYAN}Creating GitHub repository sample-app...${NC}"
gh repo create "$REPO_NAME" --public --confirm || echo -e "${YELLOW}GitHub repo already exists, continuing.${NC}"

rm -rf "$REPO_NAME"

echo -e "${CYAN}Cloning repository...${NC}"
git clone "https://github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
cd "$REPO_NAME"

echo -e "${CYAN}Copying sample code...${NC}"
gsutil -m cp -r gs://spls/gsp330/sample-app/* .

# Replace region and zone placeholders
for file in cloudbuild-dev.yaml cloudbuild.yaml; do
  sed -i "s/<your-region>/${REGION}/g" "$file"
  sed -i "s/<your-zone>/${ZONE}/g" "$file"
done

# Ensure master branch exists
git checkout -B master

git add .
git commit -m "Initial sample app code" || true
git push -u origin master

# Create dev branch
git checkout -B dev
git push -u origin dev

echo -e "${GREEN}Repository and branches created.${NC}"

# =========================
# Task 3: Cloud Build Triggers
# =========================
echo -e "${CYAN}Trying to create Cloud Build triggers...${NC}"
echo -e "${YELLOW}If this fails, connect GitHub App manually in Cloud Build UI, then rerun this script from this section or create triggers manually.${NC}"

gcloud builds triggers create github \
  --name="sample-app-prod-deploy" \
  --repo-owner="$GITHUB_USERNAME" \
  --repo-name="$REPO_NAME" \
  --branch-pattern="^master$" \
  --build-config="cloudbuild.yaml" \
  --quiet || true

gcloud builds triggers create github \
  --name="sample-app-dev-deploy" \
  --repo-owner="$GITHUB_USERNAME" \
  --repo-name="$REPO_NAME" \
  --branch-pattern="^dev$" \
  --build-config="cloudbuild-dev.yaml" \
  --quiet || true

echo -e "${YELLOW}Important:${NC} Check Task 3 progress. If not completed, create triggers manually:"
echo "1. Cloud Build > Triggers > Create Trigger"
echo "2. Name: sample-app-prod-deploy"
echo "3. Event: Push to branch"
echo "4. Source: GitHub Cloud Build GitHub App > sample-app"
echo "5. Branch: ^master$"
echo "6. Config file: cloudbuild.yaml"
echo ""
echo "Then create:"
echo "Name: sample-app-dev-deploy"
echo "Branch: ^dev$"
echo "Config file: cloudbuild-dev.yaml"

# =========================
# Helper functions
# =========================
patch_version_files() {
  local ENV_NAME=$1
  local VERSION=$2
  local CB_FILE=$3
  local DEPLOY_FILE="${ENV_NAME}/deployment.yaml"

  echo -e "${CYAN}Patching ${ENV_NAME} files to ${VERSION}...${NC}"

  sed -i "s/<version>/${VERSION}/g" "$CB_FILE"
  sed -i "s/:v[0-9]\+\.[0-9]\+/:${VERSION}/g" "$CB_FILE"

  sed -i "s|<todo>|${IMAGE_BASE}:${VERSION}|g" "$DEPLOY_FILE"
  sed -i "s|PROJECT_ID|${PROJECT_ID}|g" "$DEPLOY_FILE"
  sed -i "s|gcr.io/${PROJECT_ID}/${REPO_NAME}:v[0-9]\+\.[0-9]\+|${IMAGE_BASE}:${VERSION}|g" "$DEPLOY_FILE"
  sed -i "s|${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${REPO_NAME}:v[0-9]\+\.[0-9]\+|${IMAGE_BASE}:${VERSION}|g" "$DEPLOY_FILE"
}

add_red_handler() {
  if grep -q "func redHandler" main.go; then
    echo -e "${YELLOW}redHandler already exists, skipping.${NC}"
    return
  fi

  echo -e "${CYAN}Adding /red endpoint to main.go...${NC}"

  python3 - <<'PY'
from pathlib import Path

p = Path("main.go")
s = p.read_text()

old = '''func main() {
\thttp.HandleFunc("/blue", blueHandler)
\thttp.ListenAndServe(":8080", nil)
}'''

new = '''func main() {
\thttp.HandleFunc("/blue", blueHandler)
\thttp.HandleFunc("/red", redHandler)
\thttp.ListenAndServe(":8080", nil)
}'''

if old in s:
    s = s.replace(old, new)
else:
    # safer fallback
    s = s.replace('http.HandleFunc("/blue", blueHandler)', 'http.HandleFunc("/blue", blueHandler)\n\thttp.HandleFunc("/red", redHandler)')

handler = r'''
func redHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}
'''

s = s.rstrip() + "\n\n" + handler + "\n"
p.write_text(s)
PY
}

wait_for_builds() {
  echo -e "${YELLOW}Waiting briefly for Cloud Build trigger to start...${NC}"
  sleep 20
  echo -e "${CYAN}Recent builds:${NC}"
  gcloud builds list --limit=5
}

# =========================
# Task 4: Deploy v1.0 dev
# =========================
echo -e "${CYAN}Deploying DEV v1.0...${NC}"
git checkout dev

patch_version_files "dev" "v1.0" "cloudbuild-dev.yaml"

git add .
git commit -m "Deploy dev v1.0" || true
git push origin dev

wait_for_builds

# Manual fallback build if trigger did not run
echo -e "${YELLOW}Submitting dev build manually as fallback...${NC}"
gcloud builds submit --config cloudbuild-dev.yaml .

kubectl rollout status deployment/development-deployment -n dev --timeout=180s || true

echo -e "${CYAN}Exposing dev service...${NC}"
kubectl expose deployment development-deployment \
  --name=dev-deployment-service \
  --type=LoadBalancer \
  --port=8080 \
  --target-port=8080 \
  -n dev \
  --dry-run=client -o yaml | kubectl apply -f -

# =========================
# Task 4: Deploy v1.0 prod
# =========================
echo -e "${CYAN}Deploying PROD v1.0...${NC}"
git checkout master

patch_version_files "prod" "v1.0" "cloudbuild.yaml"

git add .
git commit -m "Deploy prod v1.0" || true
git push origin master

wait_for_builds

echo -e "${YELLOW}Submitting prod build manually as fallback...${NC}"
gcloud builds submit --config cloudbuild.yaml .

kubectl rollout status deployment/production-deployment -n prod --timeout=180s || true

echo -e "${CYAN}Exposing prod service...${NC}"
kubectl expose deployment production-deployment \
  --name=prod-deployment-service \
  --type=LoadBalancer \
  --port=8080 \
  --target-port=8080 \
  -n prod \
  --dry-run=client -o yaml | kubectl apply -f -

# =========================
# Task 5: Deploy v2.0 dev
# =========================
echo -e "${CYAN}Deploying DEV v2.0...${NC}"
git checkout dev
add_red_handler
patch_version_files "dev" "v2.0" "cloudbuild-dev.yaml"

git add .
git commit -m "Deploy dev v2.0 with red endpoint" || true
git push origin dev

wait_for_builds

echo -e "${YELLOW}Submitting dev v2.0 build manually as fallback...${NC}"
gcloud builds submit --config cloudbuild-dev.yaml .

kubectl rollout status deployment/development-deployment -n dev --timeout=180s || true

# =========================
# Task 5: Deploy v2.0 prod
# =========================
echo -e "${CYAN}Deploying PROD v2.0...${NC}"
git checkout master
add_red_handler
patch_version_files "prod" "v2.0" "cloudbuild.yaml"

git add .
git commit -m "Deploy prod v2.0 with red endpoint" || true
git push origin master

wait_for_builds

echo -e "${YELLOW}Submitting prod v2.0 build manually as fallback...${NC}"
gcloud builds submit --config cloudbuild.yaml .

kubectl rollout status deployment/production-deployment -n prod --timeout=180s || true

# =========================
# Service IPs
# =========================
echo -e "${CYAN}Waiting for LoadBalancer IPs...${NC}"
sleep 30

DEV_IP=$(kubectl get svc dev-deployment-service -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || true)
PROD_IP=$(kubectl get svc prod-deployment-service -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || true)

echo -e "${GREEN}DEV URL blue:${NC}  http://${DEV_IP}:8080/blue"
echo -e "${GREEN}DEV URL red:${NC}   http://${DEV_IP}:8080/red"
echo -e "${GREEN}PROD URL blue:${NC} http://${PROD_IP}:8080/blue"
echo -e "${GREEN}PROD URL red:${NC}  http://${PROD_IP}:8080/red"

echo ""
echo -e "${YELLOW}At this point, click Check my progress for Task 4 and Task 5 if needed.${NC}"

# =========================
# Task 6: Rollback production to v1.0 image
# =========================
echo -e "${CYAN}Rolling back production deployment to v1.0 image...${NC}"
kubectl set image deployment/production-deployment \
  -n prod \
  "*=${IMAGE_BASE}:v1.0" || true

kubectl rollout status deployment/production-deployment -n prod --timeout=180s || true

echo -e "${GREEN}Rollback completed.${NC}"
echo -e "${YELLOW}After rollback, this should return 404:${NC}"
echo "http://${PROD_IP}:8080/red"

echo ""
echo -e "${CYAN}Current deployments:${NC}"
kubectl get deploy -n dev -o wide
kubectl get deploy -n prod -o wide

echo ""
echo -e "${CYAN}Current services:${NC}"
kubectl get svc -n dev
kubectl get svc -n prod

echo -e "${GREEN}Done. Now click Check my progress for the remaining tasks.${NC}"