#!/bin/bash

# ==============================================================================
# ePlus.DEV - Database Migration Service
# MySQL VM -> Cloud SQL for MySQL (Continuous Migration)
#
# FRESH LAB / GRADER-SAFE / SINGLE RUN
#
# Run ONLY:
#   source lab.sh
#
# The script pauses only at grader checkpoints.
# Just click "Check my progress", then press ENTER to continue.
# No Y/N confirmation and no MySQL password prompt.
# ==============================================================================

(
set -Eeuo pipefail

RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
CYAN=$'\033[0;96m'
MAGENTA=$'\033[0;95m'
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

POLL_SECONDS=8

# Random local proxy port so an old proxy cannot conflict with this run.
PROXY_PORT=$((20000 + ($$ % 20000)))
PROXY_BIN="$HOME/cloud-sql-proxy"
PROXY_LOG="/tmp/eplus-cloud-sql-proxy-$$.log"
PROXY_PID=""

info() {
  echo -e "${CYAN}${BOLD}➜${RESET} $*"
}

ok() {
  echo -e "${GREEN}${BOLD}✓${RESET} $*"
}

warn() {
  echo -e "${YELLOW}${BOLD}!${RESET} $*"
}

fail() {
  echo -e "${RED}${BOLD}✗ $*${RESET}" >&2
  exit 1
}

banner() {
  clear 2>/dev/null || true

  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}        WELCOME TO ePlus.DEV CLOUD TUTORIAL                   ${RESET}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${MAGENTA}${BOLD}     Database Migration Service - MySQL Continuous Migration ${RESET}"
  echo -e "${YELLOW}                         © ePlus.DEV                           ${RESET}"
  echo
}

cleanup() {
  if [[ -n "${PROXY_PID:-}" ]] && kill -0 "$PROXY_PID" >/dev/null 2>&1; then
    kill "$PROXY_PID" >/dev/null 2>&1 || true
    wait "$PROXY_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

pause_for_grader() {
  local title="$1"

  echo
  echo -e "${YELLOW}${BOLD}============================================================${RESET}"
  echo -e "${YELLOW}${BOLD}$title${RESET}"
  echo -e "${YELLOW}${BOLD}============================================================${RESET}"
  echo
  read -r -p "After Check my progress is GREEN, press ENTER to continue..."
  echo
}

# ==============================================================================
# Detect lab environment
# ==============================================================================

detect_environment() {
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
      --format='value(zone)' |
    head -n1
  )"

  SOURCE_ZONE="${SOURCE_ZONE##*/}"

  [[ -n "$SOURCE_ZONE" ]] || fail "Source VM $SOURCE_VM was not found."

  SOURCE_IP="$(
    gcloud compute instances describe \
      "$SOURCE_VM" \
      --project="$PROJECT_ID" \
      --zone="$SOURCE_ZONE" \
      --format='value(networkInterfaces[0].networkIP)'
  )"

  [[ -n "$SOURCE_IP" ]] || fail "Unable to detect source VM internal IP."

  NETWORK_URI="$(
    gcloud compute instances describe \
      "$SOURCE_VM" \
      --project="$PROJECT_ID" \
      --zone="$SOURCE_ZONE" \
      --format='value(networkInterfaces[0].network)'
  )"

  NETWORK="${NETWORK_URI##*/}"

  [[ -n "$NETWORK" ]] || fail "Unable to detect source VPC."

  REGION="$(
    gcloud sql instances describe \
      "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(region)' \
      2>/dev/null || true
  )"

  [[ -n "$REGION" ]] || fail "Cloud SQL instance $DEST_INSTANCE was not found."

  INSTANCE_TYPE="$(
    gcloud sql instances describe \
      "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(instanceType)' \
      2>/dev/null || true
  )"

  echo
  echo -e "${WHITE}${BOLD}Detected lab environment${RESET}"
  echo "  Project ID         : $PROJECT_ID"
  echo "  Source VM          : $SOURCE_VM"
  echo "  Source zone        : $SOURCE_ZONE"
  echo "  Source internal IP : $SOURCE_IP"
  echo "  VPC network        : $NETWORK"
  echo "  Cloud SQL          : $DEST_INSTANCE"
  echo "  Cloud SQL region   : $REGION"
  echo "  Instance type      : ${INSTANCE_TYPE:-UNKNOWN}"
  echo
}

