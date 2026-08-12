#!/usr/bin/env bash

# ============================================================
# GSP351 - FULL AUTO
# Migrate MySQL Data to Cloud SQL using DMS
#
# Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 5
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

# ============================================================
# PROGRESS UI
# ============================================================

format_seconds() {
    local total="$1"
    printf "%02d:%02d" $((total / 60)) $((total % 60))
}

spinner_char() {
    case $(($1 % 4)) in
        0) printf "|" ;;
        1) printf "/" ;;
        2) printf "-" ;;
        3) printf "\\" ;;
    esac
}

progress_bar() {

    local current="$1"
    local total="$2"
    local width="${3:-30}"

    (( total <= 0 )) && total=1
    (( current > total )) && current="$total"

    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "["

    if (( filled > 0 )); then
        printf "%${filled}s" "" | tr ' ' '#'
    fi

    if (( empty > 0 )); then
        printf "%${empty}s" "" | tr ' ' '-'
    fi

    printf "]"
}

wait_countdown() {

    local total="$1"
    local message="$2"

    echo
    echo "${YELLOW}${BOLD}$message${RESET}"
    echo

    for ((elapsed=0; elapsed<=total; elapsed++)); do

        local remaining=$((total - elapsed))
        local percent=$((elapsed * 100 / total))

        printf "\r${CYAN}"

        progress_bar "$elapsed" "$total" 32

        printf " %3d%% | Remaining: %02ds${RESET}   " \
            "$percent" \
            "$remaining"

        (( elapsed == total )) && break

        sleep 1
    done

    echo
    ok "$message completed."
}

# ============================================================
# BANNER
# ============================================================

clear

echo "${MAGENTA}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                           GSP351                               ║"
echo "║            FULL AUTO MYSQL → CLOUD SQL MIGRATION               ║"
echo "║                                                                ║"
echo "║                        © ePlus.DEV                             ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo "${RESET}"

# ============================================================
# INPUT
# ============================================================

section "LAB RESOURCE INPUT"

echo "${WHITE}Enter the three resource names provided by the lab.${RESET}"
echo

read -r -p "$(echo "${CYAN}${BOLD}MySQL source instance                : ${RESET}")" \
    SOURCE_VM

read -r -p "$(echo "${CYAN}${BOLD}Cloud SQL one-time migration target  : ${RESET}")" \
    ONE_TIME_TARGET

read -r -p "$(echo "${CYAN}${BOLD}Cloud SQL continuous migration target: ${RESET}")" \
    CONTINUOUS_TARGET

[[ -z "$SOURCE_VM" ]] &&
    die "MySQL source instance is required."

[[ -z "$ONE_TIME_TARGET" ]] &&
    die "One-time Cloud SQL target is required."

[[ -z "$CONTINUOUS_TARGET" ]] &&
    die "Continuous Cloud SQL target is required."

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

SOURCE_CP="mysql-source-profile"

ONE_TIME_JOB="$ONE_TIME_TARGET"
CONTINUOUS_JOB="$CONTINUOUS_TARGET"

ONE_TIME_DEST_CP="cp-${ONE_TIME_TARGET}"
CONTINUOUS_DEST_CP="cp-${CONTINUOUS_TARGET}"

ONE_TIME_DEST_CP="${ONE_TIME_DEST_CP:0:60}"
CONTINUOUS_DEST_CP="${CONTINUOUS_DEST_CP:0:60}"

# ============================================================
# DETECT ENVIRONMENT
# ============================================================

section "[1/10] Detecting Google Cloud environment"

