#!/bin/bash
set -Eeuo pipefail

# ============================================================================
# ePlus.DEV - Google Cloud Database Migration Service Lab
# MySQL VM -> Existing Cloud SQL for MySQL (Continuous Migration)
# Fully automatic: NO read / NO Y confirmation / NO manual pause
# ============================================================================

BLACK=$'\033[0;90m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

SOURCE_VM="dms-mysql-training-vm-v2"
SOURCE_PROFILE="mysql-vm"
SOURCE_USER="admin"
SOURCE_PASSWORD="changeme"

DEST_INSTANCE="mysql-cloudsql"
DEST_PROFILE="mysql-cloudsql-destination"
DEST_USER="root"
DEST_PASSWORD='supersecret!'

MIGRATION_JOB="vm-to-cloudsql"
EXPECTED_REGION="us-east1"
EXPECTED_NETWORK="default"

POLL_SECONDS=8

banner() {
  clear 2>/dev/null || true
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}        WELCOME TO ePlus.DEV CLOUD TUTORIAL                   ${RESET}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${MAGENTA}${BOLD}     Database Migration Service - MySQL Continuous Migration ${RESET}"
  echo -e "${YELLOW}                         © ePlus.DEV                           ${RESET}"
  echo
}

info() { echo -e "${CYAN}${BOLD}➜${RESET} $*"; }
ok()   { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}!${RESET} $*"; }
fail() { echo -e "${RED}${BOLD}✗ $*${RESET}" >&2; exit 1; }

on_error() {
  local code=$?
  local line=${BASH_LINENO[0]:-unknown}
  echo
  echo -e "${RED}${BOLD}ERROR${RESET}: script stopped at line ${line} (exit ${code})."
  echo -e "${YELLOW}The resource already created before this point is kept, so the script can usually be run again.${RESET}"
  exit "$code"
}
trap on_error ERR

get_job_state() {
  gcloud database-migration migration-jobs describe "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(state)' 2>/dev/null || true
}

get_job_phase() {
  gcloud database-migration migration-jobs describe "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(phase)' 2>/dev/null || true
}

show_job_error() {
  gcloud database-migration migration-jobs describe "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='yaml(state,phase,error)' || true
}

wait_operation() {
  local operation="$1"
  [[ -n "$operation" ]] || fail "DMS did not return an operation ID."

  info "Waiting for Database Migration Service operation..."

  while true; do
    local done_value error_code error_message

    done_value="$(
      gcloud database-migration operations describe "$operation" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(done)' 2>/dev/null || true
    )"

    case "${done_value,,}" in
      true)
        error_code="$(
          gcloud database-migration operations describe "$operation" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --format='value(error.code)' 2>/dev/null || true
        )"

        error_message="$(
          gcloud database-migration operations describe "$operation" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --format='value(error.message)' 2>/dev/null || true
        )"

        if [[ -n "$error_code" && "$error_code" != "0" ]]; then
          fail "DMS operation failed (${error_code}): ${error_message:-Unknown error}"
        fi

        ok "DMS operation completed."
        return 0
        ;;
    esac

    sleep "$POLL_SECONDS"
  done
}

run_dms_action() {
  local action="$1"
  local operation

  info "DMS action: ${action}"

  operation="$(
    gcloud database-migration migration-jobs "$action" "$MIGRATION_JOB" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(name)' \
      --quiet
  )"

  wait_operation "$operation"
}

wait_for_job_state() {
  local wanted="$1"

  while true; do
    local state phase
    state="$(get_job_state)"
    phase="$(get_job_phase)"

    echo -e "  Job state: ${YELLOW}${state:-UNKNOWN}${RESET} | Phase: ${YELLOW}${phase:-UNKNOWN}${RESET}"

    if [[ "$state" == "$wanted" ]]; then
      return 0
    fi

    if [[ "$state" == "FAILED" ]]; then
      show_job_error
      fail "Migration job entered FAILED state."
    fi

    if [[ "$state" == "COMPLETED" && "$wanted" != "COMPLETED" ]]; then
      return 0
    fi

    sleep "$POLL_SECONDS"
  done
}