enable_apis() {
  info "Enabling required APIs..."

  gcloud services enable \
    datamigration.googleapis.com \
    servicenetworking.googleapis.com \
    sqladmin.googleapis.com \
    compute.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

  ok "Required APIs are enabled."
}

# ==============================================================================
# Source MySQL
# ==============================================================================

source_sql() {
  local sql="$1"
  local encoded

  encoded="$(
    printf '%s' "$sql" |
      base64 |
      tr -d '\n'
  )"

  gcloud compute ssh \
    "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$SOURCE_ZONE" \
    --quiet \
    --command="
      echo '$encoded' |
      base64 -d |
      mysql -u'$SOURCE_USER' -p'$SOURCE_PASSWORD'
    "
}

get_source_count() {
  local output

  output="$(
    source_sql "
USE customers_data;
SELECT CONCAT('EPLUS_SOURCE_COUNT=', COUNT(*))
FROM customers;
" 2>/dev/null || true
  )"

  grep -oE 'EPLUS_SOURCE_COUNT=[0-9]+' <<<"$output" |
    tail -n1 |
    cut -d= -f2 || true
}

# ==============================================================================
# Cloud SQL Auth Proxy
# ==============================================================================

ensure_proxy() {
  if [[ -x "$PROXY_BIN" ]]; then
    return 0
  fi

  info "Downloading Cloud SQL Auth Proxy..."

  curl -fsSL \
    "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.18.2/cloud-sql-proxy.linux.amd64" \
    -o "$PROXY_BIN"

  chmod +x "$PROXY_BIN"

  ok "Cloud SQL Auth Proxy installed."
}

start_proxy() {
  if [[ -n "${PROXY_PID:-}" ]] && kill -0 "$PROXY_PID" >/dev/null 2>&1; then
    return 0
  fi

  ensure_proxy

  CONNECTION_NAME="$(
    gcloud sql instances describe \
      "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(connectionName)'
  )"

  [[ -n "$CONNECTION_NAME" ]] || fail "Unable to determine Cloud SQL connection name."

  rm -f "$PROXY_LOG"

  "$PROXY_BIN" \
    --address=127.0.0.1 \
    --port="$PROXY_PORT" \
    "$CONNECTION_NAME" \
    >"$PROXY_LOG" 2>&1 &

  PROXY_PID=$!

  for _ in {1..30}; do
    if (echo >/dev/tcp/127.0.0.1/"$PROXY_PORT") >/dev/null 2>&1; then
      ok "Cloud SQL Auth Proxy is ready."
      return 0
    fi

    if ! kill -0 "$PROXY_PID" >/dev/null 2>&1; then
      cat "$PROXY_LOG" >&2 || true
      fail "Cloud SQL Auth Proxy stopped unexpectedly."
    fi

    sleep 1
  done

  cat "$PROXY_LOG" >&2 || true
  fail "Cloud SQL Auth Proxy startup timed out."
}

cloudsql_sql() {
  local sql="$1"

  start_proxy

  MYSQL_PWD="$DEST_PASSWORD" \
  mysql \
    --protocol=TCP \
    --host=127.0.0.1 \
    --port="$PROXY_PORT" \
    --user="$DEST_USER" \
    --table \
    -e "$sql"
}

get_destination_count() {
  start_proxy

  MYSQL_PWD="$DEST_PASSWORD" \
  mysql \
    --protocol=TCP \
    --host=127.0.0.1 \
    --port="$PROXY_PORT" \
    --user="$DEST_USER" \
    --batch \
    --skip-column-names \
    -e "SELECT COUNT(*) FROM customers_data.customers;" \
    2>/dev/null || true
}

