#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
#  ePlus.DEV © Cloud Run Progressive Delivery (Canary) — PASS LAB (ZERO INPUT)
#  - NO prompt for GitHub email (auto uses noreply)
#  - Auto-run all lab steps
#  - ONLY pauses for required manual web actions:
#      1) GitHub CLI login (gh auth login)
#      2) Cloud Build GitHub App install via actionUri
#  - Shows LIVE Cloud Build progress (not "frozen")
#  - Auto waits for builds to finish before next step
#  - Region fixed: europe-west4 (lab requirement)
# ==========================================================

# ---------------- COLORS ----------------
BLACK=$(tput setaf 0 || true); RED=$(tput setaf 1 || true); GREEN=$(tput setaf 2 || true)
YELLOW=$(tput setaf 3 || true); BLUE=$(tput setaf 4 || true); MAGENTA=$(tput setaf 5 || true)
CYAN=$(tput setaf 6 || true); WHITE=$(tput setaf 7 || true)
BOLD=$(tput bold || true); RESET=$(tput sgr0 || true)
BG_RED=$(tput setab 1 || true)

banner () {
  echo "${MAGENTA}${BOLD}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   ePlus.DEV © Cloud Run Progressive Delivery (Canary) — PASS LAB"
  echo "   (ZERO INPUT • pauses only for required web actions)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "${RESET}"
}
info () { echo "${CYAN}${BOLD}[INFO]${RESET} $*"; }
ok   () { echo "${GREEN}${BOLD}[OK]${RESET}   $*"; }
warn () { echo "${YELLOW}${BOLD}[WARN]${RESET} $*"; }
die  () { echo "${RED}${BOLD}[ERROR]${RESET} $*"; exit 1; }

pause_enter () { read -r -p "$(echo -e "${MAGENTA}${BOLD}Press ENTER to continue...${RESET}")"; }

critical () {
  local title="$1"; shift
  echo
  echo "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo "${BG_RED}${WHITE}${BOLD}  ⚠  ${title}  ⚠  ${RESET}"
  echo "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  while (($#)); do
    echo "${YELLOW}${BOLD}- $1${RESET}"
    shift
  done
  echo "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo
}

need_cmd () { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# Accept YES/yes/Y/y
confirm_yes () {
  local prompt="${1:-Type YES (or Y) to continue: }"
  local x=""
  while true; do
    read -r -p "$prompt" x
    x="$(echo "$x" | tr '[:upper:]' '[:lower:]')"
    [[ "$x" == "yes" || "$x" == "y" ]] && break
    echo "${YELLOW}${BOLD}Please type YES or Y to continue.${RESET}"
  done
}

# ---------------- Cloud Build Live Monitor ----------------
wait_builds_idle () {
  local delay=5
  echo
  echo "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo "${BLUE}${BOLD}⏳ Monitoring Cloud Build Progress...${RESET}"
  echo "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  while true; do
    local running last
    running="$(gcloud builds list --ongoing --format="value(id)" 2>/dev/null | wc -l | tr -d ' ')"
    last="$(gcloud builds list --limit=1 --format="value(id,status,createTime)" 2>/dev/null || true)"

    clear || true
    banner
    echo "${CYAN}${BOLD}Cloud Build Status Monitor${RESET}"
    echo
    echo "${YELLOW}${BOLD}Running Builds:${RESET} ${running}"
    echo
    echo "${WHITE}${BOLD}Latest Build:${RESET}"
    echo "${last}"
    echo
    echo "${BLUE}${BOLD}Refreshing every ${delay}s... (Cloud Build → History for logs)${RESET}"

    if [[ "${running}" == "0" ]]; then
      echo
      echo "${GREEN}${BOLD}✔ All builds completed.${RESET}"
      break
    fi

    sleep "${delay}"
  done
}

# Wait until a specific Cloud Run traffic tag URL exists
wait_tag_url () {
  local tag="$1"
  local tries=120     # ~10 minutes
  local delay=5
  local url=""

  info "Waiting for Cloud Run tag '${tag}' URL..."
  for ((i=1; i<=tries; i++)); do
    url="$(gcloud run services describe hello-cloudrun --platform managed --region "$REGION" --format=json \
      | jq -r --arg t "$tag" '.status.traffic[]? | select(.tag==$t) | .url' 2>/dev/null || true)"
    if [[ -n "${url}" && "${url}" != "null" ]]; then
      ok "Tag '${tag}' URL: ${url}"
      echo "${url}"
      return 0
    fi
    sleep "${delay}"
  done

  warn "Tag '${tag}' not visible yet. (Build may still be running)"
  echo ""
  return 0
}

# ---------------- START ----------------
clear || true
banner

need_cmd gcloud
need_cmd git
need_cmd jq
need_cmd curl

# ==========================================================
# TASK 1: env + APIs + IAM
# ==========================================================
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]] && die "No active project. Run: gcloud config set project <PROJECT_ID>"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
REGION="europe-west4" # lab requirement
gcloud config set compute/region "$REGION" >/dev/null