wait_for_cdc() {
  info "Waiting for initial dump to finish and CDC replication to become active..."

  while true; do
    local state phase
    state="$(get_job_state)"
    phase="$(get_job_phase)"

    echo -e "  Job state: ${YELLOW}${state:-UNKNOWN}${RESET} | Phase: ${YELLOW}${phase:-UNKNOWN}${RESET}"

    if [[ "$state" == "FAILED" ]]; then
      show_job_error
      fail "Migration job failed before CDC."
    fi

    case "$phase" in
      CDC|READY_FOR_PROMOTE)
        ok "Continuous replication is active (${phase})."
        return 0
        ;;
    esac

    if [[ "$state" == "COMPLETED" ]]; then
      ok "Migration job is already completed."
      return 0
    fi

    sleep "$POLL_SECONDS"
  done
}

# ============================================================================
# CLOUD SQL NON-INTERACTIVE CONNECTION
# Uses Cloud SQL Auth Proxy + mysql client.
# `gcloud sql connect` prompts for the DB password interactively, so it is not
# suitable for a fully automatic script.
# ============================================================================

PROXY_PORT=3307
PROXY_PID=""
PROXY_LOG="/tmp/eplus-cloud-sql-proxy.log"
PROXY_BIN="${HOME}/cloud-sql-proxy"

cleanup_proxy() {
  if [[ -n "${PROXY_PID:-}" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
  fi
}

trap cleanup_proxy EXIT

install_cloudsql_proxy() {
  if command -v cloud-sql-proxy >/dev/null 2>&1; then
    PROXY_BIN="$(command -v cloud-sql-proxy)"
    return 0
  fi

  if [[ -x "$PROXY_BIN" ]]; then
    return 0
  fi

  info "Installing Cloud SQL Auth Proxy..."

  local arch proxy_arch
  arch="$(uname -m)"

  case "$arch" in
    x86_64|amd64) proxy_arch="amd64" ;;
    aarch64|arm64) proxy_arch="arm64" ;;
    *) fail "Unsupported Cloud Shell architecture: $arch" ;;
  esac

  curl -fsSL \
    "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.25.4/cloud-sql-proxy.linux.${proxy_arch}" \
    -o "$PROXY_BIN"

  chmod +x "$PROXY_BIN"
  ok "Cloud SQL Auth Proxy installed."
}

start_cloudsql_proxy() {
  if [[ -n "${PROXY_PID:-}" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
    return 0
  fi

  install_cloudsql_proxy

  local connection_name
  connection_name="$(
    gcloud sql instances describe "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(connectionName)'
  )"

  [[ -n "$connection_name" ]] || \
    fail "Unable to determine Cloud SQL connection name."

  : > "$PROXY_LOG"

  info "Starting Cloud SQL Auth Proxy on 127.0.0.1:${PROXY_PORT}..."

  "$PROXY_BIN" \
    --address=127.0.0.1 \
    --port="$PROXY_PORT" \
    "$connection_name" \
    >"$PROXY_LOG" 2>&1 &

  PROXY_PID=$!

  for _ in {1..30}; do
    if ! kill -0 "$PROXY_PID" 2>/dev/null; then
      cat "$PROXY_LOG" >&2 || true
      fail "Cloud SQL Auth Proxy exited unexpectedly."
    fi

    if timeout 1 bash -c "</dev/tcp/127.0.0.1/${PROXY_PORT}" 2>/dev/null; then
      ok "Cloud SQL Auth Proxy is ready."
      return 0
    fi

    sleep 1
  done

  cat "$PROXY_LOG" >&2 || true
  fail "Cloud SQL Auth Proxy did not become ready."
}

mysql_dest() {
  start_cloudsql_proxy

  local extra=()
  if mysql --help 2>/dev/null | grep -q -- '--get-server-public-key'; then
    extra+=(--get-server-public-key)
  fi

  MYSQL_PWD="$DEST_PASSWORD" \
    mysql \
      --protocol=TCP \
      --host=127.0.0.1 \
      --port="$PROXY_PORT" \
      --user="$DEST_USER" \
      "${extra[@]}" \
      "$@"
}

cloudsql_query() {
  local sql="$1"
  mysql_dest --table -e "$sql"
}

get_destination_customer_count() {
  local output count

  output="$(
    mysql_dest \
      --batch \
      --skip-column-names \
      -e "SELECT CONCAT('EPLUS_COUNT=', COUNT(*)) FROM customers_data.customers;" \
      2>/dev/null || true
  )"

  count="$(
    grep -oE 'EPLUS_COUNT=[0-9]+' <<< "$output" \
      | tail -n1 \
      | cut -d= -f2 || true
  )"

  printf '%s' "$count"
}