wait_destination_count() {
  local wanted="$1"

  info "Waiting for destination customer count = $wanted..."

  while true; do
    local count

    count="$(get_destination_count)"

    if [[ "$count" =~ ^[0-9]+$ ]]; then
      echo -e "  Destination customers: ${YELLOW}${count}${RESET}"

      if [[ "$count" == "$wanted" ]]; then
        ok "Destination contains exactly $wanted records."
        return 0
      fi

      if (( count > wanted )); then
        fail "Destination already contains $count rows; expected $wanted. This is not a fresh-lab state."
      fi
    else
      warn "Destination database is not ready yet."
    fi

    sleep "$POLL_SECONDS"
  done
}

# ==============================================================================
# Database Migration Service helpers
# ==============================================================================

job_exists() {
  gcloud database-migration migration-jobs describe \
    "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1
}

get_job_state() {
  gcloud database-migration migration-jobs describe \
    "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(state)' \
    2>/dev/null || true
}

get_job_phase() {
  gcloud database-migration migration-jobs describe \
    "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(phase)' \
    2>/dev/null || true
}

show_job_error() {
  gcloud database-migration migration-jobs describe \
    "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='yaml(state,phase,error)' || true
}

wait_operation() {
  local operation="$1"

  [[ -n "$operation" ]] || fail "DMS did not return an operation ID."

  info "Waiting for Database Migration Service operation..."

  while true; do
    local done_value
    local error_code
    local error_message

    done_value="$(
      gcloud database-migration operations describe \
        "$operation" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(done)' \
        2>/dev/null || true
    )"

    if [[ "${done_value,,}" == "true" ]]; then
      error_code="$(
        gcloud database-migration operations describe \
          "$operation" \
          --region="$REGION" \
          --project="$PROJECT_ID" \
          --format='value(error.code)' \
          2>/dev/null || true
      )"

      error_message="$(
        gcloud database-migration operations describe \
          "$operation" \
          --region="$REGION" \
          --project="$PROJECT_ID" \
          --format='value(error.message)' \
          2>/dev/null || true
      )"

      if [[ -n "$error_code" && "$error_code" != "0" ]]; then
        fail "DMS operation failed ($error_code): ${error_message:-Unknown error}"
      fi

      ok "DMS operation completed."
      return 0
    fi

    sleep "$POLL_SECONDS"
  done
}

dms_action() {
  local action="$1"
  local operation

  info "DMS action: $action"

  operation="$(
    gcloud database-migration migration-jobs \
      "$action" \
      "$MIGRATION_JOB" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(name)' \
      --quiet
  )"

  wait_operation "$operation"
}

wait_job_running() {
  info "Waiting for migration job to become RUNNING..."

  while true; do
    local state
    local phase

    state="$(get_job_state)"
    phase="$(get_job_phase)"

    echo -e "  State: ${YELLOW}${state:-UNKNOWN}${RESET} | Phase: ${YELLOW}${phase:-UNKNOWN}${RESET}"

    case "$state" in
      RUNNING)
        ok "Migration job is RUNNING."
        return 0
        ;;

      FAILED)
        show_job_error
        fail "Migration job entered FAILED state."
        ;;
    esac

    sleep "$POLL_SECONDS"
  done
}

wait_cdc() {
  info "Waiting for initial dump to finish and CDC to become active..."

  while true; do
    local state
    local phase

    state="$(get_job_state)"
    phase="$(get_job_phase)"

    echo -e "  State: ${YELLOW}${state:-UNKNOWN}${RESET} | Phase: ${YELLOW}${phase:-UNKNOWN}${RESET}"

    if [[ "$state" == "FAILED" ]]; then
      show_job_error
      fail "Migration job failed."
    fi

    if [[ "$state" == "COMPLETED" ]]; then
      fail "Migration job was already promoted."
    fi

    if [[ "$state" == "RUNNING" && "$phase" == "CDC" ]]; then
      ok "Continuous replication is active."
      return 0
    fi

    sleep "$POLL_SECONDS"
  done
}

# ==============================================================================
# Task 2 - Connection profiles
# ==============================================================================

