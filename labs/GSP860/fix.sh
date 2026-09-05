#!/bin/bash
set -Eeuo pipefail

# ============================================================================
# ePlus.DEV - GSP860 Recovery
# Recover Task 3 / Task 4 after vm-to-cloudsql was already promoted.
#
# Usage:
#   bash recover_gsp860.sh prepare
#      -> restores source to 5030
#      -> clears destination user DBs
#      -> recreates vm-to-cloudsql
#      -> starts CONTINUOUS migration
#      -> waits for RUNNING / CDC and 5030 rows
#      -> EXITS automatically so you can click Task 3 + Task 4 Check my progress
#
#   bash recover_gsp860.sh finish
#      -> inserts the two Task 5 rows
#      -> waits for 5032 rows on Cloud SQL
#      -> promotes migration job
#      -> waits for COMPLETED
#      -> then click Task 6 Check my progress
#
# No read / no Y / no interactive password.
# ============================================================================

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
PROXY_PORT=3307
PROXY_BIN="$HOME/cloud-sql-proxy"
PROXY_LOG="/tmp/eplus-cloud-sql-proxy.log"
PROXY_PID=""

MODE="${1:-prepare}"

info() { echo -e "${CYAN}${BOLD}➜${RESET} $*"; }
ok()   { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}!${RESET} $*"; }
fail() { echo -e "${RED}${BOLD}✗ $*${RESET}" >&2; exit 1; }

cleanup_proxy() {
  if [[ -n "${PROXY_PID:-}" ]]; then
    kill "$PROXY_PID" >/dev/null 2>&1 || true
    wait "$PROXY_PID" 2>/dev/null || true
    PROXY_PID=""
  fi
}
trap cleanup_proxy EXIT

banner() {
  clear 2>/dev/null || true
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}        WELCOME TO ePlus.DEV CLOUD TUTORIAL                   ${RESET}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${MAGENTA}${BOLD}              GSP860 - Migration Recovery                    ${RESET}"
  echo -e "${YELLOW}                         © ePlus.DEV                           ${RESET}"
  echo
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

job_exists() {
  gcloud database-migration migration-jobs describe \
    "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1
}

wait_operation() {
  local operation="$1"
  [[ -n "$operation" ]] || fail "No DMS operation ID returned."

  while true; do
    local done_value error_code error_message

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
        fail "DMS operation failed (${error_code}): ${error_message:-Unknown error}"
      fi

      ok "DMS operation completed."
      return 0
    fi

    sleep "$POLL_SECONDS"
  done
}

run_dms_action() {
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

ensure_proxy_binary() {
  if [[ -x "$PROXY_BIN" ]]; then
    return 0
  fi

  info "Downloading Cloud SQL Auth Proxy..."

  curl -fsSL \
    "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.18.2/cloud-sql-proxy.linux.amd64" \
    -o "$PROXY_BIN"

  chmod +x "$PROXY_BIN"
}

start_proxy() {
  cleanup_proxy
  ensure_proxy_binary

  local connection_name
  connection_name="$(
    gcloud sql instances describe \
      "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(connectionName)'
  )"

  [[ -n "$connection_name" ]] || fail "Unable to get Cloud SQL connection name."

  rm -f "$PROXY_LOG"

  "$PROXY_BIN" \
    --address=127.0.0.1 \
    --port="$PROXY_PORT" \
    "$connection_name" \
    >"$PROXY_LOG" 2>&1 &

  PROXY_PID=$!

  for _ in {1..30}; do
    if (echo >/dev/tcp/127.0.0.1/"$PROXY_PORT") >/dev/null 2>&1; then
      return 0
    fi

    if ! kill -0 "$PROXY_PID" >/dev/null 2>&1; then
      cat "$PROXY_LOG" >&2 || true
      fail "Cloud SQL Auth Proxy stopped unexpectedly."
    fi

    sleep 1
  done

  cat "$PROXY_LOG" >&2 || true
  fail "Cloud SQL Auth Proxy did not become ready."
}

cloudsql_exec() {
  local sql="$1"

  start_proxy

  MYSQL_PWD="$DEST_PASSWORD" \
  mysql \
    --protocol=TCP \
    --host=127.0.0.1 \
    --port="$PROXY_PORT" \
    --user="$DEST_USER" \
    --batch \
    --raw \
    -e "$sql"

  cleanup_proxy
}

get_destination_count() {
  start_proxy

  local count
  count="$(
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
  )"

  cleanup_proxy

  printf '%s' "$count"
}

