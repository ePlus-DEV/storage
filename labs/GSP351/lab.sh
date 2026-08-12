#!/usr/bin/env bash

# ============================================================
# GSP351
# Migrate MySQL Data to Cloud SQL using Database Migration Service
#
# Usage:
#   bash lab.sh task2
#   bash lab.sh task3
#   bash lab.sh task4
#   bash lab.sh task5
#   bash lab.sh status
#
# © ePlus.DEV
# ============================================================

set -u

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# ============================================================
# COLORS
# ============================================================

RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'

BOLD=$'\033[1m'
RESET=$'\033[0m'

# ============================================================
# UI
# ============================================================

section() {
  echo
  echo "${CYAN}${BOLD}======================================================================${RESET}"
  echo "${CYAN}${BOLD}$1${RESET}"
  echo "${CYAN}${BOLD}======================================================================${RESET}"
}

ok() {
  echo "${GREEN}✓ $*${RESET}"
}

warn() {
  echo "${YELLOW}⚠ $*${RESET}"
}

fail() {
  echo "${RED}✗ $*${RESET}"
}

die() {
  fail "$*"
  exit 1
}

banner() {

  clear

  echo "${MAGENTA}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║                           GSP351                               ║"
  echo "║          MySQL → Cloud SQL Database Migration Service          ║"
  echo "║                        © ePlus.DEV                             ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo "${RESET}"
}

finish() {

  echo
  echo "${MAGENTA}${BOLD}======================================================================${RESET}"
  echo "${GREEN}${BOLD}$1${RESET}"
  echo "${MAGENTA}${BOLD}======================================================================${RESET}"
  echo
  echo "${WHITE}$2${RESET}"
  echo
  echo "${CYAN}${BOLD}© ePlus.DEV${RESET}"
}

# ============================================================
# MODE
# ============================================================

MODE="${1:-status}"

case "$MODE" in

  task2|task3|task4|task5|status)
    ;;

  *)
    echo "Usage:"
    echo "  bash lab.sh task2"
    echo "  bash lab.sh task3"
    echo "  bash lab.sh task4"
    echo "  bash lab.sh task5"
    echo "  bash lab.sh status"
    exit 1
    ;;

esac

banner

# ============================================================
# INPUT
# ============================================================

section "LAB RESOURCE INPUT"

echo "${WHITE}Enter the three resource names shown in the lab.${RESET}"
echo

read -r -p "$(echo "${CYAN}${BOLD}MySQL source instance                : ${RESET}")" \
  SOURCE_VM

read -r -p "$(echo "${CYAN}${BOLD}Cloud SQL one-time migration target  : ${RESET}")" \
  ONE_TIME_TARGET

read -r -p "$(echo "${CYAN}${BOLD}Cloud SQL continuous migration target: ${RESET}")" \
  CONTINUOUS_TARGET

[[ -z "$SOURCE_VM" ]] &&
  die "MySQL source instance cannot be empty."

[[ -z "$ONE_TIME_TARGET" ]] &&
  die "One-time Cloud SQL target cannot be empty."

[[ -z "$CONTINUOUS_TARGET" ]] &&
  die "Continuous Cloud SQL target cannot be empty."

[[ "$ONE_TIME_TARGET" == "$CONTINUOUS_TARGET" ]] &&
  die "One-time and continuous destinations must be different."

# ============================================================
# CONSTANTS
# ============================================================

MYSQL_USER="admin"
MYSQL_PASSWORD="changeme"
MYSQL_PORT="3306"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"

if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
fi

[[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]] &&
  die "Unable to detect Project ID."

ONE_TIME_JOB="$ONE_TIME_TARGET"
CONTINUOUS_JOB="$CONTINUOUS_TARGET"

ONE_TIME_DEST_CP="cp-${ONE_TIME_TARGET}"
CONTINUOUS_DEST_CP="cp-${CONTINUOUS_TARGET}"

ONE_TIME_DEST_CP="${ONE_TIME_DEST_CP:0:60}"
CONTINUOUS_DEST_CP="${CONTINUOUS_DEST_CP:0:60}"

# ============================================================
# DETECT ENVIRONMENT
# ============================================================

section "Detecting Google Cloud environment"

ZONE=$(
  gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="name=$SOURCE_VM" \
    --format='value(zone.basename())' |
    head -n1
)

[[ -z "$ZONE" ]] &&
  die "Compute Engine instance not found: $SOURCE_VM"