ensure_profiles() {
  echo
  echo -e "${MAGENTA}${BOLD}=== TASK 2: CREATE CONNECTION PROFILE ===${RESET}"

  if gcloud database-migration connection-profiles describe \
    "$SOURCE_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    ok "Source profile $SOURCE_PROFILE already exists."

  else
    info "Creating source profile $SOURCE_PROFILE..."

    gcloud database-migration connection-profiles create mysql \
      "$SOURCE_PROFILE" \
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

  if gcloud database-migration connection-profiles describe \
    "$DEST_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    ok "Destination profile $DEST_PROFILE already exists."

  else
    info "Creating destination profile for existing Cloud SQL..."

    gcloud database-migration connection-profiles create mysql \
      "$DEST_PROFILE" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --display-name="$DEST_PROFILE" \
      --cloudsql-instance="$DEST_INSTANCE" \
      --no-async \
      --quiet

    ok "Destination connection profile created."
  fi
}

# ==============================================================================
# Task 3 - Create/start continuous migration job
# ==============================================================================

ensure_migration_job() {
  echo
  echo -e "${MAGENTA}${BOLD}=== TASK 3: CONTINUOUS MIGRATION JOB ===${RESET}"

  if ! job_exists; then
    info "Creating NEW continuous migration job $MIGRATION_JOB..."

    gcloud database-migration migration-jobs create \
      "$MIGRATION_JOB" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --display-name="$MIGRATION_JOB" \
      --source="$SOURCE_PROFILE" \
      --destination="$DEST_PROFILE" \
      --type=CONTINUOUS \
      --peer-vpc="projects/$PROJECT_ID/global/networks/$NETWORK" \
      --all-databases \
      --no-async \
      --quiet

    ok "Continuous migration job created."
  else
    ok "Migration job $MIGRATION_JOB already exists."
  fi

  local state
  local phase

  state="$(get_job_state)"
  phase="$(get_job_phase)"

  info "Current migration job: ${state:-UNKNOWN} / ${phase:-UNKNOWN}"

  case "$state" in
    COMPLETED)
      fail "$MIGRATION_JOB is already COMPLETED. This script is for a fresh lab."
      ;;

    FAILED)
      show_job_error
      fail "$MIGRATION_JOB is FAILED."
      ;;

    RUNNING)
      ok "Migration job is already RUNNING."
      return 0
      ;;

    NOT_STARTED|"")
      local type

      type="$(
        gcloud sql instances describe \
          "$DEST_INSTANCE" \
          --project="$PROJECT_ID" \
          --format='value(instanceType)'
      )"

      if [[ "$type" != "READ_REPLICA_INSTANCE" ]]; then
        info "Demoting existing Cloud SQL destination..."
        dms_action "demote-destination"
      else
        ok "Destination is already a migration read replica."
      fi

      info "Testing migration job..."
      dms_action "verify"

      info "Starting continuous migration job..."
      dms_action "start"
      ;;

    STOPPED)
      if [[ "$phase" == "CDC" ]]; then
        info "Resuming stopped migration job..."
        dms_action "resume"
      else
        fail "Migration job is STOPPED before CDC."
      fi
      ;;
  esac

  wait_job_running
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  banner
  detect_environment
  enable_apis

  echo
  echo -e "${MAGENTA}${BOLD}=== TASK 1: SOURCE CONNECTIVITY ===${RESET}"
  echo "VM          : $SOURCE_VM"
  echo "Zone        : $SOURCE_ZONE"
  echo "Internal IP : $SOURCE_IP"
  ok "Source connectivity detected."

  # Fresh-lab guard: source should still have 5030 rows.
  local source_count

  source_count="$(get_source_count)"

  if [[ "$source_count" =~ ^[0-9]+$ && "$source_count" != "5030" ]]; then
    fail "Source currently has $source_count customers; fresh lab should have 5030."
  fi

  ensure_profiles
  ensure_migration_job

  echo
  echo -e "${MAGENTA}${BOLD}=== TASK 4: CONFIRM CLOUD SQL DATA ===${RESET}"

  wait_cdc
  wait_destination_count 5030

  cloudsql_sql "
SHOW DATABASES;

USE customers_data;

SELECT COUNT(*) AS customer_count
FROM customers;