wait_destination_count() {
  local expected="$1"

  info "Waiting for Cloud SQL customers count = ${expected}..."

  while true; do
    local count
    count="$(get_destination_count)"

    if [[ "$count" =~ ^[0-9]+$ ]]; then
      echo -e "  customer_count: ${YELLOW}${count}${RESET}"

      if [[ "$count" == "$expected" ]]; then
        ok "Destination has exactly ${expected} rows."
        return 0
      fi
    else
      warn "Destination database not ready yet."
    fi

    sleep "$POLL_SECONDS"
  done
}

source_exec() {
  local sql="$1"
  local sql_b64

  sql_b64="$(
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
      echo '$sql_b64' |
      base64 -d |
      mysql -u'$SOURCE_USER' -p'$SOURCE_PASSWORD'
    "
}

wait_for_cdc() {
  info "Waiting for migration job RUNNING / CDC..."

  while true; do
    local state phase

    state="$(get_job_state)"
    phase="$(get_job_phase)"

    echo -e "  State: ${YELLOW}${state:-UNKNOWN}${RESET} | Phase: ${YELLOW}${phase:-UNKNOWN}${RESET}"

    if [[ "$state" == "FAILED" ]]; then
      gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='yaml(state,phase,error)' || true

      fail "Migration job failed."
    fi

    if [[ "$state" == "RUNNING" && "$phase" == "CDC" ]]; then
      ok "Migration job is RUNNING / CDC."
      return 0
    fi

    sleep "$POLL_SECONDS"
  done
}

detect_environment() {
  PROJECT_ID="$(
    gcloud config get-value project 2>/dev/null || true
  )"

  if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
  fi

  [[ -n "$PROJECT_ID" ]] || fail "Unable to detect project ID."

  gcloud config set project "$PROJECT_ID" --quiet >/dev/null

  SOURCE_ZONE="$(
    gcloud compute instances list \
      --project="$PROJECT_ID" \
      --filter="name=($SOURCE_VM)" \
      --format='value(zone)' |
      head -n1
  )"
  SOURCE_ZONE="${SOURCE_ZONE##*/}"

  [[ -n "$SOURCE_ZONE" ]] || fail "Unable to find source VM."

  SOURCE_IP="$(
    gcloud compute instances describe \
      "$SOURCE_VM" \
      --project="$PROJECT_ID" \
      --zone="$SOURCE_ZONE" \
      --format='value(networkInterfaces[0].networkIP)'
  )"

  NETWORK_URI="$(
    gcloud compute instances describe \
      "$SOURCE_VM" \
      --project="$PROJECT_ID" \
      --zone="$SOURCE_ZONE" \
      --format='value(networkInterfaces[0].network)'
  )"
  NETWORK="${NETWORK_URI##*/}"

  REGION="$(
    gcloud sql instances describe \
      "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(region)'
  )"

  echo -e "${WHITE}${BOLD}Detected environment${RESET}"
  echo "  Project : $PROJECT_ID"
  echo "  Region  : $REGION"
  echo "  Zone    : $SOURCE_ZONE"
  echo "  Source  : $SOURCE_IP"
  echo "  VPC     : $NETWORK"
  echo
}

ensure_profiles() {
  if ! gcloud database-migration connection-profiles describe \
    "$SOURCE_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    info "Recreating source profile $SOURCE_PROFILE..."

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
  fi

  if ! gcloud database-migration connection-profiles describe \
    "$DEST_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    info "Recreating destination profile $DEST_PROFILE..."

    gcloud database-migration connection-profiles create mysql \
      "$DEST_PROFILE" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --display-name="$DEST_PROFILE" \
      --cloudsql-instance="$DEST_INSTANCE" \
      --no-async \
      --quiet
  fi

  ok "Connection profiles are ready."
}