REGION="${ZONE%-*}"

SOURCE_EXTERNAL_IP=$(
  gcloud compute instances describe "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --format='value(networkInterfaces[0].accessConfigs[0].natIP)'
)

SOURCE_INTERNAL_IP=$(
  gcloud compute instances describe "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --format='value(networkInterfaces[0].networkIP)'
)

NETWORK_URI=$(
  gcloud compute instances describe "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --format='value(networkInterfaces[0].network)'
)

NETWORK_NAME="${NETWORK_URI##*/}"

[[ -z "$SOURCE_EXTERNAL_IP" ]] &&
  die "Source VM does not have an external IP."

[[ -z "$SOURCE_INTERNAL_IP" ]] &&
  die "Source VM does not have an internal IP."

gcloud config set project "$PROJECT_ID" >/dev/null
gcloud config set compute/zone "$ZONE" >/dev/null
gcloud config set compute/region "$REGION" >/dev/null

echo "${WHITE}Project                   : ${CYAN}$PROJECT_ID${RESET}"
echo "${WHITE}Region                    : ${CYAN}$REGION${RESET}"
echo "${WHITE}Zone                      : ${CYAN}$ZONE${RESET}"
echo
echo "${WHITE}MySQL source              : ${CYAN}$SOURCE_VM${RESET}"
echo "${WHITE}External IP               : ${CYAN}$SOURCE_EXTERNAL_IP${RESET}"
echo "${WHITE}Internal IP               : ${CYAN}$SOURCE_INTERNAL_IP${RESET}"
echo "${WHITE}VPC                       : ${CYAN}$NETWORK_NAME${RESET}"
echo
echo "${WHITE}One-time destination      : ${GREEN}$ONE_TIME_TARGET${RESET}"
echo "${WHITE}Continuous destination    : ${GREEN}$CONTINUOUS_TARGET${RESET}"
echo "${WHITE}Execution mode            : ${YELLOW}$MODE${RESET}"

# ============================================================
# VALIDATE DESTINATIONS
# ============================================================

gcloud sql instances describe "$ONE_TIME_TARGET" \
  --project="$PROJECT_ID" >/dev/null 2>&1 ||
  die "Cloud SQL instance not found: $ONE_TIME_TARGET"

gcloud sql instances describe "$CONTINUOUS_TARGET" \
  --project="$PROJECT_ID" >/dev/null 2>&1 ||
  die "Cloud SQL instance not found: $CONTINUOUS_TARGET"

# ============================================================
# FIND EXISTING SOURCE CONNECTION PROFILE
# ============================================================

SOURCE_CP="mysql-source-profile"

if ! gcloud database-migration connection-profiles describe "$SOURCE_CP" \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  while read -r cp; do

    [[ -z "$cp" ]] && continue

    HOST=$(
      gcloud database-migration connection-profiles describe "$cp" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(mysql.host)' \
        2>/dev/null || true
    )

    if [[ "$HOST" == "$SOURCE_EXTERNAL_IP" ||
          "$HOST" == "$SOURCE_INTERNAL_IP" ]]; then

      SOURCE_CP="$cp"
      break
    fi

  done < <(
    gcloud database-migration connection-profiles list \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(name.basename())' \
      2>/dev/null
  )
fi

echo "${WHITE}Source connection profile : ${CYAN}$SOURCE_CP${RESET}"

# ============================================================
# GENERIC DMS HELPERS
# ============================================================

job_exists() {

  gcloud database-migration migration-jobs describe "$1" \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1
}

job_state() {

  gcloud database-migration migration-jobs describe "$1" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(state)' \
    2>/dev/null || true
}

job_phase() {

  gcloud database-migration migration-jobs describe "$1" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(phase)' \
    2>/dev/null || true
}

profile_exists() {

  gcloud database-migration connection-profiles describe "$1" \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1
}

source_profile_host() {

  gcloud database-migration connection-profiles describe "$SOURCE_CP" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(mysql.host)' \
    2>/dev/null || true
}

# ============================================================
# WAIT DMS LONG-RUNNING OPERATION
# ============================================================