SELECT *
FROM customers
ORDER BY lastName
LIMIT 10;
"

  # --------------------------------------------------------------------------
  # GRADER CHECKPOINT 1
  # Keep job RUNNING and destination at 5030.
  # --------------------------------------------------------------------------

  pause_for_grader \
    "CHECK NOW: Connection Profile + Task 3 Continuous Job + Task 4 Cloud SQL Data"

  # --------------------------------------------------------------------------
  # Task 5
  # --------------------------------------------------------------------------

  echo
  echo -e "${MAGENTA}${BOLD}=== TASK 5: TEST CONTINUOUS MIGRATION ===${RESET}"

  info "Adding the two required records to source MySQL..."

  source_sql "
USE customers_data;

INSERT INTO customers
(
  customerKey,
  addressKey,
  title,
  firstName,
  lastName,
  birthdate,
  gender,
  maritalStatus,
  email,
  creationDate
)
SELECT
  '9365552000000-999',
  '9999999',
  'Ms',
  'Magna',
  'Ablorem',
  '1953-07-28 00:00:00',
  'FEMALE',
  'MARRIED',
  'magna.lorem@gmail.com',
  CURRENT_TIMESTAMP
FROM DUAL
WHERE NOT EXISTS
(
  SELECT 1 FROM customers
  WHERE customerKey='9365552000000-999'
);

INSERT INTO customers
(
  customerKey,
  addressKey,
  title,
  firstName,
  lastName,
  birthdate,
  gender,
  maritalStatus,
  email,
  creationDate
)
SELECT
  '9965552000000-9999',
  '99999999',
  'Mr',
  'Arcu',
  'Abrisus',
  '1959-07-28 00:00:00',
  'MALE',
  'MARRIED',
  'arcu.risus@gmail.com',
  CURRENT_TIMESTAMP
FROM DUAL
WHERE NOT EXISTS
(
  SELECT 1 FROM customers
  WHERE customerKey='9965552000000-9999'
);

SELECT COUNT(*) AS customer_count
FROM customers;

SELECT *
FROM customers
ORDER BY lastName
LIMIT 10;
"

  ok "Source contains the Task 5 test data."

  wait_destination_count 5032

  cloudsql_sql "
USE customers_data;

SELECT COUNT(*) AS customer_count
FROM customers;

SELECT *
FROM customers
ORDER BY lastName
LIMIT 10;
"

  ok "Continuous replication test succeeded."

  # --------------------------------------------------------------------------
  # GRADER CHECKPOINT 2
  # Keep job RUNNING and both sides at 5032 before promotion.
  # --------------------------------------------------------------------------

  pause_for_grader \
    "CHECK NOW: Task 5 - Continuous migration from source to destination"

  # --------------------------------------------------------------------------
  # Task 6
  # --------------------------------------------------------------------------

  echo
  echo -e "${MAGENTA}${BOLD}=== TASK 6: PROMOTE CLOUD SQL ===${RESET}"

  info "Promoting destination Cloud SQL instance..."

  dms_action "promote"

  info "Waiting for migration job to become COMPLETED..."

  while true; do
    local state
    local phase

    state="$(get_job_state)"
    phase="$(get_job_phase)"

    echo -e "  State: ${YELLOW}${state:-UNKNOWN}${RESET} | Phase: ${YELLOW}${phase:-UNKNOWN}${RESET}"

    if [[ "$state" == "COMPLETED" ]]; then
      break
    fi

    if [[ "$state" == "FAILED" ]]; then
      show_job_error
      fail "Promotion failed."
    fi

    sleep "$POLL_SECONDS"
  done

  local final_type

  final_type="$(
    gcloud sql instances describe \
      "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(instanceType)'
  )"

  echo
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}${BOLD}                    LAB OPERATIONS COMPLETE                  ${RESET}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo
  echo "Project              : $PROJECT_ID"
  echo "Source profile       : $SOURCE_PROFILE"
  echo "Migration job        : $MIGRATION_JOB"
  echo "Job state            : $(get_job_state)"
  echo "Cloud SQL type       : $final_type"
  echo
  echo -e "${YELLOW}${BOLD}CLICK CHECK MY PROGRESS FOR TASK 6 NOW.${RESET}"
  echo
}

main
)