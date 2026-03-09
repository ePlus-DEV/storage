cat > full_cloud_code_gke_lab.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Google Cloud Artifact Registry + GKE + Cloud Code Lab
#  Copyright (c) 2026 EPlus Dev. All rights reserved.
# ============================================================

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
fail()    { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

banner() {
  echo -e "${MAGENTA}${BOLD}"
  echo "=================================================================="
  echo "      Google Cloud Artifact Registry + GKE Full Lab Script       "
  echo "=================================================================="
  echo -e "${NC}${BLUE}Copyright (c) 2026 EPlus Dev. All rights reserved.${NC}"
  echo -e "${WHITE}Theme:${NC} ${GREEN}EPlus Color Edition${NC}"
  echo
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

create_repo_if_missing() {
  local repo_name="$1"
  local repo_format="$2"
  local repo_location="$3"
  local repo_desc="$4"

  if gcloud artifacts repositories describe "$repo_name" --location="$repo_location" >/dev/null 2>&1; then
    success "Artifact Registry repository '$repo_name' already exists."
  else
    info "Creating Artifact Registry repository '$repo_name'..."
    gcloud artifacts repositories create "$repo_name" \
      --repository-format="$repo_format" \
      --location="$repo_location" \
      --description="$repo_desc"
    success "Repository '$repo_name' created."
  fi
}

create_cluster_if_missing() {
  local cluster_name="$1"
  local cluster_zone="$2"

  if gcloud container clusters describe "$cluster_name" --zone="$cluster_zone" >/dev/null 2>&1; then
    success "GKE cluster '$cluster_name' already exists."
  else
    info "Creating GKE cluster '$cluster_name'..."
    gcloud container clusters create "$cluster_name" --zone="$cluster_zone"
    success "GKE cluster '$cluster_name' created."
  fi
}

install_skaffold_if_missing() {
  if command -v skaffold >/dev/null 2>&1; then
    success "skaffold is already installed."
  else
    info "Installing skaffold..."
    curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
    chmod +x skaffold
    sudo mv skaffold /usr/local/bin/
    success "skaffold installed successfully."
  fi
}

patch_pom_xml() {
  local pom_file="pom.xml"

  [[ -f "$pom_file" ]] || fail "pom.xml not found in $(pwd)"

  cp "$pom_file" "${pom_file}.bak"

  python3 <<PY
from pathlib import Path

pom = Path("pom.xml")
content = pom.read_text()

repo_url = "artifactregistry://us-east1-maven.pkg.dev/${PROJECT_ID}/container-dev-java-repo"

distribution = f"""
 <distributionManagement>
   <snapshotRepository>
     <id>artifact-registry</id>
     <url>{repo_url}</url>
   </snapshotRepository>
   <repository>
     <id>artifact-registry</id>
     <url>{repo_url}</url>
   </repository>
 </distributionManagement>
"""

repositories = f"""
 <repositories>
   <repository>
     <id>artifact-registry</id>
     <url>{repo_url}</url>
     <releases>
       <enabled>true</enabled>
     </releases>
     <snapshots>
       <enabled>true</enabled>
     </snapshots>
   </repository>
 </repositories>
"""

extension_block = """
   <extensions>
     <extension>
       <groupId>com.google.cloud.artifactregistry</groupId>
       <artifactId>artifactregistry-maven-wagon</artifactId>
       <version>2.1.0</version>
     </extension>
   </extensions>
"""

if "<distributionManagement>" not in content:
    content = content.replace("<parent>", distribution + "\n <parent>", 1)

if "<repositories>" not in content:
    content = content.replace("<parent>", repositories + "\n <parent>", 1)

if "<extensions>" not in content:
    content = content.replace("  </plugins>", "  </plugins>\n" + extension_block, 1)

pom.write_text(content)
PY

  success "pom.xml patched for Artifact Registry Maven."
}

patch_app_text() {
  local controller_file="src/main/java/cloudcode/helloworld/web/HelloWorldController.java"

  [[ -f "$controller_file" ]] || fail "HelloWorldController.java not found."

  if grep -q "It's updated!" "$controller_file"; then
    success "Application text is already updated."
  else
    sed -i "s/It's running!/It's updated!/g" "$controller_file"
    success "Application text changed from 'It's running!' to 'It's updated!'."
  fi
}

prepare_cloud_code_launch_config() {
  mkdir -p .vscode
  cat > .vscode/launch.json <<JSON
{
  "configurations": [
    {
      "name": "Run on Kubernetes",
      "type": "cloudcode.kubernetes",
      "request": "launch",
      "skaffoldConfig": "\${workspaceFolder}/skaffold.yaml",
      "watch": true,
      "imageRegistry": "${IMAGE_REPO}",
      "debug": false
    }
  ]
}
JSON
  success ".vscode/launch.json prepared for Cloud Code."
}

main() {
  banner

  require_command gcloud
  require_command git
  require_command docker
  require_command kubectl
  require_command python3
  require_command mvn
  require_command curl

  export PROJECT_ID
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

  [[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || fail "Unable to detect PROJECT_ID from gcloud config."

  export PROJECT_NUMBER
  PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

  export REGION="us-east1"
  export ZONE="us-east1-c"
  export CLUSTER_NAME="container-dev-cluster"
  export DOCKER_REPO="container-dev-repo"
  export MAVEN_REPO="container-dev-java-repo"
  export IMAGE_REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/${DOCKER_REPO}"
  export IMAGE_TAG="tag1"
  export IMAGE_URI="${IMAGE_REPO}/java-hello-world:${IMAGE_TAG}"

  info "PROJECT_ID      = ${PROJECT_ID}"
  info "PROJECT_NUMBER  = ${PROJECT_NUMBER}"
  info "REGION          = ${REGION}"
  info "ZONE            = ${ZONE}"
  info "CLUSTER_NAME    = ${CLUSTER_NAME}"
  info "IMAGE_REPO      = ${IMAGE_REPO}"

  info "Setting compute region..."
  gcloud config set compute/region "$REGION" >/dev/null
  success "Compute region set to $REGION."

  info "Enabling required Google Cloud services..."
  gcloud services enable \
    cloudresourcemanager.googleapis.com \
    container.googleapis.com \
    artifactregistry.googleapis.com \
    containerregistry.googleapis.com \
    containerscanning.googleapis.com
  success "Required services enabled."

  cd "$HOME"

  if [[ -d "$HOME/cloud-code-samples/.git" ]]; then
    info "Repository already exists. Pulling latest changes..."
    cd "$HOME/cloud-code-samples"
    git pull
  else
    info "Cloning sample repository..."
    git clone https://github.com/GoogleCloudPlatform/cloud-code-samples/
    cd "$HOME/cloud-code-samples"
  fi
  success "Sample repository is ready."

  create_cluster_if_missing "$CLUSTER_NAME" "$ZONE"

  create_repo_if_missing \
    "$DOCKER_REPO" \
    "docker" \
    "$REGION" \
    "Docker repository for Container Dev Workshop"

  info "Configuring Docker authentication for Artifact Registry..."
  printf 'y\n' | gcloud auth configure-docker "${REGION}-docker.pkg.dev" >/dev/null
  success "Docker authentication configured."

  cd "$HOME/cloud-code-samples/java/java-hello-world"

  info "Building Docker image..."
  docker build -t "$IMAGE_URI" .
  success "Docker image built: $IMAGE_URI"

  info "Pushing Docker image..."
  docker push "$IMAGE_URI"
  success "Docker image pushed successfully."

  create_repo_if_missing \
    "$MAVEN_REPO" \
    "maven" \
    "$REGION" \
    "Java package repository for Container Dev Workshop"

  patch_pom_xml

  info "Getting GKE credentials..."
  gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE"
  success "GKE credentials configured."

  install_skaffold_if_missing
  prepare_cloud_code_launch_config

  info "Deploying application to GKE using skaffold..."
  skaffold run --default-repo="${IMAGE_REPO}"
  success "Initial deployment completed."

  info "Checking Kubernetes resources..."
  kubectl get pods
  kubectl get svc

  info "Patching application text for the updated version..."
  patch_app_text

  info "Redeploying updated application..."
  skaffold run --default-repo="${IMAGE_REPO}"
  success "Updated application redeployed."

  info "Waiting for rollout..."
  kubectl rollout status deployment/java-hello-world --timeout=300s || true

  echo
  echo -e "${MAGENTA}${BOLD}==================== OPTIONAL MANUAL STEP ====================${NC}"
  echo -e "${YELLOW}If the lab strictly requires Cloud Code UI interaction, run:${NC}"
  echo -e "${WHITE}  cd ~/cloud-code-samples${NC}"
  echo -e "${WHITE}  cloudshell workspace .${NC}"
  echo
  echo -e "${YELLOW}Then in Cloud Shell Editor:${NC}"
  echo -e "${WHITE}  1. Open Cloud Code${NC}"
  echo -e "${WHITE}  2. Select the current project${NC}"
  echo -e "${WHITE}  3. Run 'Cloud Code: Run on Kubernetes'${NC}"
  echo -e "${WHITE}  4. Choose: cloud-code-samples/java/java-hello-world/skaffold.yaml${NC}"
  echo -e "${WHITE}  5. Use image repository: ${IMAGE_REPO}${NC}"
  echo -e "${MAGENTA}${BOLD}==============================================================${NC}"
  echo

  echo -e "${BLUE}${BOLD}For Maven deployment later, run manually:${NC}"
  echo -e "${WHITE}gcloud auth login --update-adc${NC}"
  echo -e "${WHITE}cd ~/cloud-code-samples/java/java-hello-world${NC}"
  echo -e "${WHITE}mvn deploy${NC}"
  echo

  success "Full automation script completed."
  echo -e "${GREEN}${BOLD}EPlus Dev Color Edition finished successfully.${NC}"
}

main "$@"
EOF

chmod +x full_cloud_code_gke_lab.sh
./full_cloud_code_gke_lab.sh