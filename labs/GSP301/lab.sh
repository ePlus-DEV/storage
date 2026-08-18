#!/bin/bash

set -Eeuo pipefail

# ============================================================
#  Remote Startup Script Challenge Lab
#  © ePlus.DEV
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

line() {
  printf '%*s\n' 72 '' | tr ' ' '='
}

section() {
  echo
  line
  echo -e "${CYAN}${BOLD}$1${NC}"
  line
}

ok() {
  echo -e "${GREEN}✓ $1${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

fail() {
  echo -e "${RED}✗ $1${NC}"
  exit 1
}

trap 'echo -e "\n${RED}✗ Script failed at line $LINENO.${NC}"' ERR

clear 2>/dev/null || true

echo -e "${BLUE}${BOLD}"
cat <<'BANNER'
   ____  ____  ____  ____  _  ____  
  / ___||  _ \|  _ \| ___|| || ___| 
 | |  _ | |_) | |_) |___ \| ||___ \ 
 | |_| ||  __/|  __/ ___) | | ___) |
  \____||_|   |_|   |____/|_||____/ 
BANNER
echo -e "${NC}"
echo -e "${BOLD}Remote Startup Script Challenge Lab${NC}"
echo -e "© ePlus.DEV"

# ============================================================
# [1/7] Detect environment
# ============================================================

section "[1/7] Detecting Google Cloud environment"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  fail "Google Cloud Project ID could not be detected."
fi

PROJECT_NUMBER="$(
  gcloud projects describe "$PROJECT_ID" \
    --format='value(projectNumber)' 2>/dev/null
)"

# Prefer existing environment variable if the lab provides it.
ZONE="${ZONE:-}"

# Otherwise use gcloud configured zone.
if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
fi

# Qwiklabs normally creates lab-monitor in the target lab zone.
# We ONLY READ it. We never modify lab-monitor.
if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then
  ZONE="$(
    gcloud compute instances list \
      --filter='name=("lab-monitor")' \
      --format='value(zone.basename())' 2>/dev/null \
      | head -n1
  )"
fi

if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then
  echo
  echo -e "${RED}Could not automatically detect the required ZONE.${NC}"
  echo
  echo "If the lab page shows for example:"
  echo "  Zone: us-central1-a"
  echo
  echo "Run:"
  echo "  export ZONE=us-central1-a"
  echo "  bash lab.sh"
  exit 1
fi

REGION="${ZONE%-*}"

BUCKET_NAME="${PROJECT_ID}-startup-script"
BUCKET_URI="gs://${BUCKET_NAME}"
SCRIPT_NAME="install-web.sh"
SCRIPT_URI="${BUCKET_URI}/${SCRIPT_NAME}"

VM_NAME="apache-vm"
FIREWALL_NAME="allow-http-apache"
NETWORK="default"

echo -e "Project ID     : ${GREEN}${PROJECT_ID}${NC}"
echo -e "Project number : ${GREEN}${PROJECT_NUMBER}${NC}"
echo -e "Zone           : ${GREEN}${ZONE}${NC}"
echo -e "Region         : ${GREEN}${REGION}${NC}"
echo -e "Bucket         : ${GREEN}${BUCKET_NAME}${NC}"
echo -e "VM             : ${GREEN}${VM_NAME}${NC}"

if [[ "$VM_NAME" == "lab-monitor" ]]; then
  fail "Protected lab-monitor instance will not be modified."
fi

# ============================================================
# [2/7] Enable APIs
# ============================================================

section "[2/7] Enabling required APIs"

gcloud services enable \
  compute.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

ok "Required APIs are enabled."

# ============================================================
# [3/7] Task 1 - Bucket + startup script
# ============================================================

section "[3/7] TASK 1 - Creating Cloud Storage bucket"

if gcloud storage buckets describe "$BUCKET_URI" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Bucket already exists: ${BUCKET_URI}"

else
  gcloud storage buckets create "$BUCKET_URI" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --quiet

  ok "Bucket created: ${BUCKET_URI}"