wait_for_destination_count() {
  local minimum="$1"
  info "Waiting until destination has at least ${minimum} customers..."

  while true; do
    local count
    count="$(get_destination_customer_count)"

    if [[ "$count" =~ ^[0-9]+$ ]]; then
      echo -e "  Destination customer count: ${YELLOW}${count}${RESET}"
      if (( count >= minimum )); then
        ok "Destination data is ready."
        return 0
      fi
    else
      warn "Cloud SQL query is not ready yet. Retrying..."
    fi

    sleep "$POLL_SECONDS"
  done
}

banner

# ============================================================================
# 0. AUTO-DETECT LAB ENVIRONMENT
# ============================================================================

info "Detecting current Google Cloud project..."

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi
[[ -n "$PROJECT_ID" ]] || fail "Unable to detect the active Google Cloud project."

gcloud config set project "$PROJECT_ID" --quiet >/dev/null

SOURCE_ZONE="$(
  gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="name=($SOURCE_VM)" \
    --format='value(zone)' | head -n1
)"
SOURCE_ZONE="${SOURCE_ZONE##*/}"
[[ -n "$SOURCE_ZONE" ]] || fail "Source VM ${SOURCE_VM} was not found."

SOURCE_IP="$(
  gcloud compute instances describe "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$SOURCE_ZONE" \
    --format='value(networkInterfaces[0].networkIP)'
)"
[[ -n "$SOURCE_IP" ]] || fail "Unable to detect the source VM internal IP."

NETWORK_URI="$(
  gcloud compute instances describe "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$SOURCE_ZONE" \
    --format='value(networkInterfaces[0].network)'
)"
NETWORK="${NETWORK_URI##*/}"
[[ -n "$NETWORK" ]] || fail "Unable to detect the source VPC network."

REGION="$(
  gcloud sql instances describe "$DEST_INSTANCE" \
    --project="$PROJECT_ID" \
    --format='value(region)' 2>/dev/null || true
)"
[[ -n "$REGION" ]] || fail "Cloud SQL instance ${DEST_INSTANCE} was not found."

DEST_INSTANCE_TYPE="$(
  gcloud sql instances describe "$DEST_INSTANCE" \
    --project="$PROJECT_ID" \
    --format='value(instanceType)' 2>/dev/null || true
)"

echo
echo -e "${WHITE}${BOLD}Detected lab environment${RESET}"
echo "  Project ID       : $PROJECT_ID"
echo "  Source VM        : $SOURCE_VM"
echo "  Source zone      : $SOURCE_ZONE"
echo "  Source internal IP: $SOURCE_IP"
echo "  VPC network      : $NETWORK"
echo "  Cloud SQL        : $DEST_INSTANCE"
echo "  Cloud SQL region : $REGION"
echo "  Instance type    : ${DEST_INSTANCE_TYPE:-UNKNOWN}"
echo

[[ "$REGION" == "$EXPECTED_REGION" ]] \
  || warn "Lab document expects ${EXPECTED_REGION}; detected ${REGION}. Using detected region."

[[ "$NETWORK" == "$EXPECTED_NETWORK" ]] \
  || warn "Lab document expects ${EXPECTED_NETWORK}; detected ${NETWORK}. Using detected VPC."

# ============================================================================
# 1. ENABLE REQUIRED APIs
# ============================================================================

info "Enabling required APIs..."
gcloud services enable \
  datamigration.googleapis.com \
  servicenetworking.googleapis.com \
  sqladmin.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet
ok "Required APIs are enabled."

# ============================================================================
# TASK 1 - GET SOURCE CONNECTIVITY INFORMATION
# ============================================================================

echo
echo -e "${MAGENTA}${BOLD}=== TASK 1: SOURCE CONNECTIVITY ===${RESET}"
echo "VM          : $SOURCE_VM"
echo "Zone        : $SOURCE_ZONE"
echo "Internal IP : $SOURCE_IP"
ok "Task 1 information detected automatically."

# ============================================================================
# TASK 2A - CREATE SOURCE CONNECTION PROFILE
# ============================================================================

echo
echo -e "${MAGENTA}${BOLD}=== TASK 2: CREATE SOURCE CONNECTION PROFILE ===${RESET}"