ZONE=$(
    gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name=$SOURCE_VM" \
        --format='value(zone.basename())' |
        head -1
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

echo "${WHITE}Project                : ${CYAN}$PROJECT_ID${RESET}"
echo "${WHITE}Region                 : ${CYAN}$REGION${RESET}"
echo "${WHITE}Zone                   : ${CYAN}$ZONE${RESET}"
echo
echo "${WHITE}MySQL source           : ${CYAN}$SOURCE_VM${RESET}"
echo "${WHITE}External IP            : ${CYAN}$SOURCE_EXTERNAL_IP${RESET}"
echo "${WHITE}Internal IP            : ${CYAN}$SOURCE_INTERNAL_IP${RESET}"
echo "${WHITE}VPC                    : ${CYAN}$NETWORK_NAME${RESET}"
echo
echo "${WHITE}One-time destination   : ${GREEN}$ONE_TIME_TARGET${RESET}"
echo "${WHITE}Continuous destination : ${GREEN}$CONTINUOUS_TARGET${RESET}"

# ============================================================
# VALIDATE CLOUD SQL
# ============================================================

gcloud sql instances describe "$ONE_TIME_TARGET" \
    --project="$PROJECT_ID" >/dev/null 2>&1 ||
    die "Cloud SQL instance not found: $ONE_TIME_TARGET"

gcloud sql instances describe "$CONTINUOUS_TARGET" \
    --project="$PROJECT_ID" >/dev/null 2>&1 ||
    die "Cloud SQL instance not found: $CONTINUOUS_TARGET"

# ============================================================
# HELPERS
# ============================================================

profile_exists() {

    gcloud database-migration connection-profiles describe "$1" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1
}

job_exists() {

    gcloud database-migration migration-jobs describe "$1" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1
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

source_profile_host() {

    gcloud database-migration connection-profiles describe "$SOURCE_CP" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(mysql.host)' \
        2>/dev/null || true
}

# ============================================================
# DMS OPERATION WAIT
# ============================================================

wait_operation() {

    local operation="$1"

    [[ -z "$operation" ]] && return 0

    local op_id="${operation##*/}"
    local elapsed=0
    local interval=5
    local timeout=1800

    echo
    echo "${YELLOW}Waiting for DMS operation${RESET}"
    echo "${WHITE}Operation : ${CYAN}$op_id${RESET}"
    echo "${WHITE}Refresh   : ${CYAN}every ${interval}s${RESET}"
    echo

    while (( elapsed <= timeout )); do

        local done
        local err
        local spin

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
            echo

            fail "DMS operation failed:"
            echo "$err"

            return 1
        fi

        if [[ "$done" == "True" || "$done" == "true" ]]; then

            echo
            echo

            ok "DMS operation completed after $(format_seconds "$elapsed")."

            return 0
        fi

        spin=$(spinner_char $((elapsed / interval)))

        printf "\r${YELLOW}%s DMS is working | Elapsed: %s | Next check: %ss${RESET}   " \
            "$spin" \
            "$(format_seconds "$elapsed")" \
            "$interval"

        sleep "$interval"

        elapsed=$((elapsed + interval))
    done

    echo
    echo

    fail "DMS operation timeout after $(format_seconds "$timeout")."

    return 1
}

# ============================================================
# DMS ACTION
#
# IMPORTANT:
# No --no-async for:
# demote-destination
# verify
# start
# restart
# resume
# promote
# ============================================================

dms_action() {

    local action="$1"
    local job="$2"

    local error_file="/tmp/gsp351-${action}-${job}.err"
    local operation=""

    echo
    echo "${YELLOW}${BOLD}DMS action: $action${RESET}"
    echo "${WHITE}Migration job: ${CYAN}$job${RESET}"

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
    local expected="$2"

    local elapsed=0
    local interval=5
    local timeout=1800

    echo
    echo "${YELLOW}Waiting for migration job state${RESET}"
    echo "${WHITE}Job      : ${CYAN}$job${RESET}"
    echo "${WHITE}Expected : ${GREEN}$expected${RESET}"
    echo

    while (( elapsed <= timeout )); do

        local state
        local phase
        local spin

        state=$(job_state "$job")
        phase=$(job_phase "$job")

        spin=$(spinner_char $((elapsed / interval)))

        printf "\r${YELLOW}%s State: %-18s | Phase: %-22s | Elapsed: %s${RESET}   " \
            "$spin" \
            "${state:-UNKNOWN}" \
            "${phase:-N/A}" \
            "$(format_seconds "$elapsed")"

        if [[ "$state" == "$expected" ]]; then

            echo
            echo

            ok "$job reached $expected after $(format_seconds "$elapsed")."

            return 0
        fi

        if [[ "$state" == "FAILED" ]]; then

            echo
            echo

            fail "$job entered FAILED state."

            gcloud database-migration migration-jobs describe "$job" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --format='yaml(state,phase,error)'

            return 1
        fi

        sleep "$interval"

        elapsed=$((elapsed + interval))
    done

    echo
    echo

    fail "Timeout waiting for $job -> $expected."

    return 1
}

# ============================================================
# WAIT CONTINUOUS CDC
# ============================================================

wait_for_cdc() {

    local job="$1"

    local elapsed=0
    local interval=5
    local timeout=1800

    echo
    echo "${YELLOW}${BOLD}Waiting for continuous migration${RESET}"
    echo "${WHITE}Target phase: ${CYAN}FULL_DUMP → CDC${RESET}"
    echo
    echo "${WHITE}The terminal refreshes every 5 seconds.${RESET}"
    echo

    while (( elapsed <= timeout )); do

        local state
        local phase
        local spin

        state=$(job_state "$job")
        phase=$(job_phase "$job")

        spin=$(spinner_char $((elapsed / interval)))

        printf "\r${YELLOW}%s State: %-18s | Phase: %-22s | Elapsed: %s${RESET}   " \
            "$spin" \
            "${state:-UNKNOWN}" \
            "${phase:-N/A}" \
            "$(format_seconds "$elapsed")"

        if [[ "$state" == "RUNNING" &&
              "$phase" == "CDC" ]]; then

            echo
            echo

            ok "Continuous migration reached RUNNING / CDC after $(format_seconds "$elapsed")."

            return 0
        fi

        if [[ "$state" == "FAILED" ]]; then

            echo
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
            echo

            warn "Continuous migration is already COMPLETED."

            return 2
        fi

        sleep "$interval"

        elapsed=$((elapsed + interval))
    done

    echo
    echo

    fail "Continuous migration did not reach CDC."

    return 1
}

# ============================================================
# SOURCE PROFILE UPDATE
# ============================================================

set_source_host() {

    local wanted="$1"
    local current

    current=$(source_profile_host)

    if [[ "$current" == "$wanted" ]]; then

        ok "Source connection profile already uses $wanted"

        return 0
    fi

    echo
    echo "${YELLOW}Updating source connection profile${RESET}"
    echo "${WHITE}New host: ${CYAN}$wanted${RESET}"

    gcloud database-migration connection-profiles update "$SOURCE_CP" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --host="$wanted" \
        --port="$MYSQL_PORT" \
        --username="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        --quiet >/dev/null ||
        return 1

    local elapsed=0

    for ((i=1; i<=60; i++)); do

        current=$(source_profile_host)

        if [[ "$current" == "$wanted" ]]; then

            echo
            ok "Source connection profile updated to $wanted."

            return 0
        fi

        local spin
        spin=$(spinner_char "$i")

        printf "\r${YELLOW}%s Propagating source profile... Elapsed: %02ds${RESET}   " \
            "$spin" \
            "$elapsed"

        sleep 2

        elapsed=$((elapsed + 2))
    done

    echo

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

        ok "Destination connection profile already exists: $profile"

        return 0
    fi

    echo
    echo "${YELLOW}Creating destination connection profile${RESET}"
    echo "${WHITE}Profile  : ${CYAN}$profile${RESET}"
    echo "${WHITE}Instance : ${CYAN}$instance${RESET}"

    gcloud database-migration connection-profiles create mysql "$profile" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --display-name="$display_name" \
        --cloudsql-instance="$instance" \
        --no-async \
        --quiet ||
        return 1

    ok "Destination connection profile created: $profile"

    return 0
}

# ============================================================
# DEMOTE
# ============================================================

demote_destination() {

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

    echo
    echo "${YELLOW}${BOLD}Demoting existing Cloud SQL destination${RESET}"
    echo "${WHITE}Instance: ${CYAN}$instance${RESET}"

    dms_action demote-destination "$job" ||
        return 1

    ok "Destination demotion completed."

    return 0
}

# ============================================================
# SOURCE MYSQL QUERY
# ============================================================

source_query() {

    local sql="$1"

    gcloud compute ssh "$SOURCE_VM" \
        --project="$PROJECT_ID" \
        --zone="$ZONE" \
        --quiet \
        --command="
            MYSQL_PWD='$MYSQL_PASSWORD' \
            mysql -u'$MYSQL_USER' -Nse \"$sql\"
        " 2>/dev/null
}

# ============================================================
# TASK PREPARATION
# ============================================================

section "[2/10] Preparing Google Cloud APIs"

gcloud services enable \
    datamigration.googleapis.com \
    sqladmin.googleapis.com \
    compute.googleapis.com \
    servicenetworking.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

ok "Required APIs enabled."

# ============================================================
# FIREWALL
# ============================================================

section "[3/10] Preparing MySQL network access"

FW_RULE="dms-mysql-source-3306"
VM_TAG="dms-mysql-source"

gcloud compute instances add-tags "$SOURCE_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --tags="$VM_TAG" \
    --quiet >/dev/null 2>&1 || true

if gcloud compute firewall-rules describe "$FW_RULE" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    ok "Firewall rule already exists: $FW_RULE"

else

    echo "${YELLOW}Creating MySQL TCP/3306 firewall rule...${RESET}"

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
        die "Unable to create firewall rule."

    ok "MySQL firewall rule created."
fi

# ============================================================
# TASK 1
# ============================================================

section "[4/10] TASK 1 - MySQL source connection profile"

if ! profile_exists "$SOURCE_CP"; then

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
        die "Unable to create source connection profile."

    ok "Source connection profile created."

else

    ok "Source connection profile already exists: $SOURCE_CP"

fi

# Task 1 + Task 2 require EXTERNAL IP.

set_source_host "$SOURCE_EXTERNAL_IP" ||
    die "Unable to configure source external IP."

ok "TASK 1 configured using EXTERNAL IP."

echo
echo "${YELLOW}Checking source customers_data database...${RESET}"

SOURCE_COUNT=$(
    source_query \
        "SELECT COUNT(*) FROM customers_data.customers;" |
        tail -1
)

echo "${WHITE}customers_data.customers : ${CYAN}${SOURCE_COUNT:-UNKNOWN}${RESET}"

if [[ "$SOURCE_COUNT" == "5030" ]]; then
    ok "Source database contains 5030 customers."
else
    warn "Expected 5030 rows. Current result: ${SOURCE_COUNT:-UNKNOWN}"
fi

# ============================================================
# TASK 2
# ============================================================

section "[5/10] TASK 2 - One-time migration using external IP"

create_destination_profile \
    "$ONE_TIME_DEST_CP" \
    "$ONE_TIME_TARGET" \
    "One Time Destination" ||
    die "Unable to create one-time destination profile."

if ! job_exists "$ONE_TIME_JOB"; then

    echo
    echo "${YELLOW}Creating ONE_TIME migration job...${RESET}"

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

    ok "One-time migration job already exists: $ONE_TIME_JOB"

fi

ONE_STATE=$(job_state "$ONE_TIME_JOB")
ONE_PHASE=$(job_phase "$ONE_TIME_JOB")

echo
echo "${WHITE}Current state : ${CYAN}${ONE_STATE:-UNKNOWN}${RESET}"
echo "${WHITE}Current phase : ${CYAN}${ONE_PHASE:-N/A}${RESET}"

case "$ONE_STATE" in

    COMPLETED)

        ok "One-time migration is already COMPLETED."
        ;;

    NOT_STARTED|DRAFT)

        demote_destination \
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
            die "One-time migration failed."

        ;;

    RUNNING|STARTING)

        warn "One-time migration is already running."

        wait_for_state "$ONE_TIME_JOB" "COMPLETED" ||
            die "One-time migration failed."

        ;;

    FAILED)

        warn "Restarting failed one-time migration."

        dms_action restart "$ONE_TIME_JOB" ||
            die "Unable to restart one-time migration."

        wait_for_state "$ONE_TIME_JOB" "COMPLETED" ||
            die "One-time migration failed."

        ;;

    STOPPED)

        warn "Restarting stopped one-time migration."

        dms_action restart "$ONE_TIME_JOB" ||
            die "Unable to restart one-time migration."

        wait_for_state "$ONE_TIME_JOB" "COMPLETED" ||
            die "One-time migration failed."

        ;;

    *)

        die "Unexpected one-time migration state: $ONE_STATE"
        ;;