fi

echo
echo "Copying startup script..."

gcloud storage cp \
  gs://spls/gsp301/install-web.sh \
  "$SCRIPT_URI"

gcloud storage objects describe "$SCRIPT_URI" >/dev/null

ok "Startup script copied."
echo "Startup script URL: $SCRIPT_URI"

# ============================================================
# Configure service account access
# ============================================================

section "[4/7] Configuring VM access to startup script"

DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
CUSTOM_SA_NAME="startup-script-sa"
CUSTOM_SA="${CUSTOM_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Prefer the Compute Engine default service account.
if gcloud iam service-accounts describe "$DEFAULT_SA" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then

  VM_SA="$DEFAULT_SA"
  ok "Using Compute Engine default service account."

else
  warn "Default Compute Engine service account was not found."

  if ! gcloud iam service-accounts describe "$CUSTOM_SA" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then

    gcloud iam service-accounts create "$CUSTOM_SA_NAME" \
      --project="$PROJECT_ID" \
      --display-name="Startup Script VM" \
      --quiet

    ok "Created service account: $CUSTOM_SA"
  fi

  VM_SA="$CUSTOM_SA"
fi

echo "Service account: $VM_SA"

# Grant bucket-level read access.
gcloud storage buckets add-iam-policy-binding "$BUCKET_URI" \
  --member="serviceAccount:${VM_SA}" \
  --role="roles/storage.objectViewer" \
  --quiet >/dev/null

ok "Storage Object Viewer permission configured."

# ============================================================
# [5/7] Task 2 - Create VM
# ============================================================

section "[5/7] TASK 2 - Creating VM with remote startup script"

# Check if our VM already exists in the requested zone.
if gcloud compute instances describe "$VM_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  warn "VM ${VM_NAME} already exists."

  echo "Updating remote startup script metadata..."

  gcloud compute instances add-metadata "$VM_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --metadata="startup-script-url=${SCRIPT_URI}" \
    --quiet

  gcloud compute instances add-tags "$VM_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --tags=http-server \
    --quiet || true

  echo "Restarting VM so the startup script runs..."

  gcloud compute instances reset "$VM_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --quiet

else

  # Do not accidentally touch a same-name VM elsewhere.
  OTHER_ZONE="$(
    gcloud compute instances list \
      --project="$PROJECT_ID" \
      --filter="name=${VM_NAME}" \
      --format='value(zone.basename())' \
      | head -n1
  )"

  if [[ -n "$OTHER_ZONE" ]]; then
    VM_NAME="apache-vm-${RANDOM}"
    warn "Existing VM found in ${OTHER_ZONE}; using new name ${VM_NAME}."
  fi

  echo "Creating VM: $VM_NAME"

  gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=e2-micro \
    --network="$NETWORK" \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --service-account="$VM_SA" \
    --scopes=storage-ro \
    --tags=http-server \
    --metadata="startup-script-url=${SCRIPT_URI}" \
    --quiet

  ok "VM created successfully."
fi

# Verify metadata.
STARTUP_URL="$(
  gcloud compute instances describe "$VM_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(metadata.items.startup-script-url)'
)"

if [[ "$STARTUP_URL" == "$SCRIPT_URI" ]]; then
  ok "startup-script-url metadata verified."
else
  fail "startup-script-url metadata is incorrect: ${STARTUP_URL}"
fi

# ============================================================
# [6/7] Task 3 - Firewall rule
# ============================================================

section "[6/7] TASK 3 - Allowing HTTP traffic on TCP/80"

if gcloud compute firewall-rules describe "$FIREWALL_NAME" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  warn "Firewall rule already exists. Updating it..."

  gcloud compute firewall-rules update "$FIREWALL_NAME" \
    --project="$PROJECT_ID" \
    --allow=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server \
    --quiet

else

  gcloud compute firewall-rules create "$FIREWALL_NAME" \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server \
    --quiet
fi

ok "Firewall allows inbound TCP/80."

# ============================================================
# [7/7] Task 4 - HTTP test
# ============================================================