if gcloud database-migration connection-profiles describe "$SOURCE_PROFILE" \
  --region="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Source profile ${SOURCE_PROFILE} already exists."
else
  info "Creating source profile ${SOURCE_PROFILE}..."

  gcloud database-migration connection-profiles create mysql "$SOURCE_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="$SOURCE_PROFILE" \
    --host="$SOURCE_IP" \
    --port=3306 \
    --username="$SOURCE_USER" \
    --password="$SOURCE_PASSWORD" \
    --ssl-type=NONE \
    --no-async \
    --quiet

  ok "Source connection profile created."
fi

# ============================================================================
# TASK 2B - CREATE DESTINATION PROFILE FOR EXISTING CLOUD SQL INSTANCE
# ============================================================================

if gcloud database-migration connection-profiles describe "$DEST_PROFILE" \
  --region="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Destination profile ${DEST_PROFILE} already exists."
else
  info "Creating destination profile for existing Cloud SQL instance..."

  gcloud database-migration connection-profiles create mysql "$DEST_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="mysql-cloudsql-destination" \
    --cloudsql-instance="$DEST_INSTANCE" \
    --no-async \
    --quiet

  ok "Destination connection profile created."
fi

# ============================================================================
# TASK 2C - CREATE CONTINUOUS MIGRATION JOB USING VPC PEERING
# ============================================================================

if gcloud database-migration migration-jobs describe "$MIGRATION_JOB" \
  --region="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Migration job ${MIGRATION_JOB} already exists."
else
  info "Creating migration job ${MIGRATION_JOB}..."

  gcloud database-migration migration-jobs create "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="$MIGRATION_JOB" \
    --source="$SOURCE_PROFILE" \
    --destination="$DEST_PROFILE" \
    --type=CONTINUOUS \
    --peer-vpc="projects/${PROJECT_ID}/global/networks/${NETWORK}" \
    --all-databases \
    --no-async \
    --quiet

  ok "Continuous migration job created."
fi

# ============================================================================
# TASK 2D - DEMOTE EXISTING DESTINATION, VERIFY, START
# ============================================================================

JOB_STATE="$(get_job_state)"
JOB_PHASE="$(get_job_phase)"

info "Current migration job: state=${JOB_STATE:-UNKNOWN}, phase=${JOB_PHASE:-UNKNOWN}"

if [[ "$JOB_STATE" == "COMPLETED" ]]; then
  ok "Migration job is already COMPLETED. Nothing else is required."
  echo
  echo -e "${GREEN}${BOLD}LAB ALREADY COMPLETED${RESET}"
  exit 0
fi

if [[ "$JOB_STATE" == "FAILED" ]]; then
  show_job_error
  fail "Existing migration job is FAILED. Fix the displayed DMS error, then rerun the script."
fi

if [[ "$JOB_STATE" == "NOT_STARTED" ]]; then
  DEST_INSTANCE_TYPE="$(
    gcloud sql instances describe "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(instanceType)' 2>/dev/null || true
  )"

  if [[ "$DEST_INSTANCE_TYPE" != "READ_REPLICA_INSTANCE" ]]; then
    info "Demoting existing Cloud SQL destination to a migration replica..."
    run_dms_action "demote-destination"
  else
    ok "Destination is already a read replica."
  fi

  info "Verifying migration job connectivity..."
  run_dms_action "verify"

  info "Starting continuous migration job..."
  run_dms_action "start"
fi

if [[ "$JOB_STATE" == "STOPPED" ]]; then
  if [[ "$JOB_PHASE" == "CDC" || "$JOB_PHASE" == "READY_FOR_PROMOTE" ]]; then
    info "Migration job is stopped in CDC; resuming..."
    run_dms_action "resume"
  else
    info "Migration job is stopped before CDC; restarting..."
    run_dms_action "restart"
  fi
fi

# ============================================================================
# TASK 3 - WAIT FOR RUNNING
# ============================================================================

echo
echo -e "${MAGENTA}${BOLD}=== TASK 3: REVIEW CONTINUOUS MIGRATION STATUS ===${RESET}"
info "Waiting for migration job to reach RUNNING..."
wait_for_job_state "RUNNING"
ok "Migration job is running."

# ============================================================================
# TASK 4 - CONFIRM INITIAL DATA IN CLOUD SQL
# ============================================================================