wait_operation() {

  local operation="$1"

  [[ -z "$operation" ]] && return 0

  local op_id="${operation##*/}"

  echo "${YELLOW}Waiting for DMS operation: $op_id${RESET}"

  for ((i=1; i<=360; i++)); do

    local done
    local err

    done=$(
      gcloud database-migration operations describe "$op_id" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(done)' \
        2>/dev/null || true
    )

    err=$(
      gcloud database-migration operations describe "$op_id" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(error.message)' \
        2>/dev/null || true
    )

    if [[ -n "$err" ]]; then
      echo
      fail "DMS operation failed:"
      echo "$err"
      return 1
    fi

    if [[ "$done" == "True" ||
          "$done" == "true" ]]; then

      echo
      ok "DMS operation completed."
      return 0
    fi

    printf "\r${YELLOW}DMS operation in progress... %-3d${RESET}" "$i"

    sleep 5
  done

  echo
  fail "Timeout waiting for DMS operation."

  return 1
}

# ============================================================
# DMS ACTION
#
# IMPORTANT:
# demote-destination / verify / start / restart /
# resume / promote do NOT use --no-async here.
# ============================================================

dms_action() {

  local action="$1"
  local job="$2"

  local error_file="/tmp/gsp351-${action}-${job}.err"
  local operation=""

  echo "${YELLOW}${action}: $job${RESET}"

  operation=$(
    gcloud database-migration migration-jobs "$action" "$job" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --quiet \
      --format='value(name)' \
      2>"$error_file"
  )

  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "DMS action '$action' failed."
    cat "$error_file"
    return "$rc"
  fi

  if [[ -n "$operation" ]]; then
    wait_operation "$operation" || return 1
  fi

  return 0
}

# ============================================================
# WAIT JOB STATE
# ============================================================

wait_for_state() {

  local job="$1"
  local wanted="$2"

  echo

  for ((i=1; i<=360; i++)); do

    local state
    local phase

    state=$(job_state "$job")
    phase=$(job_phase "$job")

    printf "\r${YELLOW}Job %-28s State: %-18s Phase: %-22s${RESET}" \
      "$job" \
      "${state:-UNKNOWN}" \
      "${phase:-N/A}"

    if [[ "$state" == "$wanted" ]]; then
      echo
      ok "$job reached state $wanted."
      return 0
    fi

    if [[ "$state" == "FAILED" ]]; then

      echo
      fail "$job entered FAILED state."

      gcloud database-migration migration-jobs describe "$job" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='yaml(state,phase,error)'

      return 1
    fi

    sleep 5
  done

  echo
  fail "Timeout waiting for migration job."

  return 1
}

# ============================================================
# WAIT CONTINUOUS CDC
# ============================================================

wait_for_cdc() {

  local job="$1"

  echo
  echo "${YELLOW}Waiting for continuous migration to reach CDC...${RESET}"

  for ((i=1; i<=360; i++)); do

    local state
    local phase

    state=$(job_state "$job")
    phase=$(job_phase "$job")

    printf "\r${YELLOW}Job %-28s State: %-18s Phase: %-22s${RESET}" \
      "$job" \
      "${state:-UNKNOWN}" \
      "${phase:-N/A}"

    if [[ "$state" == "RUNNING" &&
          "$phase" == "CDC" ]]; then

      echo
      ok "Continuous migration is RUNNING / CDC."
      return 0
    fi

    if [[ "$state" == "FAILED" ]]; then

      echo
      fail "Continuous migration FAILED."

      gcloud database-migration migration-jobs describe "$job" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='yaml(state,phase,error)'

      return 1
    fi

    if [[ "$state" == "COMPLETED" ]]; then

      echo
      warn "Continuous migration has already been promoted."
      return 2
    fi

    sleep 5
  done

  echo
  fail "Continuous migration did not reach CDC."

  return 1
}

# ============================================================
# SOURCE PROFILE
# ============================================================

create_source_profile() {

  if profile_exists "$SOURCE_CP"; then
    ok "Source connection profile already exists: $SOURCE_CP"
    return 0
  fi

  echo "${YELLOW}Creating MySQL source connection profile...${RESET}"

  gcloud database-migration connection-profiles create mysql "$SOURCE_CP" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="MySQL Source Profile" \
    --host="$SOURCE_EXTERNAL_IP" \
    --port="$MYSQL_PORT" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD" \
    --ssl-type=NONE \
    --no-async \
    --quiet ||
    return 1

  ok "Source connection profile created."

  return 0
}

