#!/bin/bash

# ============================================================
# GSP859 - VERSION MISMATCH AUTO REPAIR
#
# RDS MySQL 8.4 -> Cloud SQL MySQL 8.4
#
# ePlus.DEV Cloud Tutorial
# ============================================================

# NO set -e
# NO exit
# Terminal remains open

RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
RESET=$'\033[0m'
BOLD=$'\033[1m'


SOURCE_PROFILE="mysql-rds-source"
DEST_PROFILE="mysql-cloudsql-destination"
MIGRATION_JOB="rds-to-cloudsql"
DEST_INSTANCE="mysql-cloudsql"

SOURCE_DB_USER="admin"
SOURCE_DB_PASSWORD="changeme"
SOURCE_DB_PORT="3306"

DEST_DB_USER="root"
DEST_DB_PASSWORD="supersecret"


# ============================================================
# DISPLAY
# ============================================================

header() {

    clear

    echo
    echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}        WELCOME TO ePlus.DEV CLOUD TUTORIAL                 ${RESET}"
    echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo "${MAGENTA}${BOLD} GSP859 - MySQL 8.4 Version Repair + Migration${RESET}"
    echo
}


step() {

    echo
    echo "${BLUE}${BOLD}============================================================${RESET}"
    echo "${YELLOW}${BOLD}$1${RESET}"
    echo "${BLUE}${BOLD}============================================================${RESET}"
}


info() {
    echo "${CYAN}➜ $1${RESET}"
}


ok() {
    echo "${GREEN}${BOLD}✓ $1${RESET}"
}


warn() {
    echo "${YELLOW}${BOLD}⚠ $1${RESET}"
}


err() {
    echo "${RED}${BOLD}✗ $1${RESET}"
}


trim() {

    local v="$1"

    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"

    printf '%s' "$v"
}


# ============================================================
# DMS HELPERS
# ============================================================

get_job_state() {

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(state)" \
        2>/dev/null
}


get_job_phase() {

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(phase)" \
        2>/dev/null
}


job_exists() {

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1
}


get_outgoing_ips() {

    gcloud sql instances describe \
        "$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        --format=json \
        2>/dev/null |
        jq -r '
            .ipAddresses[]?
            | select(.type == "OUTGOING")
            | .ipAddress
        ' |
        grep -E \
            '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
        sort -u
}


show_job_error() {

    echo

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="yaml(state,phase,error)" \
        2>/dev/null

    echo
}


# ============================================================
# WAIT DMS OPERATION
# ============================================================

wait_dms_operation() {

    local OP_NAME="$1"
    local OP_ID
    local JSON
    local DONE
    local ERROR_MESSAGE
    local COUNT=0


    if [[ -z "$OP_NAME" ]]; then

        warn "No operation ID returned."

        sleep 5

        return 0
    fi


    OP_ID="${OP_NAME##*/}"

    info "Operation: $OP_ID"


    while true; do

        JSON=$(
            gcloud database-migration operations describe \
                "$OP_ID" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --format=json \
                2>/dev/null
        )


        if [[ $? -ne 0 || -z "$JSON" ]]; then

            COUNT=$((COUNT + 1))

            if [[ "$COUNT" -ge 180 ]]; then

                echo
                err "Timed out waiting for DMS operation."

                return 1
            fi

            printf "."

            sleep 5

            continue
        fi


        DONE=$(
            echo "$JSON" |
                jq -r '.done // false'
        )


        if [[ "$DONE" == "true" ]]; then

            echo

            ERROR_MESSAGE=$(
                echo "$JSON" |
                    jq -r '.error.message // empty'
            )

            if [[ -n "$ERROR_MESSAGE" ]]; then

                err "$ERROR_MESSAGE"

                return 1
            fi

            ok "Operation completed."

            return 0
        fi


        printf "."

        sleep 5
    done
}


run_dms_action() {

    local ACTION="$1"
    local OP_NAME
    local RC


    info "Running DMS action: $ACTION"


    OP_NAME=$(
        gcloud database-migration migration-jobs "$ACTION" \
            "$MIGRATION_JOB" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet \
            --format="value(name)" \
            2>/tmp/gsp859_dms.log
    )

    RC=$?


    if [[ "$RC" -ne 0 ]]; then

        echo
        cat /tmp/gsp859_dms.log 2>/dev/null
        echo

        return "$RC"
    fi


    wait_dms_operation "$OP_NAME"

    return $?
}


# ============================================================
# WAIT CLOUD SQL
# ============================================================

wait_cloudsql() {

    local COUNT=0
    local STATE


    while true; do

        STATE=$(
            gcloud sql instances describe \
                "$DEST_INSTANCE" \
                --project="$PROJECT_ID" \
                --format="value(state)" \
                2>/dev/null
        )


        COUNT=$((COUNT + 1))

        info "Cloud SQL state: ${STATE:-UNKNOWN}"


        if [[ "$STATE" == "RUNNABLE" ]]; then

            return 0
        fi


        if [[ "$COUNT" -ge 120 ]]; then

            err "Cloud SQL did not become RUNNABLE."

            return 1
        fi


        sleep 5
    done
}


# ============================================================
# MAIN
# ============================================================

main() {

    header


    # ========================================================
    # STEP 1 - INPUT
    # ========================================================

    step "STEP 1 - Enter AWS Lab Details"


    echo
    echo "${GREEN}All pasted values are visible.${RESET}"
    echo


    read -r -p \
        "AWS RDS Database - Source        : " \
        RDS_HOST


    read -r -p \
        "AWS RDS Database Security Group : " \
        AWS_SECURITY_GROUP


    read -r -p \
        "AWS Access Key ID               : " \
        AWS_ACCESS_KEY_ID


    read -r -p \
        "AWS Secret Access Key           : " \
        AWS_SECRET_ACCESS_KEY


    RDS_HOST=$(trim "$RDS_HOST")

    AWS_SECURITY_GROUP=$(trim "$AWS_SECURITY_GROUP")

    AWS_ACCESS_KEY_ID=$(trim "$AWS_ACCESS_KEY_ID")

    AWS_SECRET_ACCESS_KEY=$(trim "$AWS_SECRET_ACCESS_KEY")


    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION="us-east-1"

    unset AWS_SESSION_TOKEN 2>/dev/null


    # ========================================================
    # STEP 2 - ENVIRONMENT
    # ========================================================

    step "STEP 2 - Detect environment"


    PROJECT_ID=$(
        gcloud config get-value project \
            2>/dev/null
    )


    REGION=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(region)" \
            2>/dev/null
    )


    if [[ -z "$PROJECT_ID" ||
          -z "$REGION" ]]; then

        err "Unable to detect project or region."

        return 1
    fi


    ok "Project : $PROJECT_ID"

    ok "Region  : $REGION"


    # ========================================================
    # STEP 3 - VERIFY THE ACTUAL VERSION PROBLEM
    # ========================================================

    step "STEP 3 - Verify source and destination versions"


    SOURCE_VERSION=$(
        aws rds describe-db-instances \
            --region=us-east-1 \
            --query \
            "DBInstances[?Endpoint.Address=='$RDS_HOST'].EngineVersion | [0]" \
            --output=text \
            2>/dev/null
    )


    DEST_JSON=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format=json
    )


    DEST_MAJOR=$(
        echo "$DEST_JSON" |
            jq -r '.databaseVersion'
    )


    DEST_INSTALLED=$(
        echo "$DEST_JSON" |
            jq -r '.databaseInstalledVersion // .databaseVersion'
    )


    INSTANCE_TYPE=$(
        echo "$DEST_JSON" |
            jq -r '.instanceType'
    )


    echo
    echo "Amazon RDS              : $SOURCE_VERSION"
    echo "Cloud SQL configured    : $DEST_MAJOR"
    echo "Cloud SQL installed     : $DEST_INSTALLED"
    echo "Cloud SQL instance type : $INSTANCE_TYPE"
    echo


    if [[ "$SOURCE_VERSION" != 8.4* ]]; then

        warn "Source isn't MySQL 8.4."

        warn "This repair script was written for the current GSP859 mismatch."
    fi


    # ========================================================
    # STEP 4 - STOP FAILED/RUNNING MIGRATION JOB
    # ========================================================

    step "STEP 4 - Remove incompatible migration job"


    if job_exists; then

        STATE=$(get_job_state)

        info "Current migration state: $STATE"


        case "$STATE" in

            RUNNING|STARTING|RESTARTING|RESUMING)

                warn "Stopping current migration job..."

                run_dms_action "stop"

                sleep 5

                ;;

        esac


        info "Deleting incompatible migration job..."

        echo "${YELLOW}Destination Cloud SQL will NOT be force-deleted.${RESET}"


        gcloud database-migration migration-jobs delete \
            "$MIGRATION_JOB" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet \
            >/tmp/gsp859_delete_job.log \
            2>&1


        DELETE_RC=$?


        if [[ "$DELETE_RC" -ne 0 ]]; then

            cat /tmp/gsp859_delete_job.log

            err "Failed to delete migration job."

            return 1
        fi


        for i in $(seq 1 60); do

            if ! job_exists; then
                break
            fi

            info "Waiting for migration job deletion..."

            sleep 3
        done


        ok "Old incompatible migration job removed."

    else

        ok "Old migration job already removed."
    fi


    # ========================================================
    # STEP 5 - PROMOTE EXTERNAL REPLICA BACK TO STANDALONE
    # ========================================================

    step "STEP 5 - Restore mysql-cloudsql to standalone instance"


    INSTANCE_TYPE=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(instanceType)" \
            2>/dev/null
    )


    info "Current instance type: $INSTANCE_TYPE"


    if [[ "$INSTANCE_TYPE" == "READ_REPLICA_INSTANCE" ]]; then


        info "Promoting replica to standalone Cloud SQL instance..."


        gcloud sql instances promote-replica \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --quiet


        if [[ $? -ne 0 ]]; then

            err "Failed to promote mysql-cloudsql."

            return 1
        fi


        wait_cloudsql || return 1


        ok "mysql-cloudsql is standalone again."


    else


        ok "mysql-cloudsql is already standalone."
    fi


    # ========================================================
    # STEP 6 - CLEAN PARTIAL DATABASES
    # ========================================================

    step "STEP 6 - Remove partial migration data if present"


    for DB in customers_data sales_data; do


        if gcloud sql databases describe \
            "$DB" \
            --instance="$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            >/dev/null 2>&1; then


            info "Deleting partial database: $DB"


            gcloud sql databases delete \
                "$DB" \
                --instance="$DEST_INSTANCE" \
                --project="$PROJECT_ID" \
                --quiet \
                >/dev/null 2>&1


            if [[ $? -eq 0 ]]; then

                ok "$DB removed."

            else

                warn "Could not remove $DB."
            fi
        fi
    done


    # ========================================================
    # STEP 7 - CHECK CURRENT MINOR VERSION
    # ========================================================

    step "STEP 7 - Check Cloud SQL MySQL 8.0 minor version"


    SQL_JSON=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format=json
    )


    INSTALLED_VERSION=$(
        echo "$SQL_JSON" |
            jq -r '.databaseInstalledVersion // .databaseVersion'
    )


    echo

    info "Installed version: $INSTALLED_VERSION"


    MINOR_NUMBER=$(
        echo "$INSTALLED_VERSION" |
            sed -nE \
            's/^MYSQL_8_0_([0-9]+).*$/\1/p'
    )


    if [[ -z "$MINOR_NUMBER" ]]; then

        MINOR_NUMBER=0
    fi


    # ========================================================
    # STEP 8 - UPGRADE MINOR VERSION TO >= 8.0.37
    # ========================================================

    step "STEP 8 - Upgrade MySQL 8.0 minor version if required"


    if [[ "$MINOR_NUMBER" -ge 37 ]]; then


        ok "Current minor version is already >= 8.0.37."


    else


        mapfile -t MINOR_TARGETS < <(

            echo "$SQL_JSON" |

            jq -r \
                '.upgradableDatabaseVersions[]?.name' |

            grep -E \
                '^MYSQL_8_0_[0-9]+$' |

            sort -V
        )


        if [[ "${#MINOR_TARGETS[@]}" -eq 0 ]]; then

            err "No MySQL 8.0 minor upgrade target found."

            return 1
        fi


        MINOR_TARGET="${MINOR_TARGETS[-1]}"


        TARGET_MINOR_NUMBER=$(
            echo "$MINOR_TARGET" |
                sed -nE \
                's/^MYSQL_8_0_([0-9]+)$/\1/p'
        )


        if [[ "$TARGET_MINOR_NUMBER" -lt 37 ]]; then

            err "Latest available minor version is below 8.0.37."

            return 1
        fi


        info "Minor upgrade target: $MINOR_TARGET"


        gcloud sql instances patch \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --database-version="$MINOR_TARGET" \
            --quiet


        if [[ $? -ne 0 ]]; then

            err "Minor version upgrade failed."

            return 1
        fi


        wait_cloudsql || return 1


        ok "Minor version upgrade completed."
    fi


    # ========================================================
    # STEP 9 - UPGRADE MAJOR VERSION 8.0 -> 8.4
    # ========================================================

    step "STEP 9 - Upgrade Cloud SQL to MySQL 8.4"


    SQL_JSON=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format=json
    )


    INSTALLED_VERSION=$(
        echo "$SQL_JSON" |
            jq -r '.databaseInstalledVersion // .databaseVersion'
    )


    info "Current installed version: $INSTALLED_VERSION"


    if [[ "$INSTALLED_VERSION" == MYSQL_8_4* ]]; then


        ok "Cloud SQL is already MySQL 8.4."


    else


        echo
        info "Available upgrade versions:"


        echo "$SQL_JSON" |
            jq -r \
                '.upgradableDatabaseVersions[]?
                 | "\(.majorVersion) -> \(.name)"' |
            sed 's/^/  /'


        echo


        info "Upgrading MYSQL_8_0 → MYSQL_8_4..."


        gcloud sql instances patch \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --database-version=MYSQL_8_4 \
            --quiet


        if [[ $? -ne 0 ]]; then

            echo

            err "MySQL 8.4 major upgrade failed."

            echo

            gcloud sql instances describe \
                "$DEST_INSTANCE" \
                --project="$PROJECT_ID" \
                --format="yaml(databaseVersion,databaseInstalledVersion,instanceType,upgradableDatabaseVersions)"

            return 1
        fi


        wait_cloudsql || return 1


        ok "Cloud SQL upgraded to MySQL 8.4."
    fi


    # ========================================================
    # STEP 10 - CONFIRM VERSION
    # ========================================================

    step "STEP 10 - Confirm compatible versions"


    DEST_VERSION=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(databaseInstalledVersion)" \
            2>/dev/null
    )


    echo
    echo "Amazon RDS : $SOURCE_VERSION"
    echo "Cloud SQL  : $DEST_VERSION"
    echo


    if [[ "$DEST_VERSION" != MYSQL_8_4* ]]; then

        err "Cloud SQL is still not MySQL 8.4."

        return 1
    fi


    ok "Source and destination versions are now compatible."


    # ========================================================
    # STEP 11 - SOURCE PROFILE
    # ========================================================

    step "STEP 11 - Verify source connection profile"


    if gcloud database-migration connection-profiles describe \
        "$SOURCE_PROFILE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1; then


        ok "$SOURCE_PROFILE still exists."


    else


        warn "Source profile is missing. Recreating..."


        RDS_IP=$(
            dig +short A "$RDS_HOST" |
                grep -E \
                    '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
                tail -n1
        )


        gcloud database-migration \
            connection-profiles create mysql \
            "$SOURCE_PROFILE" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --display-name="$SOURCE_PROFILE" \
            --host="$RDS_IP" \
            --port="$SOURCE_DB_PORT" \
            --username="$SOURCE_DB_USER" \
            --password="$SOURCE_DB_PASSWORD" \
            --provider=RDS \
            --role=SOURCE \
            --ssl-type=NONE \
            --no-async \
            --quiet


        if [[ $? -ne 0 ]]; then

            err "Failed to recreate source profile."

            return 1
        fi


        ok "Source profile recreated."
    fi


    # ========================================================
    # STEP 12 - DEST PROFILE
    # ========================================================

    step "STEP 12 - Recreate Cloud SQL destination profile"


    if gcloud database-migration connection-profiles describe \
        "$DEST_PROFILE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1; then


        warn "Removing stale destination profile..."


        gcloud database-migration connection-profiles delete \
            "$DEST_PROFILE" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet \
            >/dev/null 2>&1
    fi


    gcloud database-migration \
        connection-profiles create mysql \
        "$DEST_PROFILE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --display-name="$DEST_PROFILE" \
        --cloudsql-instance="$DEST_INSTANCE" \
        --provider=CLOUDSQL \
        --role=DESTINATION \
        --no-async \
        --quiet


    if [[ $? -ne 0 ]]; then

        err "Failed to create destination profile."

        return 1
    fi


    ok "Destination profile created."


    # ========================================================
    # STEP 13 - CREATE MIGRATION JOB
    # ========================================================

    step "STEP 13 - Recreate one-time migration job"


    gcloud database-migration migration-jobs create \
        "$MIGRATION_JOB" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --display-name="$MIGRATION_JOB" \
        --source="$SOURCE_PROFILE" \
        --destination="$DEST_PROFILE" \
        --type=ONE_TIME \
        --static-ip \
        --all-databases \
        --no-async \
        --quiet


    if [[ $? -ne 0 ]]; then

        err "Failed to recreate migration job."

        return 1
    fi


    ok "Migration job recreated."


    # ========================================================
    # STEP 14 - DEMOTE DESTINATION
    # ========================================================

    step "STEP 14 - Demote destination for migration"


    run_dms_action \
        "demote-destination"


    if [[ $? -ne 0 ]]; then

        show_job_error

        err "Destination demotion failed."

        return 1
    fi


    # ========================================================
    # STEP 15 - WAIT OUTGOING IPS
    # ========================================================

    step "STEP 15 - Get new Destination outgoing IP addresses"


    OUTGOING_IPS=()


    for i in $(seq 1 120); do


        mapfile -t OUTGOING_IPS < <(
            get_outgoing_ips
        )


        if [[ "${#OUTGOING_IPS[@]}" -gt 0 ]]; then

            break
        fi


        info "Waiting for outgoing IP... $i/120"

        sleep 5
    done


    if [[ "${#OUTGOING_IPS[@]}" -eq 0 ]]; then

        err "No outgoing IP generated."

        return 1
    fi


    echo

    for IP in "${OUTGOING_IPS[@]}"; do

        echo "${GREEN}  → $IP${RESET}"
    done


    # ========================================================
    # STEP 16 - UPDATE AWS ALLOWLIST
    # ========================================================

    step "STEP 16 - Update AWS RDS IP allowlist"


    for IP in "${OUTGOING_IPS[@]}"; do


        info "Allow TCP 3306 from $IP/32"


        RESULT=$(
            aws ec2 authorize-security-group-ingress \
                --region=us-east-1 \
                --group-id="$AWS_SECURITY_GROUP" \
                --protocol=tcp \
                --port=3306 \
                --cidr="${IP}/32" \
                2>&1
        )


        RC=$?


        if [[ "$RC" -eq 0 ]]; then


            ok "$IP/32 added."


        elif echo "$RESULT" |
             grep -q \
                'InvalidPermission.Duplicate'; then


            ok "$IP/32 already exists."


        else


            echo "$RESULT"

            err "Failed to update AWS Security Group."

            return 1
        fi
    done


    echo

    info "Allowed TCP 3306 CIDRs:"


    aws ec2 describe-security-groups \
        --region=us-east-1 \
        --group-ids="$AWS_SECURITY_GROUP" \
        --query \
        'SecurityGroups[0].IpPermissions[?FromPort==`3306`].IpRanges[].CidrIp' \
        --output=text \
        2>/dev/null |
        tr '\t' '\n' |
        sed 's/^/  → /'


    sleep 10


    # ========================================================
    # STEP 17 - VERIFY
    # ========================================================

    step "STEP 17 - Test migration job"


    run_dms_action \
        "verify"


    if [[ $? -ne 0 ]]; then

        show_job_error

        err "Migration verification failed."

        return 1
    fi


    ok "Migration test passed."


    # ========================================================
    # STEP 18 - START
    # ========================================================

    step "STEP 18 - Start one-time migration"


    run_dms_action \
        "start"


    if [[ $? -ne 0 ]]; then

        show_job_error

        err "Failed to start migration."

        return 1
    fi


    # ========================================================
    # STEP 19 - WAIT
    # ========================================================

    step "STEP 19 - Wait for migration to complete"


    COMPLETED=0


    for i in $(seq 1 180); do


        STATE=$(get_job_state)

        PHASE=$(get_job_phase)


        printf \
            "${CYAN}➜ [%03d/180] %-15s Phase: %s${RESET}\n" \
            "$i" \
            "${STATE:-UNKNOWN}" \
            "${PHASE:-N/A}"


        if [[ "$STATE" == "COMPLETED" ]]; then


            COMPLETED=1

            echo

            ok "Migration completed."

            break
        fi


        if [[ "$STATE" == "FAILED" ]]; then


            show_job_error

            err "Migration failed."

            return 1
        fi


        sleep 10
    done


    if [[ "$COMPLETED" -ne 1 ]]; then

        err "Migration did not finish in time."

        return 1
    fi


    # ========================================================
    # STEP 20 - CHECK DATABASES
    # ========================================================

    step "STEP 20 - Confirm migrated databases"


    gcloud sql databases list \
        --instance="$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        --format="table(name)"


    DB_LIST=$(
        gcloud sql databases list \
            --instance="$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(name)"
    )


    if echo "$DB_LIST" |
       grep -qx \
           "customers_data"; then


        ok "customers_data found."

    else

        warn "customers_data not found."
    fi


    if echo "$DB_LIST" |
       grep -qx \
           "sales_data"; then


        ok "sales_data found."

    else

        warn "sales_data not found."
    fi


    # ========================================================
    # STEP 21 - RECORD COUNT
    # ========================================================

    step "STEP 21 - Check customers record count"


    SQL_PUBLIC_IP=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format=json |
            jq -r '
                .ipAddresses[]?
                | select(.type=="PRIMARY")
                | .ipAddress
            ' |
            head -n1
    )


    if [[ -n "$SQL_PUBLIC_IP" &&
          "$SQL_PUBLIC_IP" != "null" ]]; then


        if ! command -v mysql \
             >/dev/null 2>&1; then


            sudo apt-get update -qq

            sudo apt-get install \
                -y default-mysql-client \
                >/dev/null 2>&1
        fi


        COUNT=$(
            MYSQL_PWD="$DEST_DB_PASSWORD" \
            mysql \
                -h "$SQL_PUBLIC_IP" \
                -u "$DEST_DB_USER" \
                --connect-timeout=15 \
                --get-server-public-key \
                -Nse \
                'SELECT COUNT(*) FROM customers_data.customers;' \
                2>/dev/null
        )


        if [[ "$COUNT" == "5030" ]]; then

            ok "customers = 5,030 records."

        else

            warn "Record count result: ${COUNT:-unable to query}"
        fi
    fi


    # ========================================================
    # FINAL
    # ========================================================

    step "FINAL STATUS"


    FINAL_STATE=$(get_job_state)


    echo
    echo "${WHITE}Amazon RDS       : ${CYAN}$SOURCE_VERSION${RESET}"
    echo "${WHITE}Cloud SQL        : ${CYAN}$DEST_VERSION${RESET}"
    echo "${WHITE}Migration Job    : ${CYAN}$FINAL_STATE${RESET}"
    echo


    if [[ "$FINAL_STATE" == "COMPLETED" ]]; then


        echo "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
        echo "${GREEN}${BOLD}               ✓ GSP859 MIGRATION COMPLETE                 ${RESET}"
        echo "${GREEN}${BOLD}                       ePlus.DEV                            ${RESET}"
        echo "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"


        return 0
    fi


    return 1
}


# ============================================================
# RUN
# ============================================================

main

RC=$?

echo


if [[ "$RC" -eq 0 ]]; then

    echo "${GREEN}${BOLD}Script finished successfully.${RESET}"

else

    echo "${YELLOW}${BOLD}Script stopped because a step needs attention.${RESET}"
fi


echo "${GREEN}${BOLD}Cloud Shell remains open.${RESET}"

# NO exit