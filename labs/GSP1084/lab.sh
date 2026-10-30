#!/usr/bin/env bash
# ============================================================
# ePlus.DEV - GSP1084
# Migrate to AlloyDB from PostgreSQL using DMS
# Cloud Shell | Auto-detect project, region, VM zones and VPC
# Resume-safe | No cluster/instance creation or deletion
# Copyright (c) 2026 ePlus.DEV
# ============================================================
# The published Quick instructions use `source lab.sh`. Run the actual lab
# in a child Bash process so `set -e`, traps and `exit` cannot terminate
# or change the caller's interactive Cloud Shell session.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  bash "${BASH_SOURCE[0]}" "$@"
  return $?
fi

set -Eeuo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[0;91m'; GREEN=$'\033[0;92m'
  YELLOW=$'\033[0;93m'; CYAN=$'\033[0;96m'
  BLUE=$'\033[0;94m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; BOLD=''; RESET=''
fi
info()  { printf '%s▶ %s%s\n' "$CYAN" "$*" "$RESET"; }
ok()    { printf '%s✔ %s%s\n' "$GREEN" "$*" "$RESET"; }
warn()  { printf '%s⚠ %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
fail()  { printf '%s✖ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
step()  { printf '\n%s%s========== %s ==========%s\n' "$BOLD" "$BLUE" "$*" "$RESET"; }
trap 'printf "%s✖ Error at line %s (exit %s)%s\n" "$RED" "$LINENO" "$?" "$RESET" >&2' ERR

readonly SOURCE_VM='pg14-source'
readonly CLIENT_VM='alloydb-client'
readonly CLUSTER='alloydb-target-cluster'
readonly INSTANCE='alloydb-target-instance'
readonly SOURCE_PROFILE='pg14-source'
readonly DEST_PROFILE='alloydb-target-profile'
readonly JOB='postgres-to-alloydb'
readonly DB_USER='postgres'
readonly DB_PASSWORD='Change3Me'  # Temporary lab-only password
readonly SQL_COUNTS="SELECT 'countries' AS table_name, count(*) AS rows FROM countries UNION ALL SELECT 'departments',count(*) FROM departments UNION ALL SELECT 'employees',count(*) FROM employees UNION ALL SELECT 'jobs',count(*) FROM jobs UNION ALL SELECT 'locations',count(*) FROM locations UNION ALL SELECT 'regions',count(*) FROM regions ORDER BY table_name;"

# Unattended SSH: compute ssh chooses the suitable connectivity path in Cloud Shell.
remote() {
  local vm="$1" zone="$2" cmd="$3"
  gcloud compute ssh "$vm" \
    --project="$PROJECT_ID" --zone="$zone" \
    --quiet --ssh-flag='-o ConnectTimeout=25' \
    --command="$cmd"
}
source_sql() {
  local escaped
  printf -v escaped '%q' "$1"
  remote "$SOURCE_VM" "$SOURCE_ZONE" \
    "sudo -u postgres psql -X -d postgres -v ON_ERROR_STOP=1 -P pager=off -c $escaped"
}
client_sql() {
  local escaped_sql escaped_password escaped_ip
  printf -v escaped_sql '%q' "$1"
  printf -v escaped_password '%q' "$DB_PASSWORD"
  printf -v escaped_ip '%q' "$ALLOYDB_IP"
  remote "$CLIENT_VM" "$CLIENT_ZONE" \
    "PGPASSWORD=$escaped_password psql -X -h $escaped_ip -p 5432 -U $DB_USER -d postgres -v ON_ERROR_STOP=1 -P pager=off -At -c $escaped_sql"
}
job_json() {
  gcloud database-migration migration-jobs describe "$JOB" \
    --project="$PROJECT_ID" --region="$REGION" --format=json
}
job_state() { job_json | jq -r '.state // "UNKNOWN"'; }
find_demote_operation() {
  gcloud database-migration operations list \
    --project="$PROJECT_ID" --region="$REGION" --format=json | \
    jq -r --arg job "$JOB" \
      '[.[] | select(.metadata.verb == "demote-destination" and ((.metadata.target // "") | contains($job)))] | sort_by(.metadata.createTime) | last | .name // empty'
}

# Poll a DMS long-running operation; do not continue while destination demotion is pending.
wait_operation() {
  local op="$1" label="$2" limit="${3:-900}" elapsed=0 status done errmsg
  [[ -n "$op" && "$op" != 'null' ]] || fail "$label did not return an operation ID."
  info "Waiting for $label: $op"
  while (( elapsed < limit )); do
    status="$(gcloud database-migration operations describe "$op" \
      --project="$PROJECT_ID" --region="$REGION" --format=json)" || return 1
    done="$(jq -r '.done // false' <<<"$status")"
    if [[ "$done" == 'true' ]]; then
      errmsg="$(jq -r '.error.message // empty' <<<"$status")"
      [[ -z "$errmsg" ]] || fail "$label failed: $errmsg"
      ok "$label completed."
      return 0
    fi
    printf '  %s: %ss elapsed (max %ss)\n' "$label" "$elapsed" "$limit"
    sleep 20
    ((elapsed+=20))
  done
  fail "Timeout waiting for $label. Rerun this script to resume."
}

printf '%s%s==============================================%s\n' "$BLUE" "$BOLD" "$RESET"
printf '%sePlus.DEV - Starting Execution - GSP1084%s\n' "$CYAN" "$RESET"
printf '%s==============================================%s\n' "$BLUE" "$RESET"

step 'STEP 1/8 - Discover project and lab resources'
command -v gcloud >/dev/null || fail 'Run this script in Google Cloud Shell.'
command -v jq >/dev/null || fail 'jq is required in Google Cloud Shell.'
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || fail 'No active Google Cloud project.'
info "Project: $PROJECT_ID"
info 'Checking required APIs (lab accounts may not have permission to enable services)...'
for api in compute.googleapis.com alloydb.googleapis.com datamigration.googleapis.com; do
  if gcloud services list --enabled --project="$PROJECT_ID" \
    --filter="config.name=$api" --format='value(config.name)' 2>/dev/null | grep -Fxq "$api"; then
    ok "$api is enabled."
  else
    warn "Cannot confirm $api is enabled. Trying to enable it (if permitted)..."
    if gcloud services enable "$api" --project="$PROJECT_ID" --quiet >/dev/null 2>&1; then
      ok "$api enabled."
    else
      warn "Cannot enable $api with this lab account. Continuing; a later resource command will report if the API is actually unavailable."
    fi
  fi
done

# Determine the DMS region from the existing AlloyDB cluster, never from a fixed value.
CLUSTER_RESOURCE="$(gcloud alloydb clusters list --project="$PROJECT_ID" \
  --format='value(name)' | awk -F/ -v c="$CLUSTER" '$NF == c {print; exit}')"
[[ "$CLUSTER_RESOURCE" == */locations/*/clusters/"$CLUSTER" ]] || \
  fail "Existing cluster $CLUSTER not found. Check lab provisioning/project."
REGION="${CLUSTER_RESOURCE#*/locations/}"
REGION="${REGION%%/*}"

SOURCE_ZONE="$(gcloud compute instances list --project="$PROJECT_ID" \
  --filter="name=$SOURCE_VM" --format='value(zone)' | head -n 1 | awk -F/ '{print $NF}')"
CLIENT_ZONE="$(gcloud compute instances list --project="$PROJECT_ID" \
  --filter="name=$CLIENT_VM" --format='value(zone)' | head -n 1 | awk -F/ '{print $NF}')"
[[ -n "$SOURCE_ZONE" && -n "$CLIENT_ZONE" ]] || fail 'Source or client VM not found.'
SOURCE_IP="$(gcloud compute instances describe "$SOURCE_VM" \
  --project="$PROJECT_ID" --zone="$SOURCE_ZONE" \
  --format='value(networkInterfaces[0].networkIP)')"
SOURCE_VPC="$(gcloud compute instances describe "$SOURCE_VM" \
  --project="$PROJECT_ID" --zone="$SOURCE_ZONE" \
  --format='value(networkInterfaces[0].network)')"
SOURCE_VPC="${SOURCE_VPC#https://www.googleapis.com/compute/v1/}"
[[ "$SOURCE_VPC" == projects/*/global/networks/* ]] || fail "Invalid source VPC: $SOURCE_VPC"
[[ "$SOURCE_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Cannot detect source private IP.'
printf '  REGION      : %s\n  SOURCE_ZONE : %s\n  CLIENT_ZONE : %s\n  SOURCE_IP   : %s\n  SOURCE_VPC  : %s\n' \
  "$REGION" "$SOURCE_ZONE" "$CLIENT_ZONE" "$SOURCE_IP" "$SOURCE_VPC"

step 'STEP 2/8 - Task 1: Verify PostgreSQL source'
source_sql "$SQL_COUNTS"
ok 'Source PostgreSQL query completed.'

step 'STEP 3/8 - Task 2: Create DMS connection profiles'
if gcloud database-migration connection-profiles describe "$SOURCE_PROFILE" \
  --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Source profile $SOURCE_PROFILE already exists."
else
  gcloud database-migration connection-profiles create postgresql "$SOURCE_PROFILE" \
    --region="$REGION" --project="$PROJECT_ID" --display-name="$SOURCE_PROFILE" \
    --role=SOURCE --host="$SOURCE_IP" --port=5432 \
    --username="$DB_USER" --password="$DB_PASSWORD" --no-async
  ok 'Source connection profile created.'
fi
if gcloud database-migration connection-profiles describe "$DEST_PROFILE" \
  --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Destination profile $DEST_PROFILE already exists."
else
  gcloud database-migration connection-profiles create postgresql "$DEST_PROFILE" \
    --region="$REGION" --project="$PROJECT_ID" --display-name="$DEST_PROFILE" \
    --role=DESTINATION --alloydb-cluster="$CLUSTER" \
    --username="$DB_USER" --password="$DB_PASSWORD" --no-async
  ok 'Existing AlloyDB destination profile created.'
fi

step 'STEP 4/8 - Task 2: Create migration job with VPC peering'
if gcloud database-migration migration-jobs describe "$JOB" \
  --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Migration job $JOB already exists."
else
  gcloud database-migration migration-jobs create "$JOB" \
    --project="$PROJECT_ID" --region="$REGION" --display-name="$JOB" \
    --type=CONTINUOUS --source="$SOURCE_PROFILE" --destination="$DEST_PROFILE" \
    --peer-vpc="$SOURCE_VPC" --all-databases --no-async
  ok 'Continuous DMS migration job created.'
fi

step 'STEP 5/8 - Demote existing destination, verify and start'
STATE="$(job_state)"
info "Current migration job state: $STATE"
case "$STATE" in
  RUNNING|STARTING|COMPLETED)
    ok 'Migration has already started; no demotion repeated.'
    ;;
  NOT_STARTED)
    # Resume-safe demotion: reuse the previous operation instead of demoting again.
    DEMOTE_OP="$(find_demote_operation)"
    if [[ -z "$DEMOTE_OP" ]]; then
      DEMOTE_OP="$(gcloud database-migration migration-jobs demote-destination "$JOB" \
        --region="$REGION" --project="$PROJECT_ID" --format='value(name)')"
    else
      ok "Found earlier destination demotion: $DEMOTE_OP"
    fi
    wait_operation "$DEMOTE_OP" 'destination demotion' 900
    VERIFY_OP="$(gcloud database-migration migration-jobs verify "$JOB" \
      --region="$REGION" --project="$PROJECT_ID" --format='value(name)')"
    wait_operation "$VERIFY_OP" 'migration job validation' 600
    info 'Starting continuous migration...'
    gcloud database-migration migration-jobs start "$JOB" \
      --region="$REGION" --project="$PROJECT_ID" >/dev/null
    ok 'Start request accepted.'
    ;;
  FAILED|STOPPED|DRAFT)
    fail "Job state is $STATE. Inspect: gcloud database-migration migration-jobs describe $JOB --region=$REGION"
    ;;
  *)
    fail "Unexpected job state: $STATE. Rerun after checking job details."
    ;;
esac

step 'STEP 6/8 - Wait until migration enters RUNNING / CDC'
CDC_READY=false
for ((i=1; i<=60; i++)); do
  JOB_JSON="$(job_json)"
  STATE="$(jq -r '.state // "UNKNOWN"' <<<"$JOB_JSON")"
  PHASE="$(jq -r '.phase // "UNKNOWN"' <<<"$JOB_JSON")"
  printf '  [%02d/60] DMS state=%s phase=%s\n' "$i" "$STATE" "$PHASE"
  [[ "$STATE" != 'FAILED' ]] || fail "DMS job failed: $(jq -r '.error.message // "See migration job errors."' <<<"$JOB_JSON")"
  if [[ "$STATE" == 'RUNNING' && "$PHASE" == 'CDC' ]]; then
    CDC_READY=true; break
  fi
  sleep 20
done
[[ "$CDC_READY" == true ]] || fail 'CDC phase not reached; rerun to continue monitoring.'
ok 'Initial database dump completed. Continuous CDC is running.'

step 'STEP 7/8 - Task 3: Verify migrated data in AlloyDB'
ALLOYDB_IP="$(gcloud alloydb instances describe "$INSTANCE" \
  --cluster="$CLUSTER" --region="$REGION" --project="$PROJECT_ID" \
  --view=full --format='value(ipAddress)')"
[[ "$ALLOYDB_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  fail "Unable to detect AlloyDB private IP. Inspect: gcloud alloydb instances describe $INSTANCE --cluster=$CLUSTER --region=$REGION"
info "AlloyDB private IP: $ALLOYDB_IP"
remote "$CLIENT_VM" "$CLIENT_ZONE" "printf '%s\\n' '$ALLOYDB_IP' > ~/alloydbip.txt"
ok 'Saved the private IP to ~/alloydbip.txt on alloydb-client.'
# Readiness retry: CDC may have begun before the SQL endpoint is queryable.
TARGET_READY=false
for ((i=1; i<=15; i++)); do
  if TARGET_COUNTS="$(client_sql "$SQL_COUNTS" 2>/dev/null)"; then
    printf '%s\n' "$TARGET_COUNTS"
    TARGET_READY=true; break
  fi
  warn "Destination query not ready (attempt $i/15)."
  sleep 15
done
[[ "$TARGET_READY" == true ]] || fail 'Cannot query AlloyDB from alloydb-client.'
# Match task's fixed reference data rather than declaring success on mere connectivity.
for expected in 'countries|25' 'departments|27' 'employees|107' 'jobs|19' 'locations|23' 'regions|4'; do
  if ! grep -Fxq "$expected" <<<"$TARGET_COUNTS"; then
    if [[ "$expected" == 'regions|4' ]] && grep -Fxq 'regions|5' <<<"$TARGET_COUNTS"; then
      warn 'regions already has 5 records (prior CDC test may have run).'
    else
      fail "Expected migrated row count $expected was not found."
    fi
  fi
done
ok 'All six HR tables are present with expected row counts.'

step 'STEP 8/8 - Task 4: Insert Oceania and verify live CDC'
source_sql "INSERT INTO regions (region_id, region_name) SELECT 5, 'Oceania' WHERE NOT EXISTS (SELECT 1 FROM regions WHERE region_id = 5);"
source_sql "SELECT region_id, region_name FROM regions ORDER BY region_id;"
CDC_APPLIED=false
for ((i=1; i<=36; i++)); do
  if result="$(client_sql "SELECT region_id || '|' || region_name FROM regions WHERE region_id = 5;" 2>/dev/null)"; then
    if grep -Fxq '5|Oceania' <<<"$result"; then CDC_APPLIED=true; break; fi
  fi
  printf '  Waiting for Oceania replication... (%s/36)\n' "$i"
  sleep 10
done
[[ "$CDC_APPLIED" == true ]] || fail 'CDC did not propagate Oceania. Check DMS job status.'
client_sql 'SELECT region_id, region_name FROM regions ORDER BY region_id;'
ok 'Oceania replicated to AlloyDB successfully.'
printf '\n%s%s==============================================%s\n' "$GREEN" "$BOLD" "$RESET"
printf '%s GSP1084 - ALL TASKS VERIFIED BY SQL%s\n' "$GREEN" "$RESET"
printf ' Project: %s | Region: %s | Job: %s\n' "$PROJECT_ID" "$REGION" "$JOB"
printf '%s==============================================%s\n' "$GREEN" "$RESET"
printf 'Use Check my progress in the Google Cloud lab interface.\n'