set_source_host() {

  local wanted_host="$1"
  local current_host

  current_host=$(source_profile_host)

  if [[ "$current_host" == "$wanted_host" ]]; then
    ok "Source profile already uses $wanted_host"
    return 0
  fi

  echo "${YELLOW}Updating source connection profile -> $wanted_host${RESET}"

  gcloud database-migration connection-profiles update "$SOURCE_CP" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --host="$wanted_host" \
    --port="$MYSQL_PORT" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD" \
    --quiet >/dev/null ||
    return 1

  for ((i=1; i<=60; i++)); do

    current_host=$(source_profile_host)

    if [[ "$current_host" == "$wanted_host" ]]; then
      ok "Source profile host: $wanted_host"
      return 0
    fi

    sleep 2
  done

  fail "Unable to confirm source profile update."

  return 1
}

# ============================================================
# DESTINATION PROFILE
# ============================================================

create_destination_profile() {

  local profile="$1"
  local instance="$2"
  local display_name="$3"

  if profile_exists "$profile"; then
    ok "Destination profile already exists: $profile"
    return 0
  fi

  echo "${YELLOW}Creating destination connection profile: $profile${RESET}"

  gcloud database-migration connection-profiles create mysql "$profile" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="$display_name" \
    --cloudsql-instance="$instance" \
    --no-async \
    --quiet ||
    return 1

  ok "Destination connection profile created."

  return 0
}

# ============================================================
# DEMOTE EXISTING CLOUD SQL
# ============================================================

demote_destination_if_required() {

  local job="$1"
  local instance="$2"

  local instance_type

  instance_type=$(
    gcloud sql instances describe "$instance" \
      --project="$PROJECT_ID" \
      --format='value(instanceType)' \
      2>/dev/null || true
  )

  if [[ "$instance_type" == "READ_REPLICA_INSTANCE" ]]; then
    ok "$instance is already demoted."
    return 0
  fi

  echo "${YELLOW}Demoting existing Cloud SQL destination...${RESET}"

  dms_action demote-destination "$job" ||
    return 1

  ok "Destination demotion completed."

  return 0
}

# ============================================================
# MYSQL QUERY ON SOURCE
# ============================================================

source_query() {

  local sql="$1"

  gcloud compute ssh "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --quiet \
    --command="
      MYSQL_PWD='$MYSQL_PASSWORD' \
      mysql \
        -u'$MYSQL_USER' \
        -Nse \"$sql\"
    "
}

# ============================================================
# REQUIRED APIS
# ============================================================

enable_apis() {

  section "Preparing Google Cloud APIs"

  gcloud services enable \
    datamigration.googleapis.com \
    sqladmin.googleapis.com \
    compute.googleapis.com \
    servicenetworking.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

  ok "Required APIs enabled."
}

# ============================================================
# FIREWALL
# ============================================================

ensure_firewall() {

  section "Preparing MySQL network access"

  local fw_rule="dms-mysql-source-3306"
  local vm_tag="dms-mysql-source"

  gcloud compute instances add-tags "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --tags="$vm_tag" \
    --quiet >/dev/null 2>&1 || true

  if gcloud compute firewall-rules describe "$fw_rule" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then

    ok "Firewall rule already exists."
    return 0
  fi

  gcloud compute firewall-rules create "$fw_rule" \
    --project="$PROJECT_ID" \
    --network="$NETWORK_NAME" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:3306 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$vm_tag" \
    --quiet ||
    return 1

  ok "MySQL TCP/3306 firewall rule created."

  return 0
}

# ============================================================
# STATUS
# ============================================================

show_status() {

  section "DATABASE MIGRATION STATUS"

  echo "${BOLD}Connection profiles${RESET}"
  echo

  gcloud database-migration connection-profiles list \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='table(displayName,name.basename(),state)' \
    2>/dev/null || true

  echo
  echo "${BOLD}Migration jobs${RESET}"
  echo

  gcloud database-migration migration-jobs list \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='table(displayName,type,state,phase)' \
    2>/dev/null || true

  echo
  echo "${BOLD}Cloud SQL instances${RESET}"
  echo

  gcloud sql instances list \
    --project="$PROJECT_ID" \
    --filter="name=($ONE_TIME_TARGET $CONTINUOUS_TARGET)" \
    --format='table(name,instanceType,state,region,databaseVersion)' \
    2>/dev/null || true

  echo
  echo "${CYAN}${BOLD}© ePlus.DEV${RESET}"
}

# ============================================================
# TASK 2
#
# Includes ensuring Task 1 source profile is correctly configured.
# Stops after one-time job becomes COMPLETED.
# ============================================================