prepare() {
  echo -e "${MAGENTA}${BOLD}=== PREPARE: RECOVER TASK 3 + TASK 4 ===${RESET}"

  # If the recreated job is already in RUNNING/CDC, do not reset again.
  if job_exists; then
    local current_state current_phase
    current_state="$(get_job_state)"
    current_phase="$(get_job_phase)"

    if [[ "$current_state" == "RUNNING" && "$current_phase" == "CDC" ]]; then
      ok "Recovery migration job is already RUNNING / CDC."
      wait_destination_count 5030

      echo
      echo -e "${GREEN}${BOLD}READY FOR GRADER${RESET}"
      echo -e "${YELLOW}${BOLD}Click Check my progress for Task 3 and Task 4 NOW.${RESET}"
      exit 0
    fi
  fi

  if job_exists; then
    local state
    state="$(get_job_state)"

    if [[ "$state" != "COMPLETED" ]]; then
      fail "Existing $MIGRATION_JOB is ${state}. Do not delete it automatically."
    fi

    info "Deleting completed migration job record $MIGRATION_JOB..."

    gcloud database-migration migration-jobs delete \
      "$MIGRATION_JOB" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --quiet

    ok "Completed migration job record deleted."
  fi

  # Restore source exactly to the Task 4 state: 5030 rows.
  info "Removing Task 5 test rows from source to restore 5030 rows..."

  source_exec "
USE customers_data;

DELETE FROM customers
WHERE customerKey IN (
  '9365552000000-999',
  '9965552000000-9999'
);

SELECT COUNT(*) AS customer_count
FROM customers;
"

  # Existing Cloud SQL destinations should be empty before a fresh migration.
  info "Clearing migrated user databases from destination..."

  cloudsql_exec "
DROP DATABASE IF EXISTS customers_data;
DROP DATABASE IF EXISTS sales_data;
"

  ok "Destination user databases cleared."

  ensure_profiles

  info "Creating NEW continuous migration job $MIGRATION_JOB..."

  gcloud database-migration migration-jobs create \
    "$MIGRATION_JOB" \
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

  ok "New CONTINUOUS migration job created."

  run_dms_action "demote-destination"
  run_dms_action "verify"
  run_dms_action "start"

  wait_for_cdc
  wait_destination_count 5030

  echo
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}${BOLD}              TASK 3 + TASK 4 STATE READY                    ${RESET}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo
  echo "Migration job : $MIGRATION_JOB"
  echo "State         : $(get_job_state)"
  echo "Phase         : $(get_job_phase)"
  echo "Customers     : 5030"
  echo
  echo -e "${YELLOW}${BOLD}CLICK CHECK MY PROGRESS FOR TASK 3 AND TASK 4 NOW.${RESET}"
  echo -e "${YELLOW}Do NOT run finish until those objectives show 20/20.${RESET}"
}

finish() {
  echo -e "${MAGENTA}${BOLD}=== FINISH: TASK 5 STATE + PROMOTE ===${RESET}"

  [[ "$(get_job_state)" == "RUNNING" ]] || \
    fail "Migration job must be RUNNING before finish."

  wait_for_cdc

  info "Adding the two required Task 5 rows to source..."

  source_exec "
USE customers_data;

INSERT INTO customers
(
  customerKey,addressKey,title,firstName,lastName,birthdate,
  gender,maritalStatus,email,creationDate
)
SELECT
  '9365552000000-999','9999999','Ms','Magna','Ablorem',
  '1953-07-28 00:00:00','FEMALE','MARRIED',
  'magna.lorem@gmail.com',CURRENT_TIMESTAMP
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM customers
  WHERE customerKey='9365552000000-999'
);

INSERT INTO customers
(
  customerKey,addressKey,title,firstName,lastName,birthdate,
  gender,maritalStatus,email,creationDate
)
SELECT
  '9965552000000-9999','99999999','Mr','Arcu','Abrisus',
  '1959-07-28 00:00:00','MALE','MARRIED',
  'arcu.risus@gmail.com',CURRENT_TIMESTAMP
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM customers
  WHERE customerKey='9965552000000-9999'
);

SELECT COUNT(*) AS customer_count
FROM customers;
"

  wait_destination_count 5032

  ok "Continuous replication confirmed at 5032 rows."

  run_dms_action "promote"

  info "Waiting for COMPLETED..."

  while true; do
    local state
    state="$(get_job_state)"

    echo -e "  State: ${YELLOW}${state:-UNKNOWN}${RESET}"

    if [[ "$state" == "COMPLETED" ]]; then
      break
    fi

    if [[ "$state" == "FAILED" ]]; then
      fail "Migration job failed during promotion."
    fi

    sleep "$POLL_SECONDS"
  done

  local instance_type
  instance_type="$(
    gcloud sql instances describe \
      "$DEST_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(instanceType)'
  )"

  echo
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}${BOLD}                     MIGRATION COMPLETED                     ${RESET}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo "Job state      : $(get_job_state)"
  echo "Cloud SQL type : $instance_type"
  echo
  echo -e "${YELLOW}${BOLD}Now click Check my progress for Task 6.${RESET}"
}

banner
detect_environment

case "$MODE" in
  prepare)
    prepare
    ;;
  finish)
    finish
    ;;
  *)
    fail "Usage: bash $0 prepare | finish"
    ;;
esac