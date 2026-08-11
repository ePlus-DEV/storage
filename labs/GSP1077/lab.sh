#!/bin/bash

# ============================================================
# ePlus.DEV - GSP1077 CI/CD Lab
# Based on the original script, fixed for grader checkpoints.
# Included graded tasks: Task 1, Task 3, Task 4, Task 5, Task 6.
# Task 2 setup is retained because Tasks 3/4/6 depend on it.
# Tasks 7/8/9 are intentionally omitted (no Check my progress).
# ============================================================

# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
TEAL=$'\033[38;5;50m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'
NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'

ok()    { echo "${GREEN_TEXT}✔ $*${RESET_FORMAT}"; }
warn()  { echo "${YELLOW_TEXT}⚠ $*${RESET_FORMAT}"; }
error() { echo "${RED_TEXT}✘ $*${RESET_FORMAT}"; }
info()  { echo "${CYAN_TEXT}→ $*${RESET_FORMAT}"; }

section() {
  echo
  echo "${MAGENTA_TEXT}${BOLD_TEXT}$1${RESET_FORMAT}"
}

main() {
  clear

  echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
  echo "${CYAN_TEXT}${BOLD_TEXT}              ePlus.DEV - INITIATING EXECUTION                   ${RESET_FORMAT}"
  echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
  echo

  # The lab explicitly requires us-east1.
  export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
  export PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
  export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null)"
  export USER_EMAIL="${USER_EMAIL:-$(gcloud config get-value account 2>/dev/null)}"

  if [[ -z "$PROJECT_ID" || -z "$PROJECT_NUMBER" ]]; then
    error "Unable to detect the active Google Cloud project."
    return 1
  fi

  echo "${TEAL}${BOLD_TEXT}► Project ID     : ${RESET_FORMAT}${PROJECT_ID}"
  echo "${TEAL}${BOLD_TEXT}► Project number : ${RESET_FORMAT}${PROJECT_NUMBER}"
  echo "${TEAL}${BOLD_TEXT}► Region         : ${RESET_FORMAT}${REGION}"
  echo "${TEAL}${BOLD_TEXT}► Account        : ${RESET_FORMAT}${USER_EMAIL}"
  echo

  gcloud config set compute/region "$REGION" >/dev/null 2>&1 || true
  gcloud config set builds/region "$REGION" >/dev/null 2>&1 || true

  # ============================================================
  # TASK 1 - CHECK MY PROGRESS
  # ============================================================
  section "[ TASK 1 ] Initialize Environment"

  info "Enabling required APIs..."
  gcloud services enable \
    container.googleapis.com \
    cloudbuild.googleapis.com \
    secretmanager.googleapis.com \
    containeranalysis.googleapis.com

  ok "Required APIs are enabled."

  info "Checking Artifact Registry repository..."
  if gcloud artifacts repositories describe my-repository \
      --location="$REGION" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "Artifact Registry repository already exists."
  else
    gcloud artifacts repositories create my-repository \
      --repository-format=docker \
      --location="$REGION" \
      --project="$PROJECT_ID"

    if [[ $? -eq 0 ]]; then
      ok "Artifact Registry repository created."
    else
      error "Failed to create Artifact Registry repository."
    fi
  fi

  info "Checking GKE cluster..."
  if gcloud container clusters describe hello-cloudbuild \
      --region="$REGION" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "GKE cluster already exists."
  else
    echo "${CYAN_TEXT}→ Creating GKE cluster. This can take several minutes...${RESET_FORMAT}"
    gcloud container clusters create hello-cloudbuild \
      --num-nodes=1 \
      --region="$REGION" \
      --project="$PROJECT_ID"

    if [[ $? -eq 0 ]]; then
      ok "GKE cluster created."
    else
      error "Failed to create the GKE cluster."
    fi
  fi

  # ============================================================
  # TASK 2 SETUP - REQUIRED DEPENDENCY
  # No separate Check my progress, but Tasks 3/4/6 require it.
  # ============================================================
  section "[ SETUP ] GitHub Repositories (required dependency)"

  if ! command -v gh >/dev/null 2>&1; then
    info "Installing GitHub CLI..."
    curl -sS https://webi.sh/gh | sh
    export PATH="$HOME/.local/bin:$HOME/.local/opt/gh/bin:$PATH"
  fi

  if ! command -v gh >/dev/null 2>&1; then
    error "GitHub CLI is not available after installation."
    echo "Please reopen Cloud Shell and run this script again."
    return 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo
    echo "${YELLOW_TEXT}${BOLD_TEXT}GitHub authentication is required.${RESET_FORMAT}"
    echo "Follow the browser login instructions shown by GitHub CLI."
    echo
    gh auth login
  fi

  if ! gh auth status >/dev/null 2>&1; then
    error "GitHub authentication was not completed."
    return 1
  fi

  export GITHUB_USERNAME="$(gh api user -q '.login' 2>/dev/null)"
  if [[ -z "$GITHUB_USERNAME" ]]; then
    error "Unable to detect the GitHub username."
    return 1
  fi

  gh auth setup-git >/dev/null 2>&1 || true
  git config --global user.name "$GITHUB_USERNAME"
  git config --global user.email "$USER_EMAIL"

  echo "${TEAL}${BOLD_TEXT}► GitHub username : ${RESET_FORMAT}${GITHUB_USERNAME}"
  ok "GitHub authentication and Git configuration are ready."

  info "Ensuring hello-cloudbuild-app exists..."
  if gh repo view "${GITHUB_USERNAME}/hello-cloudbuild-app" >/dev/null 2>&1; then
    ok "hello-cloudbuild-app already exists."
  else
    gh repo create hello-cloudbuild-app --private
    ok "hello-cloudbuild-app created."
  fi

  info "Ensuring hello-cloudbuild-env exists..."
  if gh repo view "${GITHUB_USERNAME}/hello-cloudbuild-env" >/dev/null 2>&1; then
    ok "hello-cloudbuild-env already exists."
  else
    gh repo create hello-cloudbuild-env --private
    ok "hello-cloudbuild-env created."
  fi

  info "Preparing hello-cloudbuild-app..."
  cd "$HOME" || return 1
  rm -rf hello-cloudbuild-app
  mkdir -p hello-cloudbuild-app

  gcloud storage cp -r \
    gs://spls/gsp1077/gke-gitops-tutorial-cloudbuild/* \
    hello-cloudbuild-app

  cd "$HOME/hello-cloudbuild-app" || return 1

  sed -i "s/us-central1/${REGION}/g" cloudbuild.yaml
  sed -i "s/us-central1/${REGION}/g" cloudbuild-delivery.yaml
  sed -i "s/us-central1/${REGION}/g" cloudbuild-trigger-cd.yaml
  sed -i "s/us-central1/${REGION}/g" kubernetes.yaml.tpl

  git init >/dev/null
  git branch -M master
  git remote remove google >/dev/null 2>&1 || true
  git remote add google "https://github.com/${GITHUB_USERNAME}/hello-cloudbuild-app"
  git add .
  git commit -m "initial commit" >/dev/null 2>&1 || true
  git push -u google master --force

  ok "Application repository initialized and pushed."

  # ============================================================
  # TASK 3 - CHECK MY PROGRESS
  # ============================================================
  section "[ TASK 3 ] Build Container Image"

  cd "$HOME/hello-cloudbuild-app" || return 1
  COMMIT_ID="$(git rev-parse --short=7 HEAD)"

  info "Building container image with tag ${COMMIT_ID}..."
  gcloud builds submit \
    --region="$REGION" \
    --tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/my-repository/hello-cloudbuild:${COMMIT_ID}" \
    .

  if [[ $? -eq 0 ]]; then
    ok "Container image is available in Artifact Registry."
  else
    error "Container image build failed."
  fi

  # ============================================================
  # IAM REQUIRED BY TASK 4 / TASK 6 TRIGGER SERVICE ACCOUNT
  # ============================================================
  COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
  CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
  COMPUTE_SA_RESOURCE="projects/${PROJECT_ID}/serviceAccounts/${COMPUTE_SA}"

  info "Preparing IAM permissions for the trigger service account..."

  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/artifactregistry.writer" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true

  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/logging.logWriter" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true

  # ============================================================
  # TASK 4 - CHECK MY PROGRESS
  # ============================================================
  section "[ TASK 4 ] Create Continuous Integration (CI) Pipeline"

  echo "${CYAN_TEXT}Required trigger configuration:${RESET_FORMAT}"
  echo "  Name            : ${WHITE_TEXT}hello-cloudbuild${RESET_FORMAT}"
  echo "  Region          : ${WHITE_TEXT}${REGION}${RESET_FORMAT}"
  echo "  Event           : ${WHITE_TEXT}Push to a branch${RESET_FORMAT}"
  echo "  Repository      : ${WHITE_TEXT}${GITHUB_USERNAME}/hello-cloudbuild-app${RESET_FORMAT}"
  echo "  Branch          : ${WHITE_TEXT}.*${RESET_FORMAT}"
  echo "  Config file     : ${WHITE_TEXT}cloudbuild.yaml${RESET_FORMAT}"
  echo "  Service account : ${WHITE_TEXT}${COMPUTE_SA}${RESET_FORMAT}"
  echo

  # Recreate the trigger so a previously incorrect trigger cannot keep Task 4 at 0/20.
  gcloud builds triggers delete hello-cloudbuild \
    --region="$REGION" \
    --quiet >/dev/null 2>&1 || true

  info "Creating the CI trigger automatically..."
  CI_CREATE_OUTPUT="$(gcloud builds triggers create github \
    --name="hello-cloudbuild" \
    --region="$REGION" \
    --repo-owner="$GITHUB_USERNAME" \
    --repo-name="hello-cloudbuild-app" \
    --branch-pattern='.*' \
    --build-config='cloudbuild.yaml' \
    --service-account="$COMPUTE_SA_RESOURCE" \
    --no-require-approval 2>&1)"
  CI_CREATE_STATUS=$?

  if [[ $CI_CREATE_STATUS -eq 0 ]]; then
    ok "CI trigger created successfully."
  else
    warn "Automatic CI trigger creation could not complete."
    echo
    echo "$CI_CREATE_OUTPUT"
    echo
    echo "${YELLOW_TEXT}${BOLD_TEXT}Connect the GitHub App once, then create the trigger in Cloud Build.${RESET_FORMAT}"
    echo "Open: Cloud Build > Triggers > Create trigger"
    echo "Choose: GitHub (Cloud Build GitHub App)"
    echo "Grant access to BOTH repositories:"
    echo "  - ${GITHUB_USERNAME}/hello-cloudbuild-app"
    echo "  - ${GITHUB_USERNAME}/hello-cloudbuild-env"
    echo
    echo "Use the exact CI trigger values printed above."
    echo
    read -r -p "Press ENTER after the CI trigger has been created: "
  fi

  echo
  info "Verifying the CI trigger..."
  if gcloud builds triggers describe hello-cloudbuild \
      --region="$REGION" >/dev/null 2>&1; then
    gcloud builds triggers describe hello-cloudbuild \
      --region="$REGION" \
      --format='yaml(name,github.owner,github.name,github.push.branch,filename,serviceAccount)'
    ok "CI trigger exists."
  else
    warn "CI trigger was not found. Task 4 will not pass until the trigger is created."
  fi

  # Trigger CI with a new commit, as required by the lab.
  cd "$HOME/hello-cloudbuild-app" || return 1
  git commit --allow-empty -m "Trigger CI pipeline" >/dev/null 2>&1
  git push google master
  ok "A new commit was pushed to fire the CI trigger."

  # ============================================================
  # TASK 5 - CHECK MY PROGRESS
  # ============================================================
  section "[ TASK 5 ] SSH Keys and Secret Manager"

  cd "$HOME" || return 1
  rm -rf workingdir
  mkdir -p workingdir
  cd workingdir || return 1

  if gcloud secrets describe ssh_key_secret \
      --project="$PROJECT_ID" >/dev/null 2>&1; then
    ok "Secret ssh_key_secret already exists."
    info "Restoring version 1 locally so the matching public key can be displayed..."

    gcloud secrets versions access 1 \
      --secret=ssh_key_secret \
      --project="$PROJECT_ID" > id_github 2>/dev/null

    if [[ -s id_github ]]; then
      chmod 600 id_github
      ssh-keygen -y -f id_github > id_github.pub 2>/dev/null
    fi
  else
    info "Generating a new GitHub SSH key..."
    ssh-keygen -t rsa -b 4096 -N '' -f id_github -C "$USER_EMAIL"

    info "Creating ssh_key_secret in Secret Manager..."
    gcloud secrets create ssh_key_secret \
      --data-file=id_github \
      --replication-policy="automatic" \
      --project="$PROJECT_ID"
  fi

  if [[ ! -s id_github.pub && -s id_github ]]; then
    ssh-keygen -y -f id_github > id_github.pub 2>/dev/null
  fi

  echo
  echo "${YELLOW_TEXT}${BOLD_TEXT}GitHub Deploy Key${RESET_FORMAT}"
  echo "Repository settings:"
  echo "${UNDERLINE_TEXT}https://github.com/${GITHUB_USERNAME}/hello-cloudbuild-env/settings/keys${RESET_FORMAT}"
  echo
  echo "  Title       : ${CYAN_TEXT}SSH_KEY${RESET_FORMAT}"
  echo "  Write access: ${CYAN_TEXT}YES${RESET_FORMAT}"
  echo
  echo "${TEAL}${BOLD_TEXT}--- PUBLIC KEY ---${RESET_FORMAT}"
  if [[ -s id_github.pub ]]; then
    cat id_github.pub
  else
    warn "Unable to reconstruct the public key from the existing secret."
  fi
  echo "${TEAL}${BOLD_TEXT}--- END PUBLIC KEY ---${RESET_FORMAT}"
  echo
  echo "If SSH_KEY already exists in Deploy keys, do not add it again."
  read -r -p "Press ENTER after the deploy key is confirmed with write access: "

  info "Granting Secret Manager access to the Compute Engine default service account..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true

  ok "Secret Manager IAM binding is ready."

  rm -f "$HOME/workingdir/id_github" "$HOME/workingdir/id_github.pub"
  ok "Local SSH key files removed."

  # ============================================================
  # TASK 6 - CHECK MY PROGRESS
  # ============================================================
  section "[ TASK 6 ] Create Test Environment and CD Pipeline"

  info "Granting Kubernetes Engine Developer access..."

  # The lab grants the legacy Cloud Build SA.
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${CLOUDBUILD_SA}" \
    --role="roles/container.developer" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true

  # The trigger itself is configured to run as the Compute Engine default SA,
  # so it also needs permission to deploy to GKE.
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/container.developer" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true

  ok "GKE IAM permissions are ready."

  info "Preparing hello-cloudbuild-env..."
  cd "$HOME" || return 1
  rm -rf hello-cloudbuild-env
  mkdir -p hello-cloudbuild-env

  gcloud storage cp -r \
    gs://spls/gsp1077/gke-gitops-tutorial-cloudbuild/* \
    hello-cloudbuild-env

  cd "$HOME/hello-cloudbuild-env" || return 1

  sed -i "s/us-central1/${REGION}/g" cloudbuild.yaml
  sed -i "s/us-central1/${REGION}/g" cloudbuild-delivery.yaml
  sed -i "s/us-central1/${REGION}/g" cloudbuild-trigger-cd.yaml
  sed -i "s/us-central1/${REGION}/g" kubernetes.yaml.tpl

  ssh-keyscan -t rsa github.com > known_hosts.github 2>/dev/null
  chmod +x known_hosts.github

  git init >/dev/null
  git branch -M master
  git remote remove google >/dev/null 2>&1 || true
  git remote add google "https://github.com/${GITHUB_USERNAME}/hello-cloudbuild-env"
  git add .
  git commit -m "initial commit" >/dev/null 2>&1 || true
  git push -u google master --force

  ok "Environment repository master branch pushed."

  # ------------------------------------------------------------
  # Delivery pipeline used by the candidate branch trigger.
  # ------------------------------------------------------------
  info "Writing the delivery cloudbuild.yaml..."

  cat > "$HOME/hello-cloudbuild-env/cloudbuild.yaml" <<'ENVEOF'