run_task2() {

  enable_apis

  ensure_firewall ||
    die "Unable to prepare source firewall."

  section "TASK 1 - Source MySQL connection profile"

  create_source_profile ||
    die "Unable to create source connection profile."

  # Task 1 + Task 2 use EXTERNAL IP.
  set_source_host "$SOURCE_EXTERNAL_IP" ||
    die "Unable to configure source external IP."

  echo
  echo "${YELLOW}Checking source database...${RESET}"

  local source_count

  source_count=$(
    source_query \
      "SELECT COUNT(*) FROM customers_data.customers;" |
      tail -n1
  )

  echo "${WHITE}customers_data.customers : ${CYAN}${source_count:-UNKNOWN}${RESET}"

  if [[ "$source_count" == "5030" ]]; then
    ok "Source row count = 5030."
  else
    warn "Expected row count is 5030."
  fi

  section "TASK 2 - One-time migration"

  create_destination_profile \
    "$ONE_TIME_DEST_CP" \
    "$ONE_TIME_TARGET" \
    "One Time Destination" ||
    die "Unable to create one-time destination profile."

  if ! job_exists "$ONE_TIME_JOB"; then

    echo "${YELLOW}Creating one-time migration job...${RESET}"

    gcloud database-migration migration-jobs create "$ONE_TIME_JOB" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --display-name="$ONE_TIME_JOB" \
      --type=ONE_TIME \
      --source="$SOURCE_CP" \
      --destination="$ONE_TIME_DEST_CP" \
      --static-ip \
      --no-async \
      --quiet ||
      die "Unable to create one-time migration job."

    ok "One-time migration job created."

  else

    warn "One-time migration job already exists."

  fi

  local state

  state=$(job_state "$ONE_TIME_JOB")

  echo "${WHITE}Current state: ${YELLOW}${state:-UNKNOWN}${RESET}"

  case "$state" in

    COMPLETED)

      ok "One-time migration is already COMPLETED."
      ;;

    NOT_STARTED|DRAFT)

      demote_destination_if_required \
        "$ONE_TIME_JOB" \
        "$ONE_TIME_TARGET" ||
        die "Unable to demote one-time destination."

      echo
      echo "${YELLOW}Verifying one-time migration job...${RESET}"

      dms_action verify "$ONE_TIME_JOB" ||
        die "One-time migration verification failed."

      echo
      echo "${YELLOW}Starting one-time migration...${RESET}"

      dms_action start "$ONE_TIME_JOB" ||
        die "Unable to start one-time migration."

      wait_for_state "$ONE_TIME_JOB" "COMPLETED" ||
        die "One-time migration did not complete."

      ;;

    RUNNING|STARTING)

      warn "One-time migration is already running."

      wait_for_state "$ONE_TIME_JOB" "COMPLETED" ||
        die "One-time migration did not complete."

      ;;

    FAILED)

      warn "Restarting failed one-time migration."

      dms_action restart "$ONE_TIME_JOB" ||
        die "Unable to restart one-time migration."

      wait_for_state "$ONE_TIME_JOB" "COMPLETED" ||
        die "One-time migration did not complete."

      ;;

    STOPPED)

      warn "Restarting stopped one-time migration."

      dms_action restart "$ONE_TIME_JOB" ||
        die "Unable to restart one-time migration."

      wait_for_state "$ONE_TIME_JOB" "COMPLETED" ||
        die "One-time migration did not complete."

      ;;

    *)

      die "Unexpected one-time job state: $state"
      ;;

  esac

  # Keep Task 1/2 profile on EXTERNAL IP.
  set_source_host "$SOURCE_EXTERNAL_IP" ||
    die "Unable to restore source external IP."

  echo
  gcloud database-migration migration-jobs describe "$ONE_TIME_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='yaml(displayName,type,state,phase,staticIpConnectivity)'

  finish \
    "TASK 1 + TASK 2 COMPLETE" \
    "One-time migration is COMPLETED. Check Task 1 and Task 2 in the lab before running Task 3."
}

# ============================================================
# TASK 3
#
# Continuous migration with VPC Peering.
# Stops while job is RUNNING / CDC.
# ============================================================

