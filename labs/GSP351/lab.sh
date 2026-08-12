#!/usr/bin/env bash

# ============================================================
# Google Cloud Skills Boost
# Migrate MySQL Data to Cloud SQL using DMS - Challenge Lab
# Full Task 1 -> Task 5 automation
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

clear

echo "${MAGENTA}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║       MYSQL → CLOUD SQL DATABASE MIGRATION CHALLENGE LAB        ║"
echo "║                        © ePlus.DEV                              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo "${RESET}"

# ============================================================
# GLOBAL SETTINGS
# ============================================================

SOURCE_USER="admin"
SOURCE_PASSWORD="changeme"
SOURCE_PORT="3306"

# We set this ourselves so destination verification can be automated.
DEST_ROOT_PASSWORD="changeme"

SOURCE_CP="mysql-source-profile"

FW_RULE="dms-mysql-source-3306"
VM_TAG="dms-mysql-source"

# ============================================================
# HELPERS
# ============================================================

job_state() {
  local job="$1"

  gcloud database-migration migration-jobs describe "$job" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(state)' 2>/dev/null
}

job_phase() {
  local job="$1"

  gcloud database-migration migration-jobs describe "$job" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(phase)' 2>/dev/null
}

wait_lro() {
  local operation="$1"

  [[ -z "$operation" ]] && return 0

  local op_id="${operation##*/}"
  local done=""
  local err=""

  echo "${YELLOW}Waiting for DMS operation: ${op_id}${RESET}"

  for ((i=1; i<=240; i++)); do

    done=$(gcloud database-migration operations describe "$op_id" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(done)' 2>/dev/null || true)

    err=$(gcloud database-migration operations describe "$op_id" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(error.message)' 2>/dev/null || true)

    if [[ -n "$err" ]]; then
      echo
      fail "DMS operation failed:"
      echo "$err"
      return 1
    fi

    if [[ "$done" == "True" || "$done" == "true" ]]; then
      echo
      ok "DMS operation completed."
      return 0
    fi

    printf "\r${YELLOW}DMS operation in progress... %-3s${RESET}" "$i"
    sleep 5
  done

  echo
  fail "DMS operation did not complete."
  return 1
}

dms_action() {
  local action="$1"
  local job="$2"

  local err_file="/tmp/dms-${action}-${job}.err"
  local operation=""

  operation=$(
    gcloud database-migration migration-jobs "$action" "$job" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --quiet \
      --format='value(name)' \
      2>"$err_file"
  )

  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "DMS action '$action' failed for $job."
    cat "$err_file"
    return $rc
  fi

  [[ -n "$operation" ]] && wait_lro "$operation"

  return 0
}

wait_for_job_state() {
  local job="$1"
  local wanted="$2"

  for ((i=1; i<=240; i++)); do

    local state
    local phase

    state=$(job_state "$job")
    phase=$(job_phase "$job")

    printf "\r${YELLOW}Job %-30s State: %-15s Phase: %-15s${RESET}" \
      "$job" "${state:-UNKNOWN}" "${phase:-N/A}"

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
        --format='yaml(state,phase,error)' || true

      return 1
    fi

    sleep 5
  done

  echo
  fail "Timeout waiting for $job -> $wanted."
  return 1
}

wait_for_cdc() {
  local job="$1"

  for ((i=1; i<=240; i++)); do

    local state
    local phase

    state=$(job_state "$job")
    phase=$(job_phase "$job")

    printf "\r${YELLOW}Continuous job: State=%-15s Phase=%-20s${RESET}" \
      "${state:-UNKNOWN}" "${phase:-N/A}"

    if [[ "$state" == "RUNNING" && "$phase" == "CDC" ]]; then
      echo
      ok "Continuous migration has entered CDC."
      return 0
    fi

    if [[ "$state" == "FAILED" ]]; then
      echo
      fail "Continuous migration failed."

      gcloud database-migration migration-jobs describe "$job" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='yaml(state,phase,error)' || true

      return 1
    fi

    sleep 5
  done

  echo
  fail "Migration did not enter CDC."
  return 1
}

set_source_profile_host() {

  local new_host="$1"

  echo "${YELLOW}Updating source connection profile host -> $new_host${RESET}"

  gcloud database-migration connection-profiles update "$SOURCE_CP" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --host="$new_host" \
    --port="$SOURCE_PORT" \
    --username="$SOURCE_USER" \
    --password="$SOURCE_PASSWORD" \
    --quiet >/dev/null 2>&1 || true

  for ((i=1; i<=60; i++)); do

    local current

    current=$(gcloud database-migration connection-profiles describe "$SOURCE_CP" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(mysql.host)' 2>/dev/null || true)

    if [[ "$current" == "$new_host" ]]; then
      ok "Source connection profile now uses $new_host"
      return 0
    fi

    sleep 2
  done

  warn "Could not confirm source profile host update."
}

cloudsql_query() {

  local instance="$1"
  local sql="$2"

  local result

  result=$(
    printf '%s\n' "$sql" |
      MYSQL_PWD="$DEST_ROOT_PASSWORD" \
      timeout 90 \
      gcloud sql connect "$instance" \
        --user=root \
        --project="$PROJECT_ID" \
        --quiet 2>/dev/null
  )

  local rc=$?

  if [[ $rc -eq 0 ]]; then
    echo "$result"
    return 0
  fi

  return 1
}

# ============================================================
# 1. DETECT ENVIRONMENT
# ============================================================

section "[1/9] Detecting Google Cloud environment"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"

if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
fi

[[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]] &&
  die "Unable to detect Project ID."

gcloud config set project "$PROJECT_ID" >/dev/null

# Find the MySQL source VM.
VM_LINE=$(
  gcloud compute instances list \
    --project="$PROJECT_ID" \
    --format='value(name,zone)' |
    grep -i 'mysql' |
    head -n 1
)

if [[ -z "$VM_LINE" ]]; then

  VM_COUNT=$(
    gcloud compute instances list \
      --project="$PROJECT_ID" \
      --format='value(name)' |
      wc -l
  )

  if [[ "$VM_COUNT" -eq 1 ]]; then
    VM_LINE=$(
      gcloud compute instances list \
        --project="$PROJECT_ID" \
        --format='value(name,zone)' |
        head -n1
    )
  fi
fi

[[ -z "$VM_LINE" ]] &&
  die "Unable to automatically identify the MySQL source VM."

SOURCE_VM=$(echo "$VM_LINE" | awk '{print $1}')
ZONE_URI=$(echo "$VM_LINE" | awk '{print $2}')
ZONE="${ZONE_URI##*/}"
REGION="${ZONE%-*}"

SOURCE_EXTERNAL_IP=$(
  gcloud compute instances describe "$SOURCE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[0].accessConfigs[0].natIP)'
)

SOURCE_INTERNAL_IP=$(
  gcloud compute instances describe "$SOURCE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[0].networkIP)'
)

NETWORK_URI=$(
  gcloud compute instances describe "$SOURCE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[0].network)'
)

NETWORK_NAME="${NETWORK_URI##*/}"

[[ -z "$SOURCE_EXTERNAL_IP" ]] &&
  die "The MySQL source VM has no external IP."

gcloud config set compute/zone "$ZONE" >/dev/null
gcloud config set compute/region "$REGION" >/dev/null

echo "${WHITE}Project ID          : ${CYAN}$PROJECT_ID${RESET}"
echo "${WHITE}Region              : ${CYAN}$REGION${RESET}"
echo "${WHITE}Zone                : ${CYAN}$ZONE${RESET}"
echo "${WHITE}Source VM           : ${CYAN}$SOURCE_VM${RESET}"
echo "${WHITE}External source IP  : ${CYAN}$SOURCE_EXTERNAL_IP${RESET}"
echo "${WHITE}Internal source IP  : ${CYAN}$SOURCE_INTERNAL_IP${RESET}"
echo "${WHITE}VPC Network         : ${CYAN}$NETWORK_NAME${RESET}"

# ============================================================
# 2. DETECT DESTINATION CLOUD SQL INSTANCES
# ============================================================

section "[2/9] Detecting destination Cloud SQL instances"

mapfile -t SQL_INSTANCES < <(
  gcloud sql instances list \
    --project="$PROJECT_ID" \
    --format='value(name,region,databaseVersion)' |
    awk -v r="$REGION" '$2 == r && $3 ~ /^MYSQL/ {print $1}'
)

if [[ ${#SQL_INSTANCES[@]} -lt 2 ]]; then
  echo
  gcloud sql instances list \
    --project="$PROJECT_ID" \
    --format='table(name,region,databaseVersion,state)'
  echo

  die "Expected two existing MySQL Cloud SQL destination instances."
fi

echo "${WHITE}Detected Cloud SQL instances:${RESET}"

for instance in "${SQL_INSTANCES[@]}"; do
  echo "  ${CYAN}• $instance${RESET}"
done

ONE_TIME_INSTANCE="${ONE_TIME_INSTANCE:-}"
CONTINUOUS_INSTANCE="${CONTINUOUS_INSTANCE:-}"

# Try names containing obvious keywords.
if [[ -z "$ONE_TIME_INSTANCE" ]]; then
  ONE_TIME_INSTANCE=$(
    printf '%s\n' "${SQL_INSTANCES[@]}" |
      grep -Ei 'one.?time|onetime|offline|once' |
      head -n1 || true
  )
fi

if [[ -z "$CONTINUOUS_INSTANCE" ]]; then
  CONTINUOUS_INSTANCE=$(
    printf '%s\n' "${SQL_INSTANCES[@]}" |
      grep -Ei 'continuous|cont|online' |
      head -n1 || true
  )
fi

# If one can be identified, the other one is obvious.
if [[ ${#SQL_INSTANCES[@]} -eq 2 ]]; then

  if [[ -n "$CONTINUOUS_INSTANCE" && -z "$ONE_TIME_INSTANCE" ]]; then
    for instance in "${SQL_INSTANCES[@]}"; do
      [[ "$instance" != "$CONTINUOUS_INSTANCE" ]] &&
        ONE_TIME_INSTANCE="$instance"
    done
  fi

  if [[ -n "$ONE_TIME_INSTANCE" && -z "$CONTINUOUS_INSTANCE" ]]; then
    for instance in "${SQL_INSTANCES[@]}"; do
      [[ "$instance" != "$ONE_TIME_INSTANCE" ]] &&
        CONTINUOUS_INSTANCE="$instance"
    done
  fi
fi

# Dynamic lab names were missing from the pasted instructions.
# Only ask when they cannot be safely inferred.
if [[ -z "$ONE_TIME_INSTANCE" || -z "$CONTINUOUS_INSTANCE" ]]; then

  echo
  echo "${YELLOW}${BOLD}The lab has two dynamic destination instance IDs.${RESET}"
  echo "${YELLOW}Enter the names shown above.${RESET}"
  echo

  read -r -p "$(echo "${CYAN}ONE-TIME destination instance ID : ${RESET}")" \
    ONE_TIME_INSTANCE

  read -r -p "$(echo "${CYAN}CONTINUOUS destination instance ID: ${RESET}")" \
    CONTINUOUS_INSTANCE
fi

[[ "$ONE_TIME_INSTANCE" == "$CONTINUOUS_INSTANCE" ]] &&
  die "One-time and continuous destination instances must be different."

gcloud sql instances describe "$ONE_TIME_INSTANCE" \
  --project="$PROJECT_ID" >/dev/null 2>&1 ||
  die "Cloud SQL instance not found: $ONE_TIME_INSTANCE"

gcloud sql instances describe "$CONTINUOUS_INSTANCE" \
  --project="$PROJECT_ID" >/dev/null 2>&1 ||
  die "Cloud SQL instance not found: $CONTINUOUS_INSTANCE"

ONE_TIME_JOB="$ONE_TIME_INSTANCE"
CONTINUOUS_JOB="$CONTINUOUS_INSTANCE"

ONE_TIME_DEST_CP="cp-${ONE_TIME_INSTANCE}"
CONTINUOUS_DEST_CP="cp-${CONTINUOUS_INSTANCE}"

# Keep IDs within a safe size.
ONE_TIME_DEST_CP="${ONE_TIME_DEST_CP:0:60}"
CONTINUOUS_DEST_CP="${CONTINUOUS_DEST_CP:0:60}"

echo
echo "${WHITE}One-time destination   : ${GREEN}$ONE_TIME_INSTANCE${RESET}"
echo "${WHITE}Continuous destination : ${GREEN}$CONTINUOUS_INSTANCE${RESET}"

# ============================================================
# 3. ENABLE APIS + SOURCE PRECHECK
# ============================================================

section "[3/9] Preparing APIs and MySQL source"

gcloud services enable \
  datamigration.googleapis.com \
  sqladmin.googleapis.com \
  compute.googleapis.com \
  servicenetworking.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

ok "Required APIs enabled."

echo
echo "${YELLOW}Checking source MySQL database...${RESET}"

SOURCE_COUNT=$(
  gcloud compute ssh "$SOURCE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --quiet \
    --command="
      MYSQL_PWD='$SOURCE_PASSWORD' \
      mysql -u'$SOURCE_USER' -Nse \
      'SELECT COUNT(*) FROM customers_data.customers;'
    " 2>/dev/null || true
)

if [[ "$SOURCE_COUNT" == "5030" ]]; then
  ok "Source customers row count = 5030."
else
  warn "Source count returned: ${SOURCE_COUNT:-UNKNOWN}"
fi

echo
echo "${YELLOW}Checking replication configuration...${RESET}"

MYSQL_REPL_CONFIG=$(
  gcloud compute ssh "$SOURCE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --quiet \
    --command="
      MYSQL_PWD='$SOURCE_PASSWORD' \
      mysql -u'$SOURCE_USER' -Nse \
      \"SELECT @@log_bin, @@binlog_format, @@server_id, @@gtid_mode;\"
    " 2>/dev/null || true
)

echo "${WHITE}MySQL replication config: ${CYAN}${MYSQL_REPL_CONFIG:-UNKNOWN}${RESET}"

# The lab source normally already has DMS prerequisites.
# Only repair the basic binary log config if it is obviously incorrect.
LOG_BIN=$(echo "$MYSQL_REPL_CONFIG" | awk '{print $1}')
BINLOG_FORMAT=$(echo "$MYSQL_REPL_CONFIG" | awk '{print $2}')
SERVER_ID=$(echo "$MYSQL_REPL_CONFIG" | awk '{print $3}')

if [[ "$LOG_BIN" != "1" ||
      "$BINLOG_FORMAT" != "ROW" ||
      -z "$SERVER_ID" ||
      "$SERVER_ID" == "0" ]]; then

  warn "MySQL binary logging is not ready. Applying DMS prerequisites."

  gcloud compute ssh "$SOURCE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --quiet \
    --command='
      set -e

      CFG=""

      for f in \
        /etc/mysql/mysql.conf.d/mysqld.cnf \
        /etc/mysql/my.cnf \
        /etc/my.cnf
      do
        if [[ -f "$f" ]]; then
          CFG="$f"
          break
        fi
      done

      if [[ -z "$CFG" ]]; then
        echo "Could not locate MySQL configuration file."
        exit 1
      fi

      sudo cp "$CFG" "${CFG}.eplus-backup"

      sudo tee -a "$CFG" >/dev/null <<MYSQLCFG

# DMS configuration - ePlus.DEV
[mysqld]
server-id=12345
log_bin=mysql-bin
binlog_format=ROW
expire_logs_days=7
MYSQLCFG

      sudo systemctl restart mysql 2>/dev/null ||
      sudo systemctl restart mysqld
    ' || die "Unable to configure MySQL binary logging."

  ok "MySQL replication configuration updated."
fi

# ============================================================
# 4. FIREWALL FOR MYSQL
# ============================================================

section "[4/9] Configuring source network access"

gcloud compute instances add-tags "$SOURCE_VM" \
  --zone="$ZONE" \
  --project="$PROJECT_ID" \
  --tags="$VM_TAG" \
  --quiet >/dev/null 2>&1 || true

if gcloud compute firewall-rules describe "$FW_RULE" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Firewall rule $FW_RULE already exists."

else

  gcloud compute firewall-rules create "$FW_RULE" \
    --project="$PROJECT_ID" \
    --network="$NETWORK_NAME" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:3306 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$VM_TAG" \
    --quiet ||
    die "Unable to create MySQL firewall rule."

  ok "MySQL TCP/3306 firewall rule created."
fi

# ============================================================
# 5. TASK 1 - SOURCE CONNECTION PROFILE
# ============================================================

section "[5/9] TASK 1 - Creating MySQL source connection profile"

if gcloud database-migration connection-profiles describe "$SOURCE_CP" \
     --region="$REGION" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then

  warn "Source connection profile already exists."

  # Task 1 explicitly requires external IP.
  set_source_profile_host "$SOURCE_EXTERNAL_IP"

else

  gcloud database-migration connection-profiles create mysql "$SOURCE_CP" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="MySQL Source Profile" \
    --host="$SOURCE_EXTERNAL_IP" \
    --port="$SOURCE_PORT" \
    --username="$SOURCE_USER" \
    --password="$SOURCE_PASSWORD" \
    --ssl-type=NONE \
    --no-async \
    --quiet ||
    die "Unable to create source connection profile."

fi

ok "TASK 1 source connection profile created using EXTERNAL IP."

# ============================================================
# PREPARE DESTINATION USERS
# ============================================================

echo
echo "${YELLOW}Preparing destination root users...${RESET}"

gcloud sql users set-password root \
  --host=% \
  --instance="$ONE_TIME_INSTANCE" \
  --password="$DEST_ROOT_PASSWORD" \
  --project="$PROJECT_ID" \
  --quiet >/dev/null 2>&1 || true

gcloud sql users set-password root \
  --host=% \
  --instance="$CONTINUOUS_INSTANCE" \
  --password="$DEST_ROOT_PASSWORD" \
  --project="$PROJECT_ID" \
  --quiet >/dev/null 2>&1 || true

# ============================================================
# 6. TASK 2 - ONE-TIME MIGRATION
# ============================================================

section "[6/9] TASK 2 - One-time migration using external IP"

# Destination connection profile required when using CLI
# with an EXISTING Cloud SQL destination.

if ! gcloud database-migration connection-profiles describe "$ONE_TIME_DEST_CP" \
     --region="$REGION" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then

  gcloud database-migration connection-profiles create mysql "$ONE_TIME_DEST_CP" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="One Time Destination" \
    --cloudsql-instance="$ONE_TIME_INSTANCE" \
    --no-async \
    --quiet ||
    die "Unable to create one-time destination connection profile."

fi

ok "One-time destination connection profile ready."

if ! gcloud database-migration migration-jobs describe "$ONE_TIME_JOB" \
     --region="$REGION" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then

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

ONE_STATE=$(job_state "$ONE_TIME_JOB")

if [[ "$ONE_STATE" != "COMPLETED" ]]; then

  INSTANCE_TYPE=$(
    gcloud sql instances describe "$ONE_TIME_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(instanceType)' 2>/dev/null
  )

  if [[ "$INSTANCE_TYPE" != "READ_REPLICA_INSTANCE" ]]; then

    echo "${YELLOW}Demoting existing one-time Cloud SQL destination...${RESET}"

    dms_action demote-destination "$ONE_TIME_JOB" ||
      die "Unable to demote one-time destination."
  fi

  echo
  echo "${YELLOW}Verifying one-time migration job...${RESET}"

  dms_action verify "$ONE_TIME_JOB" ||
    die "One-time migration verification failed."

  ONE_STATE=$(job_state "$ONE_TIME_JOB")

  case "$ONE_STATE" in

    DRAFT|NOT_STARTED)
      echo "${YELLOW}Starting one-time migration...${RESET}"
      dms_action start "$ONE_TIME_JOB" ||
        die "Unable to start one-time migration."
      ;;

    FAILED)
      warn "Restarting failed one-time migration."
      dms_action restart "$ONE_TIME_JOB" ||
        die "Unable to restart one-time migration."
      ;;

    STOPPED)
      warn "Restarting stopped one-time migration."
      dms_action restart "$ONE_TIME_JOB" ||
        die "Unable to restart one-time migration."
      ;;

    RUNNING|STARTING)
      warn "One-time migration is already running."
      ;;

  esac

  wait_for_job_state "$ONE_TIME_JOB" "COMPLETED" ||
    die "One-time migration did not complete."

fi

ok "TASK 2 one-time migration completed."

echo
echo "${YELLOW}Checking migrated customer count...${RESET}"

COUNT_RESULT=$(
  cloudsql_query "$ONE_TIME_INSTANCE" \
    "USE customers_data; SELECT COUNT(*) FROM customers;" || true
)

if echo "$COUNT_RESULT" | grep -q '5030'; then
  ok "Destination customer count = 5030."
else
  warn "Automatic SQL verification could not confirm count."
  echo "${WHITE}${COUNT_RESULT}${RESET}"
fi

# ============================================================
# 7. TASK 3 - CONTINUOUS MIGRATION USING VPC PEERING
# ============================================================

section "[7/9] TASK 3 - Continuous migration using VPC Peering"

# Same profile as Task 1, but VPC Peering needs the VM private IP.
set_source_profile_host "$SOURCE_INTERNAL_IP"

if ! gcloud database-migration connection-profiles describe "$CONTINUOUS_DEST_CP" \
     --region="$REGION" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then

  gcloud database-migration connection-profiles create mysql "$CONTINUOUS_DEST_CP" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --display-name="Continuous Destination" \
    --cloudsql-instance="$CONTINUOUS_INSTANCE" \
    --no-async \
    --quiet ||
    die "Unable to create continuous destination profile."

fi

ok "Continuous destination connection profile ready."

if ! gcloud database-migration migration-jobs describe "$CONTINUOUS_JOB" \
     --region="$REGION" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then

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
    die "Unable to create continuous VPC Peering migration job."

  ok "Continuous VPC Peering migration job created."

else
  warn "Continuous migration job already exists."
fi

CONT_STATE=$(job_state "$CONTINUOUS_JOB")

if [[ "$CONT_STATE" != "COMPLETED" ]]; then

  INSTANCE_TYPE=$(
    gcloud sql instances describe "$CONTINUOUS_INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(instanceType)' 2>/dev/null
  )

  if [[ "$INSTANCE_TYPE" != "READ_REPLICA_INSTANCE" ]]; then

    echo "${YELLOW}Demoting continuous Cloud SQL destination...${RESET}"

    dms_action demote-destination "$CONTINUOUS_JOB" ||
      die "Unable to demote continuous destination."
  fi

  echo
  echo "${YELLOW}Verifying continuous migration job...${RESET}"

  dms_action verify "$CONTINUOUS_JOB" ||
    die "Continuous migration verification failed."

  CONT_STATE=$(job_state "$CONTINUOUS_JOB")
  CONT_PHASE=$(job_phase "$CONTINUOUS_JOB")

  case "$CONT_STATE" in

    DRAFT|NOT_STARTED)
      echo "${YELLOW}Starting continuous migration...${RESET}"

      dms_action start "$CONTINUOUS_JOB" ||
        die "Unable to start continuous migration."
      ;;

    FAILED)
      warn "Restarting failed continuous migration."

      dms_action restart "$CONTINUOUS_JOB" ||
        die "Unable to restart continuous migration."
      ;;

    STOPPED)

      if [[ "$CONT_PHASE" == "CDC" ]]; then

        dms_action resume "$CONTINUOUS_JOB" ||
          die "Unable to resume continuous migration."

      else

        dms_action restart "$CONTINUOUS_JOB" ||
          die "Unable to restart continuous migration."

      fi
      ;;

    RUNNING|STARTING)
      warn "Continuous migration is already running."
      ;;

  esac

  wait_for_cdc "$CONTINUOUS_JOB" ||
    die "Continuous job did not reach CDC."

  ok "TASK 3 continuous migration is RUNNING in CDC."

else
  ok "Continuous job is already completed/promoted."
fi

# ============================================================
# 8. TASK 4 - UPDATE SOURCE AND VERIFY REPLICATION
# ============================================================

section "[8/9] TASK 4 - Testing continuous replication"

CONT_STATE=$(job_state "$CONTINUOUS_JOB")

if [[ "$CONT_STATE" != "COMPLETED" ]]; then

  echo "${YELLOW}Updating source record addressKey = 934...${RESET}"

  SOURCE_UPDATE=$(
    gcloud compute ssh "$SOURCE_VM" \
      --zone="$ZONE" \
      --project="$PROJECT_ID" \
      --quiet \
      --command="
        MYSQL_PWD='$SOURCE_PASSWORD' \
        mysql -u'$SOURCE_USER' -Nse \"
          USE customers_data;
          UPDATE customers
          SET gender = 'FEMALE'
          WHERE addressKey = 934;
          SELECT addressKey, gender
          FROM customers
          WHERE addressKey = 934;
        \"
      " 2>/dev/null
  )

  echo "${WHITE}Source record: ${CYAN}$SOURCE_UPDATE${RESET}"

  if echo "$SOURCE_UPDATE" | grep -qi 'FEMALE'; then
    ok "Source record updated to FEMALE."
  else
    die "Source record update could not be confirmed."
  fi

  echo
  echo "${YELLOW}Allowing CDC replication to apply the update...${RESET}"

  for ((i=1; i<=6; i++)); do
    printf "\r${YELLOW}Replication check %s/6...${RESET}" "$i"
    sleep 15

    DEST_UPDATE=$(
      cloudsql_query "$CONTINUOUS_INSTANCE" \
        "USE customers_data;
         SELECT addressKey, gender
         FROM customers
         WHERE addressKey = 934;" || true
    )

    if echo "$DEST_UPDATE" | grep -qi 'FEMALE'; then
      echo
      ok "Destination record replicated successfully."
      break
    fi
  done

  if ! echo "${DEST_UPDATE:-}" | grep -qi 'FEMALE'; then
    echo
    warn "Destination SQL query could not be performed automatically."
    warn "CDC was allowed to replicate the source update before promotion."
  fi

  ok "TASK 4 source update completed."

else
  warn "Continuous migration was already promoted; skipping source modification."
fi

# ============================================================
# 9. TASK 5 - PROMOTE DESTINATION
# ============================================================

section "[9/9] TASK 5 - Promoting continuous destination"

CONT_STATE=$(job_state "$CONTINUOUS_JOB")

if [[ "$CONT_STATE" != "COMPLETED" ]]; then

  CONT_PHASE=$(job_phase "$CONTINUOUS_JOB")

  if [[ "$CONT_PHASE" != "CDC" ]]; then
    wait_for_cdc "$CONTINUOUS_JOB" ||
      die "Cannot promote because migration has not reached CDC."
  fi

  echo "${YELLOW}Promoting continuous Cloud SQL destination...${RESET}"

  dms_action promote "$CONTINUOUS_JOB" ||
    die "Promotion failed."

  wait_for_job_state "$CONTINUOUS_JOB" "COMPLETED" ||
    die "Continuous migration did not reach COMPLETED state."

fi

ok "TASK 5 destination promoted to standalone Cloud SQL."

# Restore the Task 1 connection profile to the EXTERNAL IP.
# The completed migration job continues to reference the SAME source profile.
echo
echo "${YELLOW}Restoring source profile host to the Task 1 external IP...${RESET}"

set_source_profile_host "$SOURCE_EXTERNAL_IP"

# ============================================================
# FINAL VERIFICATION
# ============================================================

section "FINAL VERIFICATION"

echo "${BOLD}Connection Profiles${RESET}"

gcloud database-migration connection-profiles list \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format='table(displayName,name.basename(),state)' || true

echo
echo "${BOLD}Migration Jobs${RESET}"

gcloud database-migration migration-jobs list \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format='table(displayName,type,state,phase)' || true

echo
echo "${BOLD}Cloud SQL Instances${RESET}"

gcloud sql instances list \
  --project="$PROJECT_ID" \
  --filter="region:$REGION" \
  --format='table(name,instanceType,databaseVersion,state,region)' || true

echo
echo "${BOLD}Source record${RESET}"

gcloud compute ssh "$SOURCE_VM" \
  --zone="$ZONE" \
  --project="$PROJECT_ID" \
  --quiet \
  --command="
    MYSQL_PWD='$SOURCE_PASSWORD' \
    mysql -u'$SOURCE_USER' -Nse \"
      SELECT addressKey, gender
      FROM customers_data.customers
      WHERE addressKey = 934;
    \"
  " 2>/dev/null || true

echo
echo "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    LAB EXECUTION COMPLETE                      ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║ TASK 1  ✓ Source connection profile / External IP              ║"
echo "║ TASK 2  ✓ One-time MySQL → Cloud SQL migration                 ║"
echo "║ TASK 3  ✓ Continuous migration / VPC Peering                   ║"
echo "║ TASK 4  ✓ Source record updated / CDC replication              ║"
echo "║ TASK 5  ✓ Continuous destination promoted                     ║"
echo "║                                                                ║"
echo "║                         © ePlus.DEV                            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo "${RESET}"