ok "PROJECT_ID=$PROJECT_ID"
ok "PROJECT_NUMBER=$PROJECT_NUMBER"
ok "REGION=$REGION"

info "Enable required APIs"
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  container.googleapis.com \
  cloudbuild.googleapis.com \
  containerregistry.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com
ok "APIs enabled"

info "Grant Secret Manager Admin to Cloud Build Service Agent"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com" \
  --role="roles/secretmanager.admin" >/dev/null
ok "IAM done"

# ==========================================================
# GitHub CLI (manual login only if needed)
# ==========================================================
info "Install gh if missing"
if ! command -v gh >/dev/null 2>&1; then
  curl -sS https://webi.sh/gh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
need_cmd gh

if ! gh auth status >/dev/null 2>&1; then
  critical "MANUAL ACTION #1 — GitHub CLI Login" \
    "Choose: Login with a web browser" \
    "Copy one-time code + open URL from terminal" \
    "Authorize, then return here"
  gh auth login
  pause_enter
fi

GITHUB_USERNAME="$(gh api user -q ".login")"
ok "GitHub user: $GITHUB_USERNAME"

# Auto noreply email (no prompt)
USER_EMAIL="${GITHUB_USERNAME}@users.noreply.github.com"
git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$USER_EMAIL"
git config --global credential.helper gcloud.sh
git config --global init.defaultBranch master
ok "Git configured (email: ${USER_EMAIL})"

# ==========================================================
# TASK 1: repo prep
# ==========================================================
REPO_NAME="cloudrun-progression"
WORKDIR="$HOME"

info "Create GitHub repo (private): $REPO_NAME"
gh repo create "$REPO_NAME" --private >/dev/null 2>&1 || warn "Repo exists, continue."

info "Clean workspace for rerun"
cd "$WORKDIR"
rm -rf training-data-analyst "$REPO_NAME"

info "Clone sample repo"
git clone https://github.com/GoogleCloudPlatform/training-data-analyst

info "Copy lab source"
mkdir -p "$REPO_NAME"
cp -r "$WORKDIR/training-data-analyst/self-paced-labs/cloud-run/canary/"* "$WORKDIR/$REPO_NAME"
cd "$WORKDIR/$REPO_NAME"

info "Fix REGION in YAMLs"
for f in branch-cloudbuild.yaml master-cloudbuild.yaml tag-cloudbuild.yaml; do
  [[ -f "$f" ]] || continue
  sed -i "s/us-central1/${REGION}/g" "$f" || true
  sed -i "s/europe-west1/${REGION}/g" "$f" || true
  sed -i "s/REGION: us-central1/REGION: ${REGION}/g" "$f" || true
  sed -i "s/REGION: europe-west1/REGION: ${REGION}/g" "$f" || true
done

info "Render trigger JSONs"
sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" branch-trigger.json-tmpl > branch-trigger.json
sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" master-trigger.json-tmpl > master-trigger.json
sed -e "s/PROJECT/${PROJECT_ID}/g" -e "s/NUMBER/${PROJECT_NUMBER}/g" tag-trigger.json-tmpl > tag-trigger.json

info "Init git + push master"
git init >/dev/null 2>&1 || true
git branch -M master
git remote remove gcp >/dev/null 2>&1 || true
git remote add gcp "https://github.com/${GITHUB_USERNAME}/${REPO_NAME}"
git add .
git commit -m "initial commit" >/dev/null 2>&1 || warn "Nothing to commit."
git push -u gcp master
ok "Pushed master: https://github.com/${GITHUB_USERNAME}/${REPO_NAME}"

# ==========================================================
# TASK 2: Cloud Run build + deploy
# ==========================================================
info "Build image"
gcloud builds submit --tag "gcr.io/${PROJECT_ID}/hello-cloudrun"

info "Deploy Cloud Run (prod tag)"
gcloud run deploy hello-cloudrun \
  --image "gcr.io/${PROJECT_ID}/hello-cloudrun" \
  --platform managed \
  --region "${REGION}" \
  --tag=prod -q

PROD_URL="$(gcloud run services describe hello-cloudrun --platform managed --region "${REGION}" --format="value(status.url)")"
ok "Service URL: ${PROD_URL}"
info "Auth test:"
curl -s -H "Authorization: Bearer $(gcloud auth print-identity-token)" "$PROD_URL" || true
echo

# ==========================================================
# TASK 3: Cloud Build GitHub connection (manual install)
# ==========================================================
CONNECTION_NAME="cloud-build-connection"

info "Create Cloud Build GitHub connection (region: ${REGION})"
gcloud builds connections create github "$CONNECTION_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" >/dev/null 2>&1 || warn "Connection exists, continue."

ACTION_URI="$(gcloud builds connections describe "$CONNECTION_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format="value(installationState.actionUri)" || true)"

critical "MANUAL ACTION #2 — Install Cloud Build GitHub App" \
  "COPY the URL below" \
  "OPEN in new tab" \
  "Install App" \
  "Only select repositories" \
  "Select: cloudrun-progression" \
  "SAVE"
echo "${CYAN}${BOLD}${ACTION_URI}${RESET}"
echo
confirm_yes "Type YES/yes/Y/y after you finished install + SAVE: "

info "Create Cloud Build repository resource"
gcloud builds repositories create "$REPO_NAME" \
  --remote-uri="https://github.com/${GITHUB_USERNAME}/${REPO_NAME}.git" \
  --connection="$CONNECTION_NAME" \
  --region="$REGION" >/dev/null 2>&1 || warn "Repo resource exists, continue."
ok "Cloud Build repo linked"

# Triggers (with required service account)
CB_SA="projects/${PROJECT_ID}/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
REPO_PATH="projects/${PROJECT_ID}/locations/${REGION}/connections/${CONNECTION_NAME}/repositories/${REPO_NAME}"

info "Create triggers (branch/master/tag)"
gcloud builds triggers create github --name="branch" \
  --repository="$REPO_PATH" \
  --build-config="branch-cloudbuild.yaml" \
  --service-account="$CB_SA" \
  --region="$REGION" \
  --branch-pattern='[^(?!.*master)].*' >/dev/null 2>&1 || warn "Trigger branch exists."

gcloud builds triggers create github --name="master" \
  --repository="$REPO_PATH" \
  --build-config="master-cloudbuild.yaml" \
  --service-account="$CB_SA" \
  --region="$REGION" \
  --branch-pattern='master' >/dev/null 2>&1 || warn "Trigger master exists."

gcloud builds triggers create github --name="tag" \
  --repository="$REPO_PATH" \
  --build-config="tag-cloudbuild.yaml" \
  --service-account="$CB_SA" \
  --region="$REGION" \
  --tag-pattern='.*' >/dev/null 2>&1 || warn "Trigger tag exists."

ok "Triggers ready"

# ==========================================================
# TASK 3/4/5: feature -> merge -> tag (auto wait + live monitor)
# ==========================================================
info "Push feature branch new-feature-1 (triggers branch deployment)"
git checkout -B new-feature-1
if grep -q "Hello World v1.0" app.py; then
  sed -i "s/Hello World v1.0/Hello World v1.1/g" app.py
else
  sed -i "s/v1.0/v1.1/g" app.py || true
fi
git add app.py
git commit -m "updated" >/dev/null 2>&1 || warn "No changes to commit."
git push -u gcp new-feature-1

wait_builds_idle
BRANCH_URL="$(wait_tag_url "new-feature-1" || true)"

info "Merge to master (triggers canary 10%)"
git checkout master
git merge new-feature-1 -m "merge new-feature-1" >/dev/null 2>&1 || warn "Merge already applied."
git push gcp master

wait_builds_idle
CANARY_URL="$(wait_tag_url "canary" || true)"

info "Tag 1.1 (triggers prod 100%)"
git tag -f 1.1
git push -f gcp 1.1

wait_builds_idle
PROD_TAG_URL="$(wait_tag_url "prod" || true)"

# ==========================================================
# SUMMARY
# ==========================================================
clear || true
banner
echo "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${GREEN}${BOLD}✅ SCRIPT FINISHED — NOW CLICK 'Check my progress' IN LAB${RESET}"
echo "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo
echo "${WHITE}${BOLD}LIVE URL:${RESET}   ${PROD_URL}"
echo "${WHITE}${BOLD}BRANCH URL:${RESET} ${BRANCH_URL}"
echo "${WHITE}${BOLD}CANARY URL:${RESET} ${CANARY_URL}"
echo "${WHITE}${BOLD}PROD TAG:${RESET}   ${PROD_TAG_URL}"
echo
warn "If any URL is empty, Cloud Build may still be running. Check: Cloud Build → History."
ok "ePlus.DEV © — Done."