echo
echo -e "${MAGENTA}${BOLD}=== TASK 4: CONFIRM MIGRATED CLOUD SQL DATA ===${RESET}"

wait_for_cdc
wait_for_destination_count 5030

info "Showing migrated databases and customer sample..."
cloudsql_query "SHOW DATABASES;
USE customers_data;
SELECT COUNT(*) AS customer_count FROM customers;
SELECT * FROM customers ORDER BY lastName LIMIT 10;"

ok "Initial migrated data confirmed in Cloud SQL."

# ============================================================================
# TASK 5 - ADD TWO SOURCE RECORDS AND CONFIRM CONTINUOUS REPLICATION
# ============================================================================

echo
echo -e "${MAGENTA}${BOLD}=== TASK 5: TEST CONTINUOUS DATA MIGRATION ===${RESET}"

SOURCE_SQL=$(cat <<'SQL'
USE customers_data;

INSERT INTO customers
(customerKey, addressKey, title, firstName, lastName, birthdate, gender, maritalStatus, email, creationDate)
SELECT
'9365552000000-999', '9999999', 'Ms', 'Magna', 'Ablorem',
'1953-07-28 00:00:00', 'FEMALE', 'MARRIED',
'magna.lorem@gmail.com', CURRENT_TIMESTAMP
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM customers WHERE customerKey='9365552000000-999'
);

INSERT INTO customers
(customerKey, addressKey, title, firstName, lastName, birthdate, gender, maritalStatus, email, creationDate)
SELECT
'9965552000000-9999', '99999999', 'Mr', 'Arcu', 'Abrisus',
'1959-07-28 00:00:00', 'MALE', 'MARRIED',
'arcu.risus@gmail.com', CURRENT_TIMESTAMP
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM customers WHERE customerKey='9965552000000-9999'
);

SELECT COUNT(*) AS customer_count FROM customers;
SELECT * FROM customers ORDER BY lastName LIMIT 10;
SQL
)

SOURCE_SQL_B64="$(printf '%s' "$SOURCE_SQL" | base64 | tr -d '\n')"

info "Adding the two required records to source MySQL VM..."

gcloud compute ssh "$SOURCE_VM" \
  --project="$PROJECT_ID" \
  --zone="$SOURCE_ZONE" \
  --quiet \
  --command="echo '$SOURCE_SQL_B64' | base64 -d | mysql -u'$SOURCE_USER' -p'$SOURCE_PASSWORD'"

ok "Source MySQL now contains the required test records."

info "Waiting for CDC to replicate the changes to Cloud SQL..."
wait_for_destination_count 5032

cloudsql_query "USE customers_data;
SELECT COUNT(*) AS customer_count FROM customers;
SELECT * FROM customers ORDER BY lastName LIMIT 10;"

ok "Continuous replication test succeeded."

# ============================================================================
# TASK 6 - PROMOTE CLOUD SQL TO STANDALONE PRIMARY
# ============================================================================

echo
echo -e "${MAGENTA}${BOLD}=== TASK 6: PROMOTE CLOUD SQL ===${RESET}"

wait_for_cdc

JOB_STATE="$(get_job_state)"
if [[ "$JOB_STATE" != "COMPLETED" ]]; then
  info "Promoting destination Cloud SQL instance..."
  run_dms_action "promote"
fi

info "Waiting for migration job to become COMPLETED..."
wait_for_job_state "COMPLETED"

FINAL_TYPE="$(
  gcloud sql instances describe "$DEST_INSTANCE" \
    --project="$PROJECT_ID" \
    --format='value(instanceType)' 2>/dev/null || true
)"

FINAL_STATE="$(get_job_state)"
FINAL_PHASE="$(get_job_phase)"

echo
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}                ALL LAB TASKS COMPLETED                       ${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo
echo "Project              : $PROJECT_ID"
echo "Source profile       : $SOURCE_PROFILE"
echo "Destination instance : $DEST_INSTANCE"
echo "Migration job        : $MIGRATION_JOB"
echo "Job state            : ${FINAL_STATE:-UNKNOWN}"
echo "Job phase            : ${FINAL_PHASE:-UNKNOWN}"
echo "Cloud SQL type       : ${FINAL_TYPE:-UNKNOWN}"
echo
echo -e "${YELLOW}${BOLD}Now click Check my progress for all lab objectives.${RESET}"
echo