run_task3() {

  section "TASK 3 - Continuous migration using VPC Peering"

  if ! job_exists "$ONE_TIME_JOB"; then
    die "Task 2 migration job does not exist."
  fi

  if [[ "$(job_state "$ONE_TIME_JOB")" != "COMPLETED" ]]; then
    die "Task 2 is not completed yet."
  fi

  create_source_profile ||
    die "Unable to locate/create source connection profile."

  # Same connection profile, PRIVATE IP for VPC Peering.
  set_source_host "$SOURCE_INTERNAL_IP" ||
    die "Unable to configure source internal IP."

  create_destination_profile \
    "$CONTINUOUS_DEST_CP" \
    "$CONTINUOUS_TARGET" \
    "Continuous Destination" ||
    die "Unable to create continuous destination profile."

  if ! job_exists "$CONTINUOUS_JOB"; then

    echo "${YELLOW}Creating continuous migration job...${RESET}"

    gcloud database-migration migration-jobs create "$CONTINUOUS_JOB" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --display-name="$CONTINUOUS_JOB" \
      --type=CONTINUOUS \
      --source="$SOURCE_CP" \
      --destination="$CONTINUOUS_DEST_CP" \
      --peer-vpc="$NETWORK_URI" \
      --no-async \
      --quiet ||
      die "Unable to create continuous migration job."

    ok "Continuous migration job created."

  else

    warn "Continuous migration job already exists."

  fi

  local state
  local phase

  state=$(job_state "$CONTINUOUS_JOB")
  phase=$(job_phase "$CONTINUOUS_JOB")

  echo "${WHITE}Current state: ${YELLOW}${state:-UNKNOWN}${RESET}"
  echo "${WHITE}Current phase: ${YELLOW}${phase:-N/A}${RESET}"

  case "$state" in

    NOT_STARTED|DRAFT)

      demote_destination_if_required \
        "$CONTINUOUS_JOB" \
        "$CONTINUOUS_TARGET" ||
        die "Unable to demote continuous destination."

      echo
      echo "${YELLOW}Verifying continuous migration job...${RESET}"

      dms_action verify "$CONTINUOUS_JOB" ||
        die "Continuous migration verification failed."

      echo
      echo "${YELLOW}Starting continuous migration...${RESET}"

      dms_action start "$CONTINUOUS_JOB" ||
        die "Unable to start continuous migration."

      wait_for_cdc "$CONTINUOUS_JOB" ||
        die "Continuous migration did not reach CDC."

      ;;

    RUNNING)

      if [[ "$phase" != "CDC" ]]; then

        wait_for_cdc "$CONTINUOUS_JOB" ||
          die "Continuous migration did not reach CDC."

      else

        ok "Continuous migration is already RUNNING / CDC."

      fi

      ;;

    FAILED)

      warn "Restarting failed continuous migration."

      dms_action restart "$CONTINUOUS_JOB" ||
        die "Unable to restart continuous migration."

      wait_for_cdc "$CONTINUOUS_JOB" ||
        die "Continuous migration did not reach CDC."

      ;;

    STOPPED)

      if [[ "$phase" == "CDC" ]]; then

        warn "Resuming continuous migration."

        dms_action resume "$CONTINUOUS_JOB" ||
          die "Unable to resume continuous migration."

      else

        warn "Restarting continuous migration."

        dms_action restart "$CONTINUOUS_JOB" ||
          die "Unable to restart continuous migration."

      fi

      wait_for_cdc "$CONTINUOUS_JOB" ||
        die "Continuous migration did not reach CDC."

      ;;

    COMPLETED)

      warn "Continuous migration has already been promoted."
      ;;

    *)

      die "Unexpected continuous job state: $state"
      ;;

  esac

  echo
  gcloud database-migration migration-jobs describe "$CONTINUOUS_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='yaml(displayName,type,state,phase,vpcPeeringConnectivity)'

  finish \
    "TASK 3 COMPLETE" \
    "Continuous migration is RUNNING / CDC. Check Task 3 before running Task 4."
}

# ============================================================
# TASK 4
#
# Update source data and leave continuous job RUNNING.
# ============================================================