esac

ok "TASK 2 one-time migration COMPLETED."

# ============================================================
# TASK 3
# ============================================================

section "[6/10] TASK 3 - Continuous migration using VPC Peering"

echo "${WHITE}Switching the SAME source connection profile:${RESET}"
echo "${WHITE}$SOURCE_EXTERNAL_IP → ${CYAN}$SOURCE_INTERNAL_IP${RESET}"
echo

set_source_host "$SOURCE_INTERNAL_IP" ||
    die "Unable to configure source internal IP."

create_destination_profile \
    "$CONTINUOUS_DEST_CP" \
    "$CONTINUOUS_TARGET" \
    "Continuous Destination" ||
    die "Unable to create continuous destination profile."

if ! job_exists "$CONTINUOUS_JOB"; then

    echo
    echo "${YELLOW}Creating CONTINUOUS migration job...${RESET}"
    echo "${WHITE}Connectivity: ${CYAN}VPC Peering${RESET}"

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

    ok "Continuous migration job already exists: $CONTINUOUS_JOB"

fi

CONT_STATE=$(job_state "$CONTINUOUS_JOB")
CONT_PHASE=$(job_phase "$CONTINUOUS_JOB")

echo
echo "${WHITE}Current state : ${CYAN}${CONT_STATE:-UNKNOWN}${RESET}"
echo "${WHITE}Current phase : ${CYAN}${CONT_PHASE:-N/A}${RESET}"

