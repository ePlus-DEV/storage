#!/bin/bash
set -Eeuo pipefail

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

info()    { echo -e "${CYAN_TEXT}${BOLD_TEXT}➜ $*${RESET_FORMAT}"; }
success() { echo -e "${GREEN_TEXT}${BOLD_TEXT}✓ $*${RESET_FORMAT}"; }
warn()    { echo -e "${YELLOW_TEXT}${BOLD_TEXT}! $*${RESET_FORMAT}"; }
fail()    { echo -e "${RED_TEXT}${BOLD_TEXT}✗ $*${RESET_FORMAT}" >&2; exit 1; }

clear
echo
echo -e "${CYAN_TEXT}${BOLD_TEXT}=========================================${RESET_FORMAT}"
echo -e "${CYAN_TEXT}${BOLD_TEXT}🚀   ePlus.DEV - IAM Challenge Lab   🚀${RESET_FORMAT}"
echo -e "${CYAN_TEXT}${BOLD_TEXT}=========================================${RESET_FORMAT}"
echo

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
REGION="us-central1"
ZONE="us-central1-a"

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || fail "No active Google Cloud project was found."

info "Project: ${PROJECT_ID}"
info "Region : ${REGION}"
info "Zone   : ${ZONE}"

# Task 2 requires the default gcloud configuration.
if ! gcloud config configurations describe default >/dev/null 2>&1; then
  gcloud config configurations create default --no-activate --quiet
fi
gcloud config configurations activate default --quiet
gcloud config set project "$PROJECT_ID" --quiet
gcloud config set compute/region "$REGION" --quiet
gcloud config set compute/zone "$ZONE" --quiet

# Required APIs.
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  bigquery.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

create_service_account() {
  local name="$1"
  local display_name="$2"
  local email="${name}@${PROJECT_ID}.iam.gserviceaccount.com"

  if gcloud iam service-accounts describe "$email" --project="$PROJECT_ID" >/dev/null 2>&1; then
    warn "Service account ${name} already exists; reusing it."
  else
    gcloud iam service-accounts create "$name" \
      --display-name="$display_name" \
      --project="$PROJECT_ID" \
      --quiet
    success "Created service account: ${email}"
  fi
}

grant_project_role() {
  local service_account="$1"
  local role="$2"

  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${service_account}" \
    --role="$role" \
    --condition=None \
    --quiet >/dev/null

  success "Granted ${role} to ${service_account}"
}

ensure_vm() {
  local name="$1"
  local service_account="$2"
  local current_sa=""
  local current_scopes=""

  if gcloud compute instances describe "$name" \
      --project="$PROJECT_ID" \
      --zone="$ZONE" >/dev/null 2>&1; then

    current_sa="$(gcloud compute instances describe "$name" \
      --project="$PROJECT_ID" \
      --zone="$ZONE" \
      --format='value(serviceAccounts[0].email)')"

    current_scopes="$(gcloud compute instances describe "$name" \
      --project="$PROJECT_ID" \
      --zone="$ZONE" \
      --format='value(serviceAccounts[0].scopes.flatten())')"

    if [[ "$current_sa" == "$service_account" && "$current_scopes" == *"cloud-platform"* ]]; then
      warn "VM ${name} already exists with the correct service account; reusing it."
      return
    fi

    warn "VM ${name} exists with an incorrect service account or OAuth scope; recreating it."
    gcloud compute instances delete "$name" \
      --project="$PROJECT_ID" \
      --zone="$ZONE" \
      --quiet
  fi

  gcloud compute instances create "$name" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="e2-micro" \
    --image-family="debian-12" \
    --image-project="debian-cloud" \
    --service-account="$service_account" \
    --scopes="cloud-platform" \
    --quiet

  success "Created VM ${name} with ${service_account}"
}

wait_for_ssh() {
  local name="$1"
  for _ in {1..24}; do
    if gcloud compute ssh "$name" \
      --project="$PROJECT_ID" \
      --zone="$ZONE" \
      --quiet \
      --command="true" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  fail "Unable to connect to ${name} by SSH."
}

# -----------------------------------------------------------------------------
# Task 2: Create the devops service account.
# -----------------------------------------------------------------------------
info "Task 2: Creating the devops service account"
create_service_account "devops" "devops"
DEVOPS_SA="devops@${PROJECT_ID}.iam.gserviceaccount.com"

# -----------------------------------------------------------------------------
# Task 3: Grant the required IAM roles.
# -----------------------------------------------------------------------------
info "Task 3: Granting IAM roles to devops"
grant_project_role "$DEVOPS_SA" "roles/iam.serviceAccountUser"
grant_project_role "$DEVOPS_SA" "roles/compute.instanceAdmin.v1"

# -----------------------------------------------------------------------------
# Task 4: Create vm-2 with the devops service account.
# cloud-platform is required so the VM can call Compute Engine APIs.
# -----------------------------------------------------------------------------
info "Task 4: Creating vm-2"
ensure_vm "vm-2" "$DEVOPS_SA"
wait_for_ssh "vm-2"