run_task4() {

  section "TASK 4 - Verify continuous replication"

  if ! job_exists "$CONTINUOUS_JOB"; then
    die "Continuous migration job does not exist."
  fi

  set_source_host "$SOURCE_INTERNAL_IP" ||
    die "Unable to configure source internal IP."

  local state
  local phase

  state=$(job_state "$CONTINUOUS_JOB")
  phase=$(job_phase "$CONTINUOUS_JOB")

  if [[ "$state" != "RUNNING" ]]; then
    die "Continuous migration must be RUNNING. Current state: $state"
  fi

  if [[ "$phase" != "CDC" ]]; then

    wait_for_cdc "$CONTINUOUS_JOB" ||
      die "Continuous migration did not reach CDC."

  fi

  echo
  echo "${YELLOW}Executing required source update...${RESET}"

  source_query "
    USE customers_data;
    UPDATE customers
    SET gender='FEMALE'
    WHERE addressKey=934;
    SELECT addressKey, gender
    FROM customers
    WHERE addressKey=934;
  " ||
    die "Unable to update source MySQL database."

  echo
  echo "${YELLOW}Confirming source value...${RESET}"

  local gender

  gender=$(
    source_query "
      SELECT gender
      FROM customers_data.customers
      WHERE addressKey=934;
    " |
    tail -n1
  )

  echo "${WHITE}addressKey : ${CYAN}934${RESET}"
  echo "${WHITE}gender     : ${CYAN}${gender:-UNKNOWN}${RESET}"

  [[ "$gender" != "FEMALE" ]] &&
    die "Source update was not confirmed."

  ok "Source row updated successfully."

  echo
  echo "${YELLOW}Waiting 75 seconds for CDC propagation...${RESET}"

  for ((remaining=75; remaining>=1; remaining--)); do

    printf "\r${YELLOW}Replication wait: %02d seconds remaining...${RESET}" \
      "$remaining"

    sleep 1
  done

  echo

  state=$(job_state "$CONTINUOUS_JOB")
  phase=$(job_phase "$CONTINUOUS_JOB")

  echo
  echo "${WHITE}Migration state : ${CYAN}$state${RESET}"
  echo "${WHITE}Migration phase : ${CYAN}${phase:-N/A}${RESET}"

  finish \
    "TASK 4 COMPLETE" \
    "addressKey=934 is FEMALE and CDC has been given time to replicate. Check Task 4 before running Task 5."
}

# ============================================================
# TASK 5
#
# Promote continuous destination.
# ============================================================

run_task5() {

  section "TASK 5 - Promote Cloud SQL destination"

  if ! job_exists "$CONTINUOUS_JOB"; then
    die "Continuous migration job does not exist."
  fi

  local state
  local phase

  state=$(job_state "$CONTINUOUS_JOB")
  phase=$(job_phase "$CONTINUOUS_JOB")

  if [[ "$state" == "COMPLETED" ]]; then

    ok "Continuous migration is already promoted."

    finish \
      "TASK 5 COMPLETE" \
      "Continuous Cloud SQL destination is already standalone."

    return 0
  fi

  if [[ "$state" != "RUNNING" ]]; then
    die "Continuous migration must be RUNNING before promotion. Current state: $state"
  fi

  if [[ "$phase" != "CDC" ]]; then

    wait_for_cdc "$CONTINUOUS_JOB" ||
      die "Continuous migration is not ready for promotion."

  fi

  echo
  echo "${YELLOW}Checking Task 4 source value...${RESET}"

  local gender

  gender=$(
    source_query "
      SELECT gender
      FROM customers_data.customers
      WHERE addressKey=934;
    " |
    tail -n1
  )

  echo "${WHITE}addressKey 934 gender : ${CYAN}${gender:-UNKNOWN}${RESET}"

  [[ "$gender" != "FEMALE" ]] &&
    die "Task 4 has not been completed."

  echo
  echo "${YELLOW}Promoting continuous destination...${RESET}"

  dms_action promote "$CONTINUOUS_JOB" ||
    die "Unable to promote continuous migration."

  wait_for_state "$CONTINUOUS_JOB" "COMPLETED" ||
    die "Promotion did not complete."

  echo
  echo "${BOLD}Migration job:${RESET}"

  gcloud database-migration migration-jobs describe "$CONTINUOUS_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='yaml(displayName,type,state,phase)'

  echo
  echo "${BOLD}Cloud SQL destination:${RESET}"

  gcloud sql instances describe "$CONTINUOUS_TARGET" \
    --project="$PROJECT_ID" \
    --format='yaml(name,state,instanceType,masterInstanceName,region)'

  finish \
    "TASK 5 COMPLETE" \
    "Continuous destination has been promoted to standalone Cloud SQL."
}

# ============================================================
# EXECUTE
# ============================================================

case "$MODE" in

  task2)
    run_task2
    ;;

  task3)
    run_task3
    ;;

  task4)
    run_task4
    ;;

  task5)
    run_task5
    ;;

  status)
    show_status
    ;;

esac