case "$CONT_STATE" in

    NOT_STARTED|DRAFT)

        demote_destination \
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
            die "Continuous migration failed to reach CDC."

        ;;

    RUNNING)

        if [[ "$CONT_PHASE" == "CDC" ]]; then

            ok "Continuous migration is already RUNNING / CDC."

        else

            wait_for_cdc "$CONTINUOUS_JOB" ||
                die "Continuous migration failed to reach CDC."

        fi

        ;;

    FAILED)

        warn "Restarting failed continuous migration."

        dms_action restart "$CONTINUOUS_JOB" ||
            die "Unable to restart continuous migration."

        wait_for_cdc "$CONTINUOUS_JOB" ||
            die "Continuous migration failed to reach CDC."

        ;;

    STOPPED)

        if [[ "$CONT_PHASE" == "CDC" ]]; then

            warn "Resuming continuous migration."

            dms_action resume "$CONTINUOUS_JOB" ||
                die "Unable to resume continuous migration."

        else

            warn "Restarting continuous migration."

            dms_action restart "$CONTINUOUS_JOB" ||
                die "Unable to restart continuous migration."

        fi

        wait_for_cdc "$CONTINUOUS_JOB" ||
            die "Continuous migration failed to reach CDC."

        ;;

    COMPLETED)

        warn "Continuous migration is already COMPLETED."
        ;;

    *)

        die "Unexpected continuous migration state: $CONT_STATE"
        ;;
esac

CONT_STATE=$(job_state "$CONTINUOUS_JOB")

# If previous run already promoted it, do not repeat Task 4/5.

if [[ "$CONT_STATE" == "COMPLETED" ]]; then

    warn "Continuous destination has already been promoted."

else

    ok "TASK 3 continuous migration reached RUNNING / CDC."

    # ========================================================
    # SMALL VISUAL STABILIZATION
    # ========================================================

    wait_countdown 10 \
        "Continuous migration is stable in CDC"

    # ========================================================
    # TASK 4
    # ========================================================

    section "[7/10] TASK 4 - Test continuous replication"

    CURRENT_GENDER=$(
        source_query \
            "SELECT gender
             FROM customers_data.customers
             WHERE addressKey=934;" |
            tail -1
    )

    echo "${WHITE}Current gender for addressKey 934: ${CYAN}${CURRENT_GENDER:-UNKNOWN}${RESET}"

    # Make reruns idempotent while ensuring a real change occurs
    # after CDC has started.

    if [[ "$CURRENT_GENDER" == "FEMALE" ]]; then

        warn "Record is already FEMALE from a previous attempt."
        echo "${YELLOW}Resetting temporarily to MALE before applying required update...${RESET}"

        source_query "
            USE customers_data;
            UPDATE customers
            SET gender='MALE'
            WHERE addressKey=934;
        " >/dev/null ||
            die "Unable to reset source row."

        wait_countdown 5 "Preparing fresh CDC update"

    fi

    echo
    echo "${YELLOW}${BOLD}Executing required Task 4 query${RESET}"
    echo "${WHITE}UPDATE customers SET gender='FEMALE' WHERE addressKey=934;${RESET}"
    echo

    source_query "
        USE customers_data;

        UPDATE customers
        SET gender='FEMALE'
        WHERE addressKey=934;

        SELECT CONCAT(addressKey,' | ',gender)
        FROM customers
        WHERE addressKey=934;
    " ||
        die "Unable to update source MySQL database."

    GENDER=$(
        source_query "
            SELECT gender
            FROM customers_data.customers
            WHERE addressKey=934;
        " |
        tail -1
    )

    echo
    echo "${WHITE}addressKey : ${CYAN}934${RESET}"
    echo "${WHITE}gender     : ${CYAN}${GENDER:-UNKNOWN}${RESET}"

    [[ "$GENDER" != "FEMALE" ]] &&
        die "Task 4 source update could not be confirmed."

    ok "Source row successfully updated to FEMALE."

    # Lab asks to allow time for replication.

    wait_countdown 90 \
        "Waiting for continuous CDC replication"

    CONT_STATE=$(job_state "$CONTINUOUS_JOB")
    CONT_PHASE=$(job_phase "$CONTINUOUS_JOB")

    echo
    echo "${WHITE}Continuous state : ${CYAN}$CONT_STATE${RESET}"
    echo "${WHITE}Continuous phase : ${CYAN}${CONT_PHASE:-N/A}${RESET}"

    [[ "$CONT_STATE" != "RUNNING" ]] &&
        die "Continuous migration is no longer RUNNING."

    ok "TASK 4 CDC propagation period completed."

    # ========================================================
    # TASK 5
    # ========================================================

    section "[8/10] TASK 5 - Promote continuous Cloud SQL destination"

    CONT_PHASE=$(job_phase "$CONTINUOUS_JOB")

    if [[ "$CONT_PHASE" != "CDC" ]]; then

        wait_for_cdc "$CONTINUOUS_JOB" ||
            die "Continuous migration is not ready for promotion."

    fi

    echo
    echo "${YELLOW}${BOLD}Promoting destination: $CONTINUOUS_TARGET${RESET}"

    dms_action promote "$CONTINUOUS_JOB" ||
        die "Continuous migration promotion failed."

    wait_for_state "$CONTINUOUS_JOB" "COMPLETED" ||
        die "Promotion did not complete."

    ok "TASK 5 destination promoted successfully."

fi

# ============================================================
# RESTORE TASK 1 SOURCE PROFILE
# ============================================================

section "[9/10] Restoring Task 1 source connection profile"

echo "${WHITE}Restoring source host to external IP:${RESET}"
echo "${CYAN}$SOURCE_EXTERNAL_IP${RESET}"

set_source_host "$SOURCE_EXTERNAL_IP" ||
    warn "Unable to restore source connection profile external IP."

# ============================================================
# FINAL VERIFICATION
# ============================================================

section "[10/10] FINAL VERIFICATION"

echo "${BOLD}Migration Jobs${RESET}"
echo

gcloud database-migration migration-jobs list \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='table(displayName,type,state,phase)' ||
    true

echo
echo "${BOLD}Cloud SQL Instances${RESET}"
echo

gcloud sql instances list \
    --project="$PROJECT_ID" \
    --filter="name=($ONE_TIME_TARGET $CONTINUOUS_TARGET)" \
    --format='table(name,instanceType,state,region,databaseVersion)' ||
    true

echo
echo "${BOLD}Source verification${RESET}"
echo

FINAL_SOURCE_COUNT=$(
    source_query \
        "SELECT COUNT(*) FROM customers_data.customers;" |
        tail -1
)

FINAL_GENDER=$(
    source_query \
        "SELECT gender
         FROM customers_data.customers
         WHERE addressKey=934;" |
        tail -1
)

echo "${WHITE}customers count       : ${CYAN}${FINAL_SOURCE_COUNT:-UNKNOWN}${RESET}"
echo "${WHITE}addressKey 934 gender : ${CYAN}${FINAL_GENDER:-UNKNOWN}${RESET}"

echo
echo "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    GSP351 EXECUTION COMPLETE                  ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║ TASK 1  ✓ Source connection profile / External IP              ║"
echo "║ TASK 2  ✓ One-time migration / COMPLETED                       ║"
echo "║ TASK 3  ✓ Continuous migration / VPC Peering                   ║"
echo "║ TASK 4  ✓ CDC replication / gender = FEMALE                    ║"
echo "║ TASK 5  ✓ Continuous destination promoted                     ║"
echo "║                                                                ║"
echo "║                        © ePlus.DEV                             ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo "${RESET}"