section "[7/7] TASK 4 - Testing Apache web server"

echo "Waiting for external IP..."

EXTERNAL_IP=""

for i in {1..30}; do
  EXTERNAL_IP="$(
    gcloud compute instances describe "$VM_NAME" \
      --zone="$ZONE" \
      --project="$PROJECT_ID" \
      --format='get(networkInterfaces[0].accessConfigs[0].natIP)' \
      2>/dev/null || true
  )"

  if [[ -n "$EXTERNAL_IP" ]]; then
    break
  fi

  printf "\rExternal IP check: %02d/30" "$i"
  sleep 2
done

echo

if [[ -z "$EXTERNAL_IP" ]]; then
  fail "VM does not have an external IP."
fi

ok "External IP: ${EXTERNAL_IP}"

echo
echo "Waiting for Apache startup script to finish..."

HTTP_OK=0

for i in {1..36}; do

  HTTP_CODE="$(
    curl \
      --connect-timeout 3 \
      --max-time 5 \
      -s \
      -o /tmp/apache-response.html \
      -w '%{http_code}' \
      "http://${EXTERNAL_IP}" || true
  )"

  if [[ "$HTTP_CODE" == "200" ]]; then
    HTTP_OK=1
    echo
    ok "Apache returned HTTP 200."
    break
  fi

  printf "\rHTTP check: %02d/36 | Current status: %s" \
    "$i" "${HTTP_CODE:-waiting}"

  sleep 5
done

echo

if [[ "$HTTP_OK" -ne 1 ]]; then

  warn "Apache is not responding yet."

  echo
  echo "Recent startup script logs:"
  echo "------------------------------------------------------------"

  gcloud compute instances get-serial-port-output "$VM_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --port=1 2>/dev/null \
    | grep -Ei \
      'startup|apache|metadata|script|error|failed' \
    | tail -n 30 || true

  echo
  echo "You can retry the startup script with:"
  echo
  echo "gcloud compute ssh $VM_NAME --zone=$ZONE --command='sudo google_metadata_script_runner startup'"
  echo
  echo "Then test:"
  echo
  echo "curl http://${EXTERNAL_IP}"
  echo

  exit 1
fi

# ============================================================
# Final verification
# ============================================================

section "LAB RESOURCE VERIFICATION"

echo -e "${GREEN}✓ TASK 1${NC} - Cloud Storage bucket"
echo "  $BUCKET_URI"
echo
echo -e "${GREEN}✓ TASK 1${NC} - Startup script"
echo "  $SCRIPT_URI"
echo
echo -e "${GREEN}✓ TASK 2${NC} - VM"
echo "  $VM_NAME"
echo
echo -e "${GREEN}✓ TASK 2${NC} - Zone"
echo "  $ZONE"
echo
echo -e "${GREEN}✓ TASK 2${NC} - Metadata"
echo "  startup-script-url=$SCRIPT_URI"
echo
echo -e "${GREEN}✓ TASK 3${NC} - Firewall"
echo "  $FIREWALL_NAME -> tcp:80"
echo
echo -e "${GREEN}✓ TASK 4${NC} - Apache"
echo "  HTTP 200"

section "CHALLENGE LAB COMPLETE"

echo -e "${GREEN}${BOLD}All automated configuration tasks completed successfully.${NC}"
echo
echo -e "VM          : ${BOLD}${VM_NAME}${NC}"
echo -e "Zone        : ${BOLD}${ZONE}${NC}"
echo -e "Bucket      : ${BOLD}${BUCKET_URI}${NC}"
echo -e "Startup URL : ${BOLD}${SCRIPT_URI}${NC}"
echo -e "External IP : ${BOLD}${EXTERNAL_IP}${NC}"
echo
echo -e "${GREEN}${BOLD}Open in browser:${NC}"
echo
echo -e "  ${CYAN}http://${EXTERNAL_IP}${NC}"
echo
echo "Now click Check my progress for Tasks 1 → 4."
echo
echo "© ePlus.DEV"
echo