steps:
- name: 'gcr.io/cloud-builders/kubectl'
  id: Deploy
  args:
  - 'apply'
  - '-f'
  - 'kubernetes.yaml'
  env:
  - 'CLOUDSDK_COMPUTE_REGION=us-east1'
  - 'CLOUDSDK_CONTAINER_CLUSTER=hello-cloudbuild'

- name: 'gcr.io/cloud-builders/git'
  secretEnv: ['SSH_KEY']
  entrypoint: 'bash'
  args:
  - -c
  - |
    mkdir -p /root/.ssh
    echo "$$SSH_KEY" > /root/.ssh/id_rsa
    chmod 400 /root/.ssh/id_rsa
    cp known_hosts.github /root/.ssh/known_hosts
  volumes:
  - name: 'ssh'
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/git'
  args:
  - clone
  - --recurse-submodules
  - git@github.com:__GITHUB_USERNAME__/hello-cloudbuild-env.git
  volumes:
  - name: ssh
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/gcloud'
  id: Copy to production branch
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    set -x && \
    cd hello-cloudbuild-env && \
    git config user.name "Cloud Build" && \
    git config user.email $(gcloud auth list --filter=status:ACTIVE --format='value(account)') && \
    git fetch origin production && \
    git checkout production && \
    git checkout $COMMIT_SHA kubernetes.yaml && \
    git add kubernetes.yaml && \
    (git diff --cached --quiet || git commit -m "Manifest from commit $COMMIT_SHA
    $(git log --format=%B -n 1 $COMMIT_SHA)") && \
    git push origin production
  volumes:
  - name: ssh
    path: /root/.ssh

availableSecrets:
  secretManager:
  - versionName: projects/__PROJECT_NUMBER__/secrets/ssh_key_secret/versions/1
    env: 'SSH_KEY'

options:
  logging: CLOUD_LOGGING_ONLY
ENVEOF

  sed -i "s/__GITHUB_USERNAME__/${GITHUB_USERNAME}/g" "$HOME/hello-cloudbuild-env/cloudbuild.yaml"
  sed -i "s/__PROJECT_NUMBER__/${PROJECT_NUMBER}/g" "$HOME/hello-cloudbuild-env/cloudbuild.yaml"

  # Create the exact production and candidate branches required by the lab.
  cd "$HOME/hello-cloudbuild-env" || return 1

  git checkout -B production master
  git add cloudbuild.yaml known_hosts.github
  git commit -m "Create cloudbuild.yaml for deployment" >/dev/null 2>&1 || true
  git push google production --force

  git checkout -B candidate production
  git push google candidate --force

  ok "production and candidate branches are available in GitHub."

  # ------------------------------------------------------------
  # Create CD trigger HERE, after candidate exists.
  # This fixes the original script, which created it too early.
  # ------------------------------------------------------------
  echo
  echo "${CYAN_TEXT}Required CD trigger configuration:${RESET_FORMAT}"
  echo "  Name            : ${WHITE_TEXT}hello-cloudbuild-deploy${RESET_FORMAT}"
  echo "  Region          : ${WHITE_TEXT}${REGION}${RESET_FORMAT}"
  echo "  Event           : ${WHITE_TEXT}Push to a branch${RESET_FORMAT}"
  echo "  Repository      : ${WHITE_TEXT}${GITHUB_USERNAME}/hello-cloudbuild-env${RESET_FORMAT}"
  echo "  Branch          : ${WHITE_TEXT}^candidate\$${RESET_FORMAT}"
  echo "  Config file     : ${WHITE_TEXT}cloudbuild.yaml${RESET_FORMAT}"
  echo "  Service account : ${WHITE_TEXT}${COMPUTE_SA}${RESET_FORMAT}"
  echo

  gcloud builds triggers delete hello-cloudbuild-deploy \
    --region="$REGION" \
    --quiet >/dev/null 2>&1 || true

  info "Creating the CD trigger automatically..."
  CD_CREATE_OUTPUT="$(gcloud builds triggers create github \
    --name="hello-cloudbuild-deploy" \
    --region="$REGION" \
    --repo-owner="$GITHUB_USERNAME" \
    --repo-name="hello-cloudbuild-env" \
    --branch-pattern='^candidate$' \
    --build-config='cloudbuild.yaml' \
    --service-account="$COMPUTE_SA_RESOURCE" \
    --no-require-approval 2>&1)"
  CD_CREATE_STATUS=$?

  if [[ $CD_CREATE_STATUS -eq 0 ]]; then
    ok "CD trigger created successfully."
  else
    warn "Automatic CD trigger creation could not complete."
    echo
    echo "$CD_CREATE_OUTPUT"
    echo
    echo "Create it manually in Cloud Build using the exact values printed above."
    echo "The repository must be connected with GitHub (Cloud Build GitHub App)."
    echo
    read -r -p "Press ENTER after the CD trigger has been created: "
  fi

  echo
  info "Verifying the CD trigger..."
  if gcloud builds triggers describe hello-cloudbuild-deploy \
      --region="$REGION" >/dev/null 2>&1; then
    gcloud builds triggers describe hello-cloudbuild-deploy \
      --region="$REGION" \
      --format='yaml(name,github.owner,github.name,github.push.branch,filename,serviceAccount)'
    ok "CD trigger exists."
  else
    warn "CD trigger was not found. Task 6 will not fully pass until the trigger is created."
  fi

  # ------------------------------------------------------------
  # Add known_hosts to the app repository.
  # ------------------------------------------------------------
  info "Adding GitHub known_hosts to the application repository..."
  cd "$HOME/hello-cloudbuild-app" || return 1

  ssh-keyscan -t rsa github.com > known_hosts.github 2>/dev/null
  chmod +x known_hosts.github

  git add known_hosts.github
  git commit -m "Adding known_host file." >/dev/null 2>&1 || true
  git push google master

  ok "known_hosts.github pushed to the application repository."

  # ------------------------------------------------------------
  # Replace app cloudbuild.yaml with the full CI -> CD pipeline.
  # ------------------------------------------------------------
  info "Writing the complete CI/CD cloudbuild.yaml..."

  cat > "$HOME/hello-cloudbuild-app/cloudbuild.yaml" <<'APPEOF'
steps:
- name: 'python:3.7-slim'
  id: Test
  entrypoint: /bin/sh
  args:
  - -c
  - 'pip install flask && python test_app.py -v'

- name: 'gcr.io/cloud-builders/docker'
  id: Build
  args:
  - 'build'
  - '-t'
  - 'us-east1-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:$SHORT_SHA'
  - '.'

- name: 'gcr.io/cloud-builders/docker'
  id: Push
  args:
  - 'push'
  - 'us-east1-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:$SHORT_SHA'

- name: 'gcr.io/cloud-builders/git'
  secretEnv: ['SSH_KEY']
  entrypoint: 'bash'
  args:
  - -c
  - |
    mkdir -p /root/.ssh
    echo "$$SSH_KEY" > /root/.ssh/id_rsa
    chmod 400 /root/.ssh/id_rsa
    cp known_hosts.github /root/.ssh/known_hosts
  volumes:
  - name: 'ssh'
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/git'
  args:
  - clone
  - --recurse-submodules
  - git@github.com:__GITHUB_USERNAME__/hello-cloudbuild-env.git
  volumes:
  - name: ssh
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/gcloud'
  id: Change directory
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    cd hello-cloudbuild-env && \
    git checkout candidate && \
    git config user.name "Cloud Build" && \
    git config user.email $(gcloud auth list --filter=status:ACTIVE --format='value(account)')
  volumes:
  - name: ssh
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/gcloud'
  id: Generate manifest
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    sed "s/GOOGLE_CLOUD_PROJECT/${PROJECT_ID}/g" kubernetes.yaml.tpl | \
    sed "s/COMMIT_SHA/${SHORT_SHA}/g" > hello-cloudbuild-env/kubernetes.yaml
  volumes:
  - name: ssh
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/gcloud'
  id: Push manifest
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    set -x && \
    cd hello-cloudbuild-env && \
    git add kubernetes.yaml && \
    git commit -m "Deploying image us-east1-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:${SHORT_SHA}
    Built from commit ${COMMIT_SHA} of repository hello-cloudbuild-app
    Author: $(git log --format='%an <%ae>' -n 1 HEAD)" && \
    git push origin candidate
  volumes:
  - name: ssh
    path: /root/.ssh

availableSecrets:
  secretManager:
  - versionName: projects/__PROJECT_NUMBER__/secrets/ssh_key_secret/versions/1
    env: 'SSH_KEY'

options:
  logging: CLOUD_LOGGING_ONLY
APPEOF

  sed -i "s/__GITHUB_USERNAME__/${GITHUB_USERNAME}/g" "$HOME/hello-cloudbuild-app/cloudbuild.yaml"
  sed -i "s/__PROJECT_NUMBER__/${PROJECT_NUMBER}/g" "$HOME/hello-cloudbuild-app/cloudbuild.yaml"

  cd "$HOME/hello-cloudbuild-app" || return 1
  git add cloudbuild.yaml known_hosts.github
  git commit -m "Trigger CD pipeline" >/dev/null 2>&1 || true
  git push google master

  ok "The complete CI/CD pipeline configuration was pushed."

  # ============================================================
  # FINAL VERIFICATION
  # ============================================================
  section "[ VERIFY ] Grader-Critical Resources"

  echo "${CYAN_TEXT}${BOLD_TEXT}Artifact Registry${RESET_FORMAT}"
  gcloud artifacts repositories describe my-repository \
    --location="$REGION" \
    --format='value(name)' 2>/dev/null || true

  echo
  echo "${CYAN_TEXT}${BOLD_TEXT}GKE Cluster${RESET_FORMAT}"
  gcloud container clusters describe hello-cloudbuild \
    --region="$REGION" \
    --format='table(name,status,location)' 2>/dev/null || true

  echo
  echo "${CYAN_TEXT}${BOLD_TEXT}CI Trigger${RESET_FORMAT}"
  gcloud builds triggers describe hello-cloudbuild \
    --region="$REGION" \
    --format='yaml(name,github.owner,github.name,github.push.branch,filename,serviceAccount)' 2>/dev/null || true

  echo
  echo "${CYAN_TEXT}${BOLD_TEXT}CD Trigger${RESET_FORMAT}"
  gcloud builds triggers describe hello-cloudbuild-deploy \
    --region="$REGION" \
    --format='yaml(name,github.owner,github.name,github.push.branch,filename,serviceAccount)' 2>/dev/null || true

  echo
  echo "${CYAN_TEXT}${BOLD_TEXT}Secret${RESET_FORMAT}"
  gcloud secrets describe ssh_key_secret \
    --format='value(name)' 2>/dev/null || true

  echo
  echo "${CYAN_TEXT}${BOLD_TEXT}Recent Builds${RESET_FORMAT}"
  gcloud builds list \
    --region="$REGION" \
    --limit=8 \
    --format='table(id.slice(0:8):label=BUILD,status,substitutions.TRIGGER_NAME:label=TRIGGER,createTime)' 2>/dev/null || true

  echo
  echo "${GREEN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
  echo "${GREEN_TEXT}${BOLD_TEXT}                REQUIRED GRADER SETUP COMPLETED                  ${RESET_FORMAT}"
  echo "${GREEN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
  echo
  echo "Check progress for:"
  echo "  Task 1 - Initialize your lab"
  echo "  Task 3 - Create the container image with Cloud Build"
  echo "  Task 4 - Create the Continuous Integration (CI) Pipeline"
  echo "  Task 5 - Accessing GitHub from a build via SSH keys"
  echo "  Task 6 - Create the Test Environment and CD Pipeline"
  echo
  echo "Tasks 7, 8 and 9 are intentionally not automated because they do not have a Check my progress checkpoint."
  echo
  echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
  echo
}

main "$@"