gcloud compute ssh vm-2 \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  --command="gcloud compute instances list --project='${PROJECT_ID}' --filter='name=vm-2' --format='table(name,zone.basename(),status)'"
success "The devops service account can list Compute Engine instances from vm-2."

# -----------------------------------------------------------------------------
# Task 5: Create/update the project custom role from YAML.
# -----------------------------------------------------------------------------
info "Task 5: Creating the custom IAM role"
cat > role-definition.yaml <<'EOF_ROLE'
title: "Cloud SQL Instance Connector"
description: "Custom role with Cloud SQL connect and get permissions"
stage: "GA"
includedPermissions:
  - cloudsql.instances.connect
  - cloudsql.instances.get
EOF_ROLE

CUSTOM_ROLE_ID="customRole"
if gcloud iam roles describe "$CUSTOM_ROLE_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam roles update "$CUSTOM_ROLE_ID" \
    --project="$PROJECT_ID" \
    --file="role-definition.yaml" \
    --quiet
  success "Updated custom role: ${CUSTOM_ROLE_ID}"
else
  gcloud iam roles create "$CUSTOM_ROLE_ID" \
    --project="$PROJECT_ID" \
    --file="role-definition.yaml" \
    --quiet
  success "Created custom role: ${CUSTOM_ROLE_ID}"
fi

# -----------------------------------------------------------------------------
# Task 6: BigQuery service account, IAM roles, VM and Python client query.
# -----------------------------------------------------------------------------
info "Task 6: Creating the BigQuery service account and VM"
create_service_account "bigquery-qwiklab" "bigquery-qwiklab"
BQ_SA="bigquery-qwiklab@${PROJECT_ID}.iam.gserviceaccount.com"

grant_project_role "$BQ_SA" "roles/bigquery.dataViewer"
grant_project_role "$BQ_SA" "roles/bigquery.user"

# Confirm the exact role that the grader reports when it is missing.
if ! gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.role=roles/bigquery.dataViewer AND bindings.members=serviceAccount:${BQ_SA}" \
    --format="value(bindings.role)" | grep -qx "roles/bigquery.dataViewer"; then
  fail "BigQuery Data Viewer binding was not found for ${BQ_SA}."
fi
success "Verified BigQuery Data Viewer for ${BQ_SA}"

ensure_vm "bigquery-instance" "$BQ_SA"
wait_for_ssh "bigquery-instance"

cat > bq-setup.sh <<EOF_REMOTE
#!/bin/bash
set -Eeuo pipefail

sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv

python3 -m venv "\$HOME/bq-venv"
source "\$HOME/bq-venv/bin/activate"
python -m pip install --upgrade pip
python -m pip install google-cloud-bigquery pandas pyarrow db-dtypes

cat > "\$HOME/query.py" <<'EOF_PY'
from google.auth import compute_engine
from google.cloud import bigquery

credentials = compute_engine.Credentials(
    service_account_email='${BQ_SA}'
)

query = '''
SELECT name, SUM(number) AS total_people
FROM \`bigquery-public-data.usa_names.usa_1910_2013\`
WHERE state = 'TX'
GROUP BY name, state
ORDER BY total_people DESC
LIMIT 20
'''

client = bigquery.Client(
    project='${PROJECT_ID}',
    credentials=credentials,
)

print(client.query(query).to_dataframe())
EOF_PY

for attempt in {1..6}; do
  if python "\$HOME/query.py"; then
    exit 0
  fi
  echo "BigQuery query failed; retrying..."
  sleep 10
done

exit 1
EOF_REMOTE

chmod +x bq-setup.sh

gcloud compute scp bq-setup.sh bigquery-instance:/tmp/bq-setup.sh \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet

gcloud compute ssh bigquery-instance \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  --command="bash /tmp/bq-setup.sh"

rm -f bq-setup.sh

echo
echo -e "${GREEN_TEXT}${BOLD_TEXT}=========================================${RESET_FORMAT}"
echo -e "${GREEN_TEXT}${BOLD_TEXT}       LAB EXECUTION COMPLETED            ${RESET_FORMAT}"
echo -e "${GREEN_TEXT}${BOLD_TEXT}=========================================${RESET_FORMAT}"
echo
echo -e "${BLUE_TEXT}${BOLD_TEXT}Project: ${PROJECT_ID}${RESET_FORMAT}"
echo -e "${BLUE_TEXT}${BOLD_TEXT}Region : ${REGION}${RESET_FORMAT}"
echo -e "${BLUE_TEXT}${BOLD_TEXT}Zone   : ${ZONE}${RESET_FORMAT}"
echo
echo -e "${YELLOW_TEXT}${BOLD_TEXT}Run Check my progress for Tasks 2-6.${RESET_FORMAT}"
