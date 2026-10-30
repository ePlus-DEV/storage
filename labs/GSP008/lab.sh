#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP008 official lab: https://www.skills.google/focuses/1846
# ePlus.DEV © 2026 - EARTHQUAKE LAB AUTO (ANTI-OUT)
# - Color output
# - Auto detect Zone/Region
# - Auto create SSH key (no prompt)
# - Upload & run VM script via nohup (survives disconnect)
# ============================================================

# ---------- COLORS ----------
BOLD=$(tput bold 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
MAGENTA=$(tput setaf 5 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)

if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
  BOLD=''; RESET=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''
fi

hr(){ printf "%s%s============================================================%s\n" "$BLUE" "$BOLD" "$RESET"; }
step(){ printf "%s%s➜ %s%s\n" "$CYAN" "$BOLD" "$*" "$RESET"; }
ok(){ printf "%s%s✔ %s%s\n" "$GREEN" "$BOLD" "$*" "$RESET"; }
warn(){ printf "%s%s⚠ %s%s\n" "$YELLOW" "$BOLD" "$*" "$RESET"; }
fail(){ printf "%s%s✘ %s%s\n" "$RED" "$BOLD" "$*" "$RESET"; }

clear || true
hr
printf "%s%s  ePlus.DEV – Starting Execution | GSP008 Earthquake Data  %s\n" "$MAGENTA" "$BOLD" "$RESET"
hr

# ---------- AUTO DETECT ----------
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || { echo "ERROR: Select the authorized lab project." >&2; exit 1; }
REGION="${REGION:-$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
ZONE="${ZONE:-$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"; fi
if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"; fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set ZONE to the lab zone." >&2; exit 1; }
  read -r -p "Lab zone: " ZONE
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ && "$ZONE" == "$REGION"-[a-z] ]] || { echo "ERROR: Invalid region/zone." >&2; exit 1; }
export REGION ZONE

gcloud config set compute/zone "$ZONE" --quiet >/dev/null
gcloud config set compute/region "$REGION" --quiet >/dev/null

INSTANCE_NAME="earthquake-vm"
BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-earthquake-data}"

ok "Project: $PROJECT_ID"
ok "Zone:    $ZONE"
ok "Region:  $REGION"
ok "Bucket:  $BUCKET_NAME"

# ---------- SSH KEY (NO PROMPT) ----------
step "Ensure SSH key exists (no prompt)"
if [[ ! -f "$HOME/.ssh/google_compute_engine" ]]; then
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t rsa -b 3072 -f "$HOME/.ssh/google_compute_engine" -N "" -q
fi
ok "SSH key OK"

# ---------- CREATE VM ----------
step "Create VM (Debian 12, full Cloud API access)"
if gcloud compute instances describe "$INSTANCE_NAME" --zone "$ZONE" >/dev/null 2>&1; then
  warn "VM exists, reuse: $INSTANCE_NAME"
else
  gcloud compute instances create "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --machine-type="e2-medium" \
    --image-family="debian-12" \
    --image-project="debian-cloud" \
    --scopes="https://www.googleapis.com/auth/cloud-platform" \
    --quiet
  ok "VM created"
fi

# ---------- CREATE BUCKET ----------
step "Create bucket"
if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  warn "Reusing existing lab bucket: $BUCKET_NAME"
else
  gsutil mb -l "$REGION" "gs://${BUCKET_NAME}"
fi
# The lab publishes two individual objects, so object ACLs are required.
gsutil uniformbucketlevelaccess set off "gs://${BUCKET_NAME}"
ok "Bucket ready"

# ---------- BUILD VM SCRIPT LOCALLY ----------
step "Create VM runner script (local temp)"
TMP_VM_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/gsp008-runner.XXXXXXXX.sh")"
trap 'rm -f "$TMP_VM_SCRIPT"' EXIT
cat > "$TMP_VM_SCRIPT" <<'VM_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

BUCKET_NAME="$1"
if [[ -z "${BUCKET_NAME:-}" ]]; then
  echo "Missing BUCKET_NAME arg"; exit 1
fi

sudo -E apt-get update -y >/dev/null
sudo -E apt-get -y -qq install git python3.11-venv >/dev/null

python3 -m venv earthquake-data
source earthquake-data/bin/activate

wget -q https://storage.googleapis.com/spls/gsp008/requirements.txt
pip3 install -q -r requirements.txt

if [[ -e training-data-analyst ]]; then
  [[ -d training-data-analyst/.git ]] || { echo "ERROR: Existing training-data-analyst is not a Git checkout; refusing to delete." >&2; exit 1; }
  [[ "$(git -C training-data-analyst remote get-url origin)" == "https://github.com/GoogleCloudPlatform/training-data-analyst" || "$(git -C training-data-analyst remote get-url origin)" == "https://github.com/GoogleCloudPlatform/training-data-analyst.git" ]] || { echo "ERROR: Unexpected training-data-analyst origin." >&2; exit 1; }
else
  git clone -q https://github.com/GoogleCloudPlatform/training-data-analyst
fi
cd training-data-analyst/CPB100/lab2b

bash ingest.sh
python3 transform.py

gsutil cp earthquakes.* "gs://${BUCKET_NAME}/earthquakes/"

# Publish only the two generated lab objects, not the whole bucket.
# With UBLA disabled, object ACLs allow anonymous reads of these two files.
gsutil acl ch -u AllUsers:R "gs://${BUCKET_NAME}/earthquakes/earthquakes.htm"
gsutil acl ch -u AllUsers:R "gs://${BUCKET_NAME}/earthquakes/earthquakes.png"

echo "DONE_UPLOAD"
VM_SCRIPT
chmod +x "$TMP_VM_SCRIPT"

# ---------- COPY SCRIPT TO VM ----------
step "Copy runner script to VM"
gcloud compute scp --quiet \
  --zone="$ZONE" \
  "$TMP_VM_SCRIPT" \
  "${INSTANCE_NAME}:~/eplus_earthquake_vm_runner.sh"
ok "Copied to VM"

# ---------- START NOHUP JOB ON VM ----------
step "Start VM job via nohup (survives Cloud Shell disconnect)"
gcloud compute ssh "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --quiet \
  --command "chmod +x ~/eplus_earthquake_vm_runner.sh && nohup ~/eplus_earthquake_vm_runner.sh '$BUCKET_NAME' > ~/earthquake_job.log 2>&1 & disown; echo STARTED"
ok "VM job started"

# ---------- SHOW HOW TO CHECK STATUS ----------
hr
printf "%s%sCHECK STATUS (run anytime):%s\n" "$YELLOW" "$BOLD" "$RESET"
printf "gcloud compute ssh %s --zone %s --quiet --command 'tail -n 80 ~/earthquake_job.log'\n" "$INSTANCE_NAME" "$ZONE"
hr

printf "%s%sOUTPUT URL (after job done):%s\n" "$GREEN" "$BOLD" "$RESET"
printf "https://storage.googleapis.com/%s/earthquakes/earthquakes.htm\n" "$BUCKET_NAME"
printf "https://storage.googleapis.com/%s/earthquakes/earthquakes.png\n" "$BUCKET_NAME"
hr