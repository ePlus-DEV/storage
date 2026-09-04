#!/bin/bash

# ============================================================
# GSP859
# Migrating Amazon RDS for MySQL to Cloud SQL
# Using Database Migration Service
#
# ePlus.DEV Cloud Tutorial
# ============================================================
#
# DESIGN
# ------------------------------------------------------------
# - Designed for a FRESH GSP859 lab
# - Detect Project / Region automatically
# - Ask only values supplied by Qwiklabs
# - AWS Access/Secret keys are VISIBLE when pasted
# - Detect Amazon RDS MySQL version
# - Automatically repair RDS 8.4 -> Cloud SQL 8.0 mismatch
# - Create source profile
# - Create destination profile
# - Create ONE_TIME migration job with IP allowlist
# - Demote existing mysql-cloudsql
# - Get REAL Cloud SQL OUTGOING IPs
# - Add all OUTGOING IPs to AWS SG port 3306
# - Verify migration
# - Start migration
# - Wait for COMPLETED
# - Verify customers_data / sales_data
# - Try to verify 5,030 customer records
#
# IMPORTANT
# ------------------------------------------------------------
# NO set -e
# NO exit
# Cloud Shell remains open if a step fails
# ============================================================


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

RESET=$'\033[0m'
BOLD=$'\033[1m'


# ============================================================
# LAB RESOURCE NAMES
# ============================================================

SOURCE_PROFILE="mysql-rds-source"

DEST_PROFILE="mysql-cloudsql-destination"

MIGRATION_JOB="rds-to-cloudsql"

DEST_INSTANCE="mysql-cloudsql"


# ============================================================
# DATABASE CREDENTIALS FROM LAB INSTRUCTIONS
# ============================================================

SOURCE_DB_USER="admin"

SOURCE_DB_PASSWORD="changeme"

SOURCE_DB_PORT="3306"


DEST_DB_USER="root"

DEST_DB_PASSWORD="supersecret"


# ============================================================
# DISPLAY FUNCTIONS
# ============================================================

header() {

    clear

    echo
    echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}        WELCOME TO ePlus.DEV CLOUD TUTORIAL                 ${RESET}"
    echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo "${MAGENTA}${BOLD} GSP859 - Amazon RDS MySQL → Cloud SQL MySQL${RESET}"
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


# ============================================================
# STRING HELPERS
# ============================================================

trim() {

    local VALUE="$1"

    VALUE="${VALUE#"${VALUE%%[![:space:]]*}"}"

    VALUE="${VALUE%"${VALUE##*[![:space:]]}"}"

    printf '%s' "$VALUE"
}


# ============================================================
# VERSION HELPERS
# ============================================================

normalize_source_major() {

    case "$1" in

        5.6*)
            echo "5.6"
            ;;

        5.7*)
            echo "5.7"
            ;;

        8.0*)
            echo "8.0"
            ;;

        8.4*)
            echo "8.4"
            ;;

        9.7*)
            echo "9.7"
            ;;

        *)
            echo "UNKNOWN"
            ;;
    esac
}


normalize_cloudsql_major() {

    case "$1" in

        MYSQL_5_6*)
            echo "5.6"
            ;;

        MYSQL_5_7*)
            echo "5.7"
            ;;

        MYSQL_8_0*)
            echo "8.0"
            ;;

        MYSQL_8_4*)
            echo "8.4"
            ;;

        MYSQL_9_7*)
            echo "9.7"
            ;;

        *)
            echo "UNKNOWN"
            ;;
    esac
}


versions_compatible() {

    local SRC="$1"

    local DST="$2"


    case "$SRC:$DST" in

        5.6:5.6|5.6:5.7)

            return 0
            ;;

        5.7:5.7|5.7:8.0)

            return 0
            ;;

        8.0:8.0|8.0:8.4)

            return 0
            ;;

        8.4:8.4|8.4:9.7)

            return 0
            ;;

        9.7:9.7)

            return 0
            ;;

        *)

            return 1
            ;;
    esac
}


# ============================================================
# CLOUD SQL HELPERS
# ============================================================

get_sql_json() {

    gcloud sql instances describe \
        "$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        --format=json \
        2>/dev/null
}


wait_cloudsql_runnable() {

    local STATE

    local COUNT=0


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


        if [[ "$COUNT" -ge 180 ]]; then

            err "Cloud SQL did not become RUNNABLE."

            return 1
        fi


        sleep 5
    done
}


get_outgoing_ips() {

    get_sql_json |

        jq -r '
            .ipAddresses[]?
            | select(.type == "OUTGOING")
            | .ipAddress
        ' |

        grep -E \
            '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |

        sort -u
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
# RUN AND WAIT DMS LONG-RUNNING OPERATION
# ============================================================

run_dms_action() {

    local ACTION="$1"

    local ACTION_JSON

    local ACTION_RC

    local OP_NAME

    local OP_ID

    local OP_JSON

    local DONE

    local ERROR_MESSAGE

    local COUNT=0

    local ERROR_FILE="/tmp/gsp859_${ACTION//-/_}.log"


    info "Running DMS action: $ACTION"


    ACTION_JSON=$(

        gcloud database-migration migration-jobs "$ACTION" \
            "$MIGRATION_JOB" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet \
            --format=json \
            2>"$ERROR_FILE"
    )


    ACTION_RC=$?


    if [[ "$ACTION_RC" -ne 0 ]]; then

        echo

        cat "$ERROR_FILE" \
            2>/dev/null

        echo

        err "Unable to submit DMS action '$ACTION'."

        return "$ACTION_RC"
    fi


    OP_NAME=$(

        printf '%s' "$ACTION_JSON" |

            jq -r \
                '.name // empty' \
                2>/dev/null
    )


    if [[ -z "$OP_NAME" ]]; then

        warn "No operation ID returned."

        sleep 5

        return 0
    fi


    OP_ID="${OP_NAME##*/}"


    info "Operation: $OP_ID"


    while true; do


        OP_JSON=$(

            gcloud database-migration operations describe \
                "$OP_ID" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --format=json \
                2>/dev/null
        )


        if [[ $? -ne 0 ||
              -z "$OP_JSON" ]]; then


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

            printf '%s' "$OP_JSON" |

                jq -r \
                    '.done // false'
        )


        if [[ "$DONE" == "true" ]]; then


            echo


            ERROR_MESSAGE=$(

                printf '%s' "$OP_JSON" |

                    jq -r \
                        '.error.message // empty'
            )


            if [[ -n "$ERROR_MESSAGE" ]]; then

                err "$ERROR_MESSAGE"

                return 1
            fi


            ok "DMS operation '$ACTION' completed."

            return 0
        fi


        printf "."


        sleep 5
    done
}


# ============================================================
# MAKE CLOUD SQL COMPATIBLE WITH SOURCE
# ============================================================

ensure_mysql_compatibility() {

    step "STEP 7 - Check MySQL source/destination compatibility"


    SOURCE_VERSION=$(

        aws rds describe-db-instances \
            --region="$AWS_REGION" \
            --query \
            "DBInstances[?Endpoint.Address=='$RDS_HOST'].EngineVersion | [0]" \
            --output=text \
            2>/dev/null
    )


    if [[ -z "$SOURCE_VERSION" ||
          "$SOURCE_VERSION" == "None" ]]; then


        warn "Could not match RDS hostname exactly."


        SOURCE_VERSION=$(

            aws rds describe-db-instances \
                --region="$AWS_REGION" \
                --query \
                'DBInstances[0].EngineVersion' \
                --output=text \
                2>/dev/null
        )
    fi


    if [[ -z "$SOURCE_VERSION" ||
          "$SOURCE_VERSION" == "None" ]]; then

        err "Unable to detect Amazon RDS MySQL version."

        return 1
    fi


    SQL_JSON=$(get_sql_json)


    DEST_VERSION=$(

        printf '%s' "$SQL_JSON" |

            jq -r \
                '.databaseVersion // empty'
    )


    INSTALLED_VERSION=$(

        printf '%s' "$SQL_JSON" |

            jq -r \
                '.databaseInstalledVersion // .databaseVersion // empty'
    )


    SOURCE_MAJOR=$(normalize_source_major "$SOURCE_VERSION")

    DEST_MAJOR=$(normalize_cloudsql_major "$DEST_VERSION")


    echo

    echo "${WHITE}Amazon RDS version        : ${CYAN}$SOURCE_VERSION${RESET}"

    echo "${WHITE}Cloud SQL version         : ${CYAN}$DEST_VERSION${RESET}"

    echo "${WHITE}Cloud SQL installed       : ${CYAN}$INSTALLED_VERSION${RESET}"

    echo "${WHITE}Source major              : ${CYAN}$SOURCE_MAJOR${RESET}"

    echo "${WHITE}Destination major         : ${CYAN}$DEST_MAJOR${RESET}"

    echo


    # --------------------------------------------------------
    # Already compatible
    # --------------------------------------------------------

    if versions_compatible \
        "$SOURCE_MAJOR" \
        "$DEST_MAJOR"; then


        ok "Source and destination versions are compatible."


        return 0
    fi


    # ========================================================
    # SPECIAL AUTO-REPAIR FOR CURRENT GSP859
    #
    # RDS 8.4.x
    # Cloud SQL 8.0
    #
    # Need:
    # 8.0 latest supported minor
    #        ↓
    # 8.4
    # ========================================================

    if [[ "$SOURCE_MAJOR" == "8.4" &&
          "$DEST_MAJOR" == "8.0" ]]; then


        warn "Detected GSP859 version mismatch."

        warn "Amazon RDS is MySQL 8.4 but mysql-cloudsql is MySQL 8.0."

        echo


        # ----------------------------------------------------
        # Check whether MYSQL_8_4 is already an available
        # upgrade target.
        # ----------------------------------------------------

        HAS_84=0


        printf '%s' "$SQL_JSON" |

            jq -r '
                .upgradableDatabaseVersions[]?
                | (.name // empty),
                  (.majorVersion // empty)
            ' |

            grep -qx \
                'MYSQL_8_4' && HAS_84=1


        # ----------------------------------------------------
        # If 8.4 is not yet available, upgrade MySQL 8.0
        # minor version first.
        # ----------------------------------------------------

        if [[ "$HAS_84" -ne 1 ]]; then


            info "MySQL 8.4 is not yet an available upgrade target."

            info "Checking MySQL 8.0 minor-version targets..."


            MINOR_TARGET=$(

                printf '%s' "$SQL_JSON" |

                    jq -r '
                        .upgradableDatabaseVersions[]?
                        | .name // empty
                    ' |

                    grep -E \
                        '^MYSQL_8_0_[0-9]+$' |

                    sort \
                        -t_ \
                        -k4,4n |

                    tail -n1
            )


            if [[ -z "$MINOR_TARGET" ]]; then

                err "No MySQL 8.0 minor upgrade target is available."

                echo

                gcloud sql instances describe \
                    "$DEST_INSTANCE" \
                    --project="$PROJECT_ID" \
                    --format="yaml(databaseVersion,databaseInstalledVersion,upgradableDatabaseVersions)"

                return 1
            fi


            info "Selected MySQL minor target: $MINOR_TARGET"


            gcloud sql instances patch \
                "$DEST_INSTANCE" \
                --project="$PROJECT_ID" \
                --database-version="$MINOR_TARGET" \
                --quiet


            if [[ $? -ne 0 ]]; then

                err "Cloud SQL minor-version upgrade failed."

                return 1
            fi


            wait_cloudsql_runnable ||
                return 1


            ok "Cloud SQL MySQL 8.0 minor upgrade completed."


            # ------------------------------------------------
            # Refresh instance information.
            # ------------------------------------------------

            SQL_JSON=$(get_sql_json)


            HAS_84=0


            printf '%s' "$SQL_JSON" |

                jq -r '
                    .upgradableDatabaseVersions[]?
                    | (.name // empty),
                      (.majorVersion // empty)
                ' |

                grep -qx \
                    'MYSQL_8_4' && HAS_84=1
        fi


        # ----------------------------------------------------
        # MySQL 8.4 should now be available.
        # ----------------------------------------------------

        if [[ "$HAS_84" -ne 1 ]]; then


            err "MYSQL_8_4 is still not an available upgrade target."


            echo

            gcloud sql instances describe \
                "$DEST_INSTANCE" \
                --project="$PROJECT_ID" \
                --format="yaml(databaseVersion,databaseInstalledVersion,upgradableDatabaseVersions)"

            echo


            return 1
        fi


        # ----------------------------------------------------
        # Upgrade 8.0 -> 8.4
        # ----------------------------------------------------

        info "Upgrading Cloud SQL MySQL 8.0 → MySQL 8.4..."


        gcloud sql instances patch \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --database-version=MYSQL_8_4 \
            --quiet


        if [[ $? -ne 0 ]]; then

            err "Cloud SQL MySQL 8.4 upgrade failed."

            return 1
        fi


        wait_cloudsql_runnable ||
            return 1


        # ----------------------------------------------------
        # Confirm
        # ----------------------------------------------------

        SQL_JSON=$(get_sql_json)


        DEST_VERSION=$(

            printf '%s' "$SQL_JSON" |

                jq -r \
                    '.databaseVersion // empty'
        )


        INSTALLED_VERSION=$(

            printf '%s' "$SQL_JSON" |

                jq -r \
                    '.databaseInstalledVersion // .databaseVersion // empty'
        )


        DEST_MAJOR=$(normalize_cloudsql_major "$DEST_VERSION")


        echo

        info "Cloud SQL configured version: $DEST_VERSION"

        info "Cloud SQL installed version : $INSTALLED_VERSION"


        if versions_compatible \
            "$SOURCE_MAJOR" \
            "$DEST_MAJOR"; then


            ok "Version mismatch repaired."

            ok "Amazon RDS $SOURCE_VERSION → Cloud SQL $DEST_VERSION is compatible."


            return 0
        fi


        err "Cloud SQL version is still incompatible."

        return 1
    fi


    # --------------------------------------------------------
    # Other unexpected combination
    # --------------------------------------------------------

    err "Unsupported source/destination version combination."

    echo

    echo "Source      : $SOURCE_VERSION"

    echo "Destination : $DEST_VERSION"

    echo


    return 1
}


# ============================================================
# MAIN
# ============================================================

main() {

    header


    # ========================================================
    # STEP 1 - LAB INPUT
    # ========================================================

    step "STEP 1 - Enter Lab Details"


    echo

    echo "${YELLOW}Copy these values from the Lab Details panel:${RESET}"

    echo

    echo "  • AWS RDS Database - Source"

    echo "  • AWS RDS Database Security Group"

    echo "  • AWS Access Key ID"

    echo "  • AWS Secret Access Key"

    echo

    echo "${GREEN}${BOLD}All pasted values are VISIBLE.${RESET}"

    echo

    echo "${YELLOW}AWS Username and AWS Password are NOT required.${RESET}"

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


    echo


    RDS_HOST=$(trim "$RDS_HOST")

    AWS_SECURITY_GROUP=$(trim "$AWS_SECURITY_GROUP")

    AWS_ACCESS_KEY_ID=$(trim "$AWS_ACCESS_KEY_ID")

    AWS_SECRET_ACCESS_KEY=$(trim "$AWS_SECRET_ACCESS_KEY")


    RDS_HOST="${RDS_HOST%.}"


    if [[ -z "$RDS_HOST" ]]; then

        err "AWS RDS Database - Source cannot be empty."

        return 1
    fi


    if [[ -z "$AWS_SECURITY_GROUP" ]]; then

        err "AWS Security Group cannot be empty."

        return 1
    fi


    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then

        err "AWS Access Key ID cannot be empty."

        return 1
    fi


    if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then

        err "AWS Secret Access Key cannot be empty."

        return 1
    fi


    export AWS_ACCESS_KEY_ID

    export AWS_SECRET_ACCESS_KEY


    unset AWS_SESSION_TOKEN \
        2>/dev/null


    ok "Lab information received."


    info "RDS Source     : $RDS_HOST"

    info "Security Group : $AWS_SECURITY_GROUP"


    # ========================================================
    # STEP 2 - PROJECT
    # ========================================================

    step "STEP 2 - Detect Google Cloud project"


    PROJECT_ID=$(

        gcloud config get-value project \
            2>/dev/null
    )


    if [[ -z "$PROJECT_ID" ||
          "$PROJECT_ID" == "(unset)" ]]; then


        PROJECT_ID=$(

            gcloud projects list \
                --filter="lifecycleState=ACTIVE" \
                --format="value(projectId)" \
                --limit=1 \
                2>/dev/null
        )


        if [[ -z "$PROJECT_ID" ]]; then

            err "Unable to detect Google Cloud Project ID."

            return 1
        fi


        gcloud config set project \
            "$PROJECT_ID" \
            >/dev/null 2>&1
    fi


    ok "Project: $PROJECT_ID"


    # ========================================================
    # STEP 3 - WAIT FOR CLOUD SQL
    # ========================================================

    step "STEP 3 - Detect Cloud SQL destination"


    FOUND_SQL=0


    for i in $(seq 1 60); do


        if gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            >/dev/null 2>&1; then


            FOUND_SQL=1

            break
        fi


        info "Waiting for $DEST_INSTANCE... $i/60"


        sleep 10
    done


    if [[ "$FOUND_SQL" -ne 1 ]]; then

        err "Cloud SQL instance '$DEST_INSTANCE' was not found."

        return 1
    fi


    REGION=$(

        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(region)" \
            2>/dev/null
    )


    if [[ -z "$REGION" ]]; then

        err "Unable to detect Cloud SQL region."

        return 1
    fi


    ok "Cloud SQL : $DEST_INSTANCE"

    ok "Region    : $REGION"


    # ========================================================
    # STEP 4 - GOOGLE APIS
    # ========================================================

    step "STEP 4 - Enable required Google APIs"


    gcloud services enable \
        datamigration.googleapis.com \
        sqladmin.googleapis.com \
        --project="$PROJECT_ID" \
        --quiet \
        >/tmp/gsp859_api.log \
        2>&1


    if [[ $? -ne 0 ]]; then


        warn "API command returned a warning/error."

        cat /tmp/gsp859_api.log \
            2>/dev/null


    else


        ok "Required APIs ready."
    fi


    sleep 5


    # ========================================================
    # STEP 5 - UTILITIES
    # ========================================================

    step "STEP 5 - Prepare required utilities"


    # --------------------------------------------------------
    # jq
    # --------------------------------------------------------

    if ! command -v jq \
        >/dev/null 2>&1; then


        info "Installing jq..."


        sudo apt-get update -qq


        sudo apt-get install \
            -y jq \
            >/dev/null


        if [[ $? -ne 0 ]]; then

            err "Unable to install jq."

            return 1
        fi
    fi


    ok "jq ready."


    # --------------------------------------------------------
    # dig
    # --------------------------------------------------------

    if ! command -v dig \
        >/dev/null 2>&1; then


        info "Installing dnsutils..."


        sudo apt-get update -qq


        sudo apt-get install \
            -y dnsutils \
            >/dev/null


        if [[ $? -ne 0 ]]; then

            err "Unable to install dnsutils."

            return 1
        fi
    fi


    ok "dig ready."


    # --------------------------------------------------------
    # AWS CLI
    # --------------------------------------------------------

    if ! command -v aws \
        >/dev/null 2>&1; then


        info "Installing AWS CLI v2..."


        if ! command -v unzip \
            >/dev/null 2>&1; then


            sudo apt-get update -qq


            sudo apt-get install \
                -y unzip \
                >/dev/null
        fi


        rm -rf \
            /tmp/aws \
            /tmp/awscliv2.zip


        curl -fsSL \
            "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
            -o /tmp/awscliv2.zip


        if [[ $? -ne 0 ]]; then

            err "Unable to download AWS CLI."

            return 1
        fi


        unzip -q \
            /tmp/awscliv2.zip \
            -d /tmp


        if [[ $? -ne 0 ]]; then

            err "Unable to extract AWS CLI."

            return 1
        fi


        sudo /tmp/aws/install \
            --update \
            >/dev/null


        if [[ $? -ne 0 ]]; then

            err "Unable to install AWS CLI."

            return 1
        fi


        rm -rf \
            /tmp/aws \
            /tmp/awscliv2.zip
    fi


    ok "AWS CLI ready."


    # ========================================================
    # STEP 6 - AWS ACCESS / RDS IP
    # ========================================================

    step "STEP 6 - Verify AWS and resolve RDS"


    AWS_REGION=$(

        printf '%s' "$RDS_HOST" |

            grep -oE \
                '[a-z]{2}(-gov)?-[a-z0-9-]+-[0-9]+\.rds\.amazonaws\.com' |

            head -n1 |

            cut -d. -f1
    )


    if [[ -z "$AWS_REGION" ]]; then

        AWS_REGION="us-east-1"

        warn "Could not detect AWS region."

        warn "Using lab default: us-east-1"
    fi


    export AWS_DEFAULT_REGION="$AWS_REGION"


    ok "AWS Region: $AWS_REGION"


    AWS_ACCOUNT=$(

        aws sts get-caller-identity \
            --region="$AWS_REGION" \
            --query='Account' \
            --output=text \
            2>/tmp/gsp859_aws.log
    )


    if [[ $? -ne 0 ]]; then


        cat /tmp/gsp859_aws.log \
            2>/dev/null


        err "AWS credentials are invalid."


        return 1
    fi


    ok "AWS credentials accepted. Account: $AWS_ACCOUNT"


    if ! aws ec2 describe-security-groups \
        --region="$AWS_REGION" \
        --group-ids="$AWS_SECURITY_GROUP" \
        >/dev/null \
        2>/tmp/gsp859_sg.log; then


        cat /tmp/gsp859_sg.log \
            2>/dev/null


        err "AWS Security Group not found."


        return 1
    fi


    ok "Security Group found: $AWS_SECURITY_GROUP"


    # --------------------------------------------------------
    # RDS IP
    # --------------------------------------------------------

    RDS_IP=""


    for i in $(seq 1 60); do


        RDS_IP=$(

            dig +short A \
                "$RDS_HOST" |

                grep -E \
                    '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |

                tail -n1
        )


        if [[ -n "$RDS_IP" ]]; then

            break
        fi


        info "Waiting for RDS DNS... $i/60"


        sleep 10
    done


    if [[ -z "$RDS_IP" ]]; then

        err "Unable to resolve Amazon RDS hostname."

        return 1
    fi


    ok "RDS Host : $RDS_HOST"

    ok "RDS IP   : $RDS_IP"


    # ========================================================
    # STEP 7 - VERSION COMPATIBILITY
    # ========================================================

    ensure_mysql_compatibility ||
        return 1


    # ========================================================
    # STEP 8 - CREATE SOURCE PROFILE
    # ========================================================

    step "STEP 8 - Create source connection profile"


    if gcloud database-migration connection-profiles describe \
        "$SOURCE_PROFILE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1; then


        ok "$SOURCE_PROFILE already exists."


    else


        gcloud database-migration \
            connection-profiles \
            create mysql \
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
            --quiet \
            >/tmp/gsp859_source.log \
            2>&1


        if [[ $? -ne 0 ]]; then


            cat /tmp/gsp859_source.log


            err "Failed to create source connection profile."


            return 1
        fi


        ok "Created source profile: $SOURCE_PROFILE"
    fi


    # ========================================================
    # STEP 9 - DESTINATION PROFILE
    # ========================================================

    step "STEP 9 - Create destination connection profile"


    if gcloud database-migration connection-profiles describe \
        "$DEST_PROFILE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1; then


        ok "$DEST_PROFILE already exists."


    else


        gcloud database-migration \
            connection-profiles \
            create mysql \
            "$DEST_PROFILE" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --display-name="$DEST_PROFILE" \
            --cloudsql-instance="$DEST_INSTANCE" \
            --provider=CLOUDSQL \
            --role=DESTINATION \
            --no-async \
            --quiet \
            >/tmp/gsp859_destination.log \
            2>&1


        if [[ $? -ne 0 ]]; then


            cat /tmp/gsp859_destination.log


            err "Failed to create destination connection profile."


            return 1
        fi


        ok "Created destination profile: $DEST_PROFILE"
    fi


    # ========================================================
    # STEP 10 - MIGRATION JOB
    # ========================================================

    step "STEP 10 - Create one-time migration job"


    if gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1; then


        ok "$MIGRATION_JOB already exists."


    else


        gcloud database-migration \
            migration-jobs create \
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
            --quiet \
            >/tmp/gsp859_job.log \
            2>&1


        if [[ $? -ne 0 ]]; then


            cat /tmp/gsp859_job.log


            err "Failed to create migration job."


            return 1
        fi


        ok "Created migration job: $MIGRATION_JOB"
    fi


    # ========================================================
    # STEP 11 - DEMOTE EXISTING DESTINATION
    # ========================================================

    step "STEP 11 - Prepare existing Cloud SQL destination"


    mapfile -t OUTGOING_IPS < <(
        get_outgoing_ips
    )


    if [[ "${#OUTGOING_IPS[@]}" -gt 0 ]]; then


        ok "Destination is already prepared."


    else


        STATE=$(get_job_state)


        info "Current migration state: ${STATE:-UNKNOWN}"


        run_dms_action \
            "demote-destination"


        if [[ $? -ne 0 ]]; then


            show_job_error


            err "Destination demotion failed."


            return 1
        fi
    fi


    # ========================================================
    # STEP 12 - GET OUTGOING IPS
    # ========================================================

    step "STEP 12 - Get Destination outgoing IP addresses"


    OUTGOING_IPS=()


    for i in $(seq 1 120); do


        mapfile -t OUTGOING_IPS < <(
            get_outgoing_ips
        )


        if [[ "${#OUTGOING_IPS[@]}" -gt 0 ]]; then

            break
        fi


        STATE=$(get_job_state)


        info \
            "Waiting for OUTGOING IP... $i/120 | state=${STATE:-UNKNOWN}"


        sleep 5
    done


    if [[ "${#OUTGOING_IPS[@]}" -eq 0 ]]; then


        err "Cloud SQL OUTGOING IP was not generated."


        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="yaml(instanceType,state,ipAddresses)"


        return 1
    fi


    echo

    echo "${GREEN}${BOLD}Destination outgoing IP address(es):${RESET}"


    for IP in "${OUTGOING_IPS[@]}"; do

        echo "  → $IP"
    done


    # ========================================================
    # STEP 13 - AWS IP ALLOWLIST
    # ========================================================

    step "STEP 13 - Configure AWS RDS IP allowlist"


    for IP in "${OUTGOING_IPS[@]}"; do


        info "Allow TCP 3306 from $IP/32"


        AWS_RESULT=$(

            aws ec2 authorize-security-group-ingress \
                --region="$AWS_REGION" \
                --group-id="$AWS_SECURITY_GROUP" \
                --protocol=tcp \
                --port=3306 \
                --cidr="${IP}/32" \
                2>&1
        )


        AWS_RC=$?


        if [[ "$AWS_RC" -eq 0 ]]; then


            ok "$IP/32 added."


        elif printf '%s' "$AWS_RESULT" |
             grep -q \
                'InvalidPermission.Duplicate'; then


            ok "$IP/32 already exists."


        else


            echo "$AWS_RESULT"


            err "Failed to add $IP/32 to AWS Security Group."


            return 1
        fi
    done


    echo

    info "Current TCP/3306 allowlist:"


    SG_CIDRS=$(

        aws ec2 describe-security-groups \
            --region="$AWS_REGION" \
            --group-ids="$AWS_SECURITY_GROUP" \
            --query \
            'SecurityGroups[0].IpPermissions[?FromPort==`3306`].IpRanges[].CidrIp' \
            --output=text \
            2>/dev/null
    )


    printf '%s\n' "$SG_CIDRS" |

        tr '\t' '\n' |

        sed 's/^/  → /'


    echo

    info "Waiting 20 seconds for AWS rule propagation..."


    sleep 20


    # ========================================================
    # STEP 14 - VERIFY
    # ========================================================

    step "STEP 14 - Test migration job"


    STATE=$(get_job_state)


    info "Current state: ${STATE:-UNKNOWN}"


    case "$STATE" in


        STARTING|RUNNING|COMPLETED)

            ok "Migration has already passed verification."


            ;;


        *)

            run_dms_action \
                "verify"


            if [[ $? -ne 0 ]]; then


                show_job_error


                err "Migration job verification failed."


                return 1
            fi


            ok "Migration test passed."


            ;;
    esac


    # ========================================================
    # STEP 15 - START
    # ========================================================

    step "STEP 15 - Start one-time migration job"


    STATE=$(get_job_state)


    info "Current state: ${STATE:-UNKNOWN}"


    case "$STATE" in


        COMPLETED)

            ok "Migration already completed."

            ;;


        STARTING|RUNNING|RESTARTING)

            ok "Migration is already running."

            ;;


        FAILED)

            info "Restarting migration job..."


            run_dms_action \
                "restart"


            if [[ $? -ne 0 ]]; then


                show_job_error


                err "Migration restart failed."


                return 1
            fi

            ;;


        *)

            run_dms_action \
                "start"


            if [[ $? -ne 0 ]]; then


                show_job_error


                err "Failed to start migration."


                return 1
            fi

            ;;
    esac


    # ========================================================
    # STEP 16 - WAIT FOR COMPLETED
    # ========================================================

    step "STEP 16 - Wait for migration to complete"


    COMPLETED_OK=0


    for i in $(seq 1 240); do


        STATE=$(get_job_state)

        PHASE=$(get_job_phase)


        printf \
            "${CYAN}➜ [%03d/240] State: %-15s Phase: %s${RESET}\n" \
            "$i" \
            "${STATE:-UNKNOWN}" \
            "${PHASE:-N/A}"


        if [[ "$STATE" == "COMPLETED" ]]; then


            COMPLETED_OK=1


            echo


            ok "Migration completed successfully."


            break
        fi


        if [[ "$STATE" == "FAILED" ]]; then


            show_job_error


            err "Migration failed."


            return 1
        fi


        sleep 10
    done


    if [[ "$COMPLETED_OK" -ne 1 ]]; then


        err "Migration did not reach COMPLETED in time."


        return 1
    fi


    # ========================================================
    # STEP 17 - VERIFY DATABASES
    # ========================================================

    step "STEP 17 - Verify migrated databases"


    gcloud sql databases list \
        --instance="$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        --format="table(name)"


    DB_LIST=$(

        gcloud sql databases list \
            --instance="$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(name)" \
            2>/dev/null
    )


    echo


    if printf '%s\n' "$DB_LIST" |
       grep -qx \
           'customers_data'; then


        ok "customers_data found."


    else


        warn "customers_data not found."
    fi


    if printf '%s\n' "$DB_LIST" |
       grep -qx \
           'sales_data'; then


        ok "sales_data found."


    else


        warn "sales_data not found."
    fi


    # ========================================================
    # STEP 18 - TRY RECORD COUNT
    # ========================================================

    step "STEP 18 - Verify customers table record count"


    SQL_PUBLIC_IP=$(

        get_sql_json |

            jq -r '
                .ipAddresses[]?
                | select(.type == "PRIMARY")
                | .ipAddress
            ' |

            head -n1
    )


    if [[ -z "$SQL_PUBLIC_IP" ||
          "$SQL_PUBLIC_IP" == "null" ]]; then


        warn "Cloud SQL public IP not found."


    else


        ok "Cloud SQL Public IP: $SQL_PUBLIC_IP"


        if ! command -v mysql \
             >/dev/null 2>&1; then


            info "Installing MySQL client..."


            sudo apt-get update -qq


            sudo apt-get install \
                -y default-mysql-client \
                >/dev/null 2>&1
        fi


        if command -v mysql \
             >/dev/null 2>&1; then


            CUSTOMER_COUNT=$(

                MYSQL_PWD="$DEST_DB_PASSWORD" \
                mysql \
                    -h "$SQL_PUBLIC_IP" \
                    -u "$DEST_DB_USER" \
                    --connect-timeout=15 \
                    --get-server-public-key \
                    -Nse \
                    'SELECT COUNT(*) FROM customers_data.customers;' \
                    2>/tmp/gsp859_mysql.log
            )


            if [[ $? -eq 0 ]]; then


                info "customers_data.customers = $CUSTOMER_COUNT"


                if [[ "$CUSTOMER_COUNT" == "5030" ]]; then


                    ok "Correct record count: 5,030."


                else


                    warn "Lab expects 5,030 records."

                    warn "Current result: $CUSTOMER_COUNT"
                fi


            else


                warn "Direct MySQL connection from Cloud Shell failed."

                warn "Migration itself is already COMPLETED."
            fi
        fi
    fi


    # ========================================================
    # FINAL
    # ========================================================

    step "FINAL STATUS"


    FINAL_STATE=$(get_job_state)


    FINAL_SQL_VERSION=$(

        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(databaseVersion)" \
            2>/dev/null
    )


    echo

    echo "${WHITE}Project        : ${CYAN}$PROJECT_ID${RESET}"

    echo "${WHITE}GCP Region     : ${CYAN}$REGION${RESET}"

    echo "${WHITE}AWS Region     : ${CYAN}$AWS_REGION${RESET}"

    echo "${WHITE}RDS Version    : ${CYAN}$SOURCE_VERSION${RESET}"

    echo "${WHITE}Cloud SQL      : ${CYAN}$FINAL_SQL_VERSION${RESET}"

    echo "${WHITE}RDS IP         : ${CYAN}$RDS_IP${RESET}"

    echo "${WHITE}Security Group : ${CYAN}$AWS_SECURITY_GROUP${RESET}"

    echo "${WHITE}Source Profile : ${CYAN}$SOURCE_PROFILE${RESET}"

    echo "${WHITE}Destination    : ${CYAN}$DEST_INSTANCE${RESET}"

    echo "${WHITE}Migration Job  : ${CYAN}$MIGRATION_JOB${RESET}"

    echo "${WHITE}State          : ${CYAN}$FINAL_STATE${RESET}"

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

    echo "${GREEN}${BOLD}Cloud Shell remains open.${RESET}"


else


    echo "${YELLOW}${BOLD}Script stopped because a step needs attention.${RESET}"

    echo "${GREEN}${BOLD}Cloud Shell remains open.${RESET}"

    echo

    echo "Review the error above before running again."
fi


# ============================================================
# INTENTIONALLY NO:
#
# exit
#
# ============================================================