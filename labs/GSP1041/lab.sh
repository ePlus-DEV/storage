#!/bin/bash

# ============================================================
# BigQuery Authorized Views Challenge Lab
# CHECK PROGRESS TASKS ONLY
# SOURCE SAFE
#
# © ePlus.DEV
# ============================================================

(
set -Eeuo pipefail

# ============================================================
# COLORS
# ============================================================

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED="$(tput setaf 1 2>/dev/null || true)"
    GREEN="$(tput setaf 2 2>/dev/null || true)"
    YELLOW="$(tput setaf 3 2>/dev/null || true)"
    BLUE="$(tput setaf 4 2>/dev/null || true)"
    MAGENTA="$(tput setaf 5 2>/dev/null || true)"
    CYAN="$(tput setaf 6 2>/dev/null || true)"
    WHITE="$(tput setaf 7 2>/dev/null || true)"
    BOLD="$(tput bold 2>/dev/null || true)"
    RESET="$(tput sgr0 2>/dev/null || true)"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    WHITE=""
    BOLD=""
    RESET=""
fi

# ============================================================
# CONSTANTS
#
# NO QWIKLABS PROJECT ID IS HARD-CODED
# ============================================================

PARTNER_DATASET="demo_dataset"

VIEW_A="authorized_view_a"
VIEW_B="authorized_view_b"

CUSTOMER_A_DATASET="customer_a_dataset"
CUSTOMER_A_TABLE="customer_a_table"

CUSTOMER_B_DATASET="customer_b_dataset"
CUSTOMER_B_TABLE="customer_b_table"

CUSTOMER_INFO_TABLE="customer_info"

# ============================================================
# VARIABLES
# ============================================================

CUSTOMER_A_USER=""
CUSTOMER_B_USER=""

CURRENT_PROJECT=""
CURRENT_ACCOUNT=""
PROJECT_ROLE=""

PARTNER_PROJECT=""

TMP_FILES=()

# ============================================================
# CLEANUP
# ============================================================

cleanup() {
    if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
        rm -f "${TMP_FILES[@]}" 2>/dev/null || true
    fi

    printf "%s" "$RESET" 2>/dev/null || true
}

trap cleanup EXIT

# ============================================================
# UI
# ============================================================

banner() {
    echo
    echo "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║          BIGQUERY AUTHORIZED VIEWS CHALLENGE LAB             ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║                  CHECK PROGRESS ONLY                         ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║                      © ePlus.DEV                             ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

step() {
    echo
    echo "${MAGENTA}${BOLD}$1${RESET}"
    echo "${BLUE}${BOLD}==============================================================${RESET}"
}

info() {
    echo "${CYAN}➜ $*${RESET}"
}

ok() {
    echo "${GREEN}${BOLD}✓ $*${RESET}"
}

warn() {
    echo "${YELLOW}${BOLD}⚠ $*${RESET}"
}

fail() {
    echo
    echo "${RED}${BOLD}✗ $*${RESET}"
    exit 1
}

# ============================================================
# COLORED INPUT
# ============================================================

colored_read() {
    local variable="$1"
    local label="$2"
    local value=""

    printf "%s%s%s%s %s>%s " \
        "$YELLOW" \
        "$BOLD" \
        "$label" \
        "$RESET" \
        "$GREEN" \
        "$CYAN"

    IFS= read -r value

    printf "%s" "$RESET"

    printf -v "$variable" '%s' "$value"
}

# ============================================================
# VALIDATION
# ============================================================

valid_email() {
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

valid_project() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
}

# ============================================================
# ASK USER A + B IMMEDIATELY
#
# NO GCLOUD / BQ NETWORK CALL BEFORE THIS.
# ============================================================

ask_users() {
    step "ENTER CUSTOMER ACCOUNTS"

    echo "${WHITE}Copy Customer A and Customer B users from the lab panel.${RESET}"
    echo
    echo "${WHITE}Example:${RESET}"
    echo "${CYAN}student-02-xxxxxxxxxxxx@qwiklabs.net${RESET}"
    echo

    # --------------------------------------------------------
    # CUSTOMER A
    # --------------------------------------------------------

    while true; do
        colored_read CUSTOMER_A_USER "Customer A user"
        echo

        if valid_email "$CUSTOMER_A_USER"; then
            break
        fi

        warn "Invalid Customer A email."
        echo
    done

    echo

    # --------------------------------------------------------
    # CUSTOMER B
    # --------------------------------------------------------

    while true; do
        colored_read CUSTOMER_B_USER "Customer B user"
        echo

        if valid_email "$CUSTOMER_B_USER"; then
            break
        fi

        warn "Invalid Customer B email."
        echo
    done

    echo
    echo "${BLUE}--------------------------------------------------------------${RESET}"
    echo "${WHITE}${BOLD}INPUT SUMMARY${RESET}"
    echo "${BLUE}--------------------------------------------------------------${RESET}"
    echo "${WHITE}Customer A : ${CYAN}${BOLD}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}Customer B : ${MAGENTA}${BOLD}${CUSTOMER_B_USER}${RESET}"
    echo "${BLUE}--------------------------------------------------------------${RESET}"
}

# ============================================================
# REQUIRED COMMAND
# ============================================================

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || \
        fail "Required command not found: $1"
}

# ============================================================
# DETECT CURRENT PROJECT
# ============================================================

detect_current_project() {
    step "DETECT GOOGLE CLOUD ENVIRONMENT"

    info "Detecting current project..."

    CURRENT_PROJECT="${DEVSHELL_PROJECT_ID:-}"

    if [[ -z "$CURRENT_PROJECT" ]]; then
        CURRENT_PROJECT="$(
            timeout 10s \
            gcloud config get-value project \
            2>/dev/null || true
        )"
    fi

    if [[ -z "$CURRENT_PROJECT" || "$CURRENT_PROJECT" == "(unset)" ]]; then
        warn "Unable to detect current Project ID automatically."
        echo

        while true; do
            colored_read CURRENT_PROJECT "Current Project ID"
            echo

            if valid_project "$CURRENT_PROJECT"; then
                break
            fi

            warn "Invalid Google Cloud Project ID."
            echo
        done
    fi

    ok "Current project: ${CURRENT_PROJECT}"
}

# ============================================================
# DETECT ACCOUNT
# ============================================================

detect_current_account() {
    CURRENT_ACCOUNT="$(
        timeout 10s \
        gcloud auth list \
            --filter=status:ACTIVE \
            --format='value(account)' \
        2>/dev/null |
        head -n1 || true
    )"

    [[ -n "$CURRENT_ACCOUNT" ]] || CURRENT_ACCOUNT="unknown"
}

# ============================================================
# DETECT CURRENT ROLE
#
# demo_dataset       -> Partner
# customer_a_dataset -> Customer A
# customer_b_dataset -> Customer B
# ============================================================

detect_project_role() {
    step "DETECT LAB ROLE"

    info "Reading datasets in current project..."

    local datasets=""

    if ! datasets="$(
        timeout 25s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            ls \
            --format=prettyjson \
        2>/dev/null
    )"; then
        PROJECT_ROLE="UNKNOWN"

        warn "Unable to detect lab role automatically."
        return
    fi

    # --------------------------------------------------------
    # PARTNER
    # --------------------------------------------------------

    if jq -e \
        --arg dataset "$PARTNER_DATASET" \
        'any(.[]?; .datasetReference.datasetId == $dataset)' \
        <<< "$datasets" \
        >/dev/null 2>&1; then

        PROJECT_ROLE="PARTNER"
        PARTNER_PROJECT="$CURRENT_PROJECT"

        ok "Detected Data Sharing Partner."
        return
    fi

    # --------------------------------------------------------
    # CUSTOMER A
    # --------------------------------------------------------

    if jq -e \
        --arg dataset "$CUSTOMER_A_DATASET" \
        'any(.[]?; .datasetReference.datasetId == $dataset)' \
        <<< "$datasets" \
        >/dev/null 2>&1; then

        PROJECT_ROLE="CUSTOMER_A"

        ok "Detected Customer A."
        return
    fi

    # --------------------------------------------------------
    # CUSTOMER B
    # --------------------------------------------------------

    if jq -e \
        --arg dataset "$CUSTOMER_B_DATASET" \
        'any(.[]?; .datasetReference.datasetId == $dataset)' \
        <<< "$datasets" \
        >/dev/null 2>&1; then

        PROJECT_ROLE="CUSTOMER_B"

        ok "Detected Customer B."
        return
    fi

    PROJECT_ROLE="UNKNOWN"

    warn "Unable to detect lab role automatically."
}

# ============================================================
# MANUAL ROLE FALLBACK
# ============================================================

ask_project_role() {
    step "SELECT CURRENT PROJECT TYPE"

    echo "${WHITE}Which console are you currently using?${RESET}"
    echo
    echo "  ${CYAN}${BOLD}1${RESET}) Data Sharing Partner"
    echo "  ${CYAN}${BOLD}2${RESET}) Customer A"
    echo "  ${CYAN}${BOLD}3${RESET}) Customer B"
    echo

    local choice=""

    while true; do
        colored_read choice "Select"
        echo

        case "$choice" in

            1)
                PROJECT_ROLE="PARTNER"
                PARTNER_PROJECT="$CURRENT_PROJECT"
                break
                ;;

            2)
                PROJECT_ROLE="CUSTOMER_A"
                break
                ;;

            3)
                PROJECT_ROLE="CUSTOMER_B"
                break
                ;;

            *)
                warn "Please enter 1, 2 or 3."
                echo
                ;;
        esac
    done
}

# ============================================================
# ASK PARTNER PROJECT
#
# Needed from Customer A / Customer B console.
# ============================================================

ask_partner_project() {
    step "ENTER DATA SHARING PARTNER PROJECT"

    echo "${WHITE}Copy the Data Sharing Partner Project ID from the lab panel.${RESET}"
    echo

    while true; do
        colored_read PARTNER_PROJECT "Partner Project ID"
        echo

        if valid_project "$PARTNER_PROJECT"; then
            break
        fi

        warn "Invalid Partner Project ID."
        echo
    done

    ok "Partner project: ${PARTNER_PROJECT}"
}

# ============================================================
# GET DATASET LOCATION
# ============================================================

get_location() {
    local project="$1"
    local dataset="$2"

    local location=""

    location="$(
        timeout 20s \
        bq \
            --project_id="$project" \
            --quiet \
            show \
            --format=prettyjson \
            "$project:$dataset" \
        2>/dev/null |
        jq -r '.location // empty' || true
    )"

    if [[ -z "$location" ]]; then
        location="US"
    fi

    printf "%s" "$location"
}

# ============================================================
# TASK 1
# CREATE AUTHORIZED VIEWS
# ============================================================

task1() {
    step "[1/4] TASK 1 - CREATE AUTHORIZED VIEWS"

    local location

    location="$(
        get_location \
            "$CURRENT_PROJECT" \
            "$PARTNER_DATASET"
    )"

    echo "${WHITE}Project  : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Dataset  : ${CYAN}${PARTNER_DATASET}${RESET}"
    echo "${WHITE}Location : ${CYAN}${location}${RESET}"

    # ========================================================
    # AUTHORIZED VIEW A - TEXAS
    # ========================================================

    echo
    info "Creating ${VIEW_A} for Texas..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CURRENT_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        AS

        SELECT *
        FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`
        WHERE state_code = 'TX'
        LIMIT 4000
        "

    ok "${VIEW_A} created."

    # ========================================================
    # AUTHORIZED VIEW B - CALIFORNIA
    # ========================================================

    echo
    info "Creating ${VIEW_B} for California..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CURRENT_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        AS

        SELECT *
        FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`
        WHERE state_code = 'CA'
        LIMIT 4000
        "

    ok "${VIEW_B} created."

    echo
    ok "TASK 1 COMPLETED"
}

# ============================================================
# TASK 2
# AUTHORIZE BOTH VIEWS
# ============================================================

task2() {
    step "[2/4] TASK 2 - AUTHORIZE BOTH VIEWS"

    local source_json
    local update_json

    source_json="$(mktemp)"
    update_json="$(mktemp)"

    TMP_FILES+=("$source_json" "$update_json")

    # --------------------------------------------------------
    # READ CURRENT DATASET ACCESS
    # --------------------------------------------------------

    info "Reading ${PARTNER_DATASET} access list..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        --format=prettyjson \
        "$CURRENT_PROJECT:$PARTNER_DATASET" \
        > "$source_json"

    # --------------------------------------------------------
    # PRESERVE CURRENT ACL
    # REMOVE DUPLICATE AUTHORIZED VIEW ENTRIES
    # ADD VIEW A + VIEW B
    # --------------------------------------------------------

    info "Authorizing ${VIEW_A} and ${VIEW_B}..."

    jq \
        --arg project "$CURRENT_PROJECT" \
        --arg dataset "$PARTNER_DATASET" \
        --arg view_a "$VIEW_A" \
        --arg view_b "$VIEW_B" \
        '
        {
            "access":
            (
                [
                    (.access // [])[]
                    |
                    select(
                        (.view == null)
                        or
                        (.view.projectId != $project)
                        or
                        (.view.datasetId != $dataset)
                        or
                        (
                            .view.tableId != $view_a
                            and
                            .view.tableId != $view_b
                        )
                    )
                ]

                +

                [
                    {
                        "view": {
                            "projectId": $project,
                            "datasetId": $dataset,
                            "tableId": $view_a
                        }
                    },

                    {
                        "view": {
                            "projectId": $project,
                            "datasetId": $dataset,
                            "tableId": $view_b
                        }
                    }
                ]
            )
        }
        ' \
        "$source_json" \
        > "$update_json"

    # --------------------------------------------------------
    # UPDATE DATASET ACCESS
    # --------------------------------------------------------

    timeout 60s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        update \
        --source="$update_json" \
        "$CURRENT_PROJECT:$PARTNER_DATASET" \
        >/dev/null

    ok "${VIEW_A} authorized."
    ok "${VIEW_B} authorized."

    echo
    ok "TASK 2 COMPLETED"
}

# ============================================================
# TASK 3
#
# Customer A -> authorized_view_a
# Customer B -> authorized_view_b
# ============================================================

task3() {
    step "[3/4] TASK 3 - GRANT USERS ACCESS TO VIEWS"

    # ========================================================
    # CUSTOMER A
    # ========================================================

    echo "${WHITE}${BOLD}Customer A${RESET}"
    echo "${WHITE}User : ${CYAN}${BOLD}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}View : ${GREEN}${VIEW_A}${RESET}"

    echo
    info "Granting BigQuery Data Viewer to Customer A..."

    timeout 60s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        add-iam-policy-binding \
        --table=true \
        --member="user:${CUSTOMER_A_USER}" \
        --role="roles/bigquery.dataViewer" \
        "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_A}" \
        >/dev/null

    ok "Customer A → ${VIEW_A}"

    # ========================================================
    # CUSTOMER B
    # ========================================================

    echo
    echo "${WHITE}${BOLD}Customer B${RESET}"
    echo "${WHITE}User : ${MAGENTA}${BOLD}${CUSTOMER_B_USER}${RESET}"
    echo "${WHITE}View : ${GREEN}${VIEW_B}${RESET}"

    echo
    info "Granting BigQuery Data Viewer to Customer B..."

    timeout 60s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        add-iam-policy-binding \
        --table=true \
        --member="user:${CUSTOMER_B_USER}" \
        --role="roles/bigquery.dataViewer" \
        "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_B}" \
        >/dev/null

    ok "Customer B → ${VIEW_B}"

    echo
    ok "TASK 3 COMPLETED"
}

# ============================================================
# VERIFY TASKS 1 - 3
# ============================================================

verify_partner() {
    step "VERIFY TASKS 1 - 3"

    # --------------------------------------------------------
    # VIEW A
    # --------------------------------------------------------

    info "Checking ${VIEW_A}..."

    timeout 20s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_A}" \
        >/dev/null

    ok "${VIEW_A} exists."

    # --------------------------------------------------------
    # VIEW B
    # --------------------------------------------------------

    info "Checking ${VIEW_B}..."

    timeout 20s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_B}" \
        >/dev/null

    ok "${VIEW_B} exists."

    # --------------------------------------------------------
    # AUTHORIZED VIEW ACL
    # --------------------------------------------------------

    info "Checking Authorized View ACL..."

    local count

    count="$(
        timeout 20s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            show \
            --format=prettyjson \
            "$CURRENT_PROJECT:$PARTNER_DATASET" |
        jq \
            --arg project "$CURRENT_PROJECT" \
            --arg dataset "$PARTNER_DATASET" \
            --arg view_a "$VIEW_A" \
            --arg view_b "$VIEW_B" \
            '
            [
                .access[]?
                |
                select(
                    .view.projectId == $project
                    and
                    .view.datasetId == $dataset
                    and
                    (
                        .view.tableId == $view_a
                        or
                        .view.tableId == $view_b
                    )
                )
            ]
            |
            length
            '
    )"

    if [[ "$count" -lt 2 ]]; then
        fail "Authorized View ACL is incomplete."
    fi

    ok "Both Authorized Views verified."

    # --------------------------------------------------------
    # VERIFY CUSTOMER A IAM
    # --------------------------------------------------------

    info "Checking Customer A permission on ${VIEW_A}..."

    local policy_a

    policy_a="$(
        timeout 20s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            get-iam-policy \
            --table=true \
            "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_A}"
    )"

    if ! jq -e \
        --arg member "user:${CUSTOMER_A_USER}" \
        '
        any(
            .bindings[]?;
            .role == "roles/bigquery.dataViewer"
            and
            any(.members[]?; . == $member)
        )
        ' \
        <<< "$policy_a" \
        >/dev/null 2>&1; then

        fail "Customer A IAM binding was not found."
    fi

    ok "Customer A permission verified."

    # --------------------------------------------------------
    # VERIFY CUSTOMER B IAM
    # --------------------------------------------------------

    info "Checking Customer B permission on ${VIEW_B}..."

    local policy_b

    policy_b="$(
        timeout 20s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            get-iam-policy \
            --table=true \
            "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_B}"
    )"

    if ! jq -e \
        --arg member "user:${CUSTOMER_B_USER}" \
        '
        any(
            .bindings[]?;
            .role == "roles/bigquery.dataViewer"
            and
            any(.members[]?; . == $member)
        )
        ' \
        <<< "$policy_b" \
        >/dev/null 2>&1; then

        fail "Customer B IAM binding was not found."
    fi

    ok "Customer B permission verified."

    # --------------------------------------------------------
    # PARTNER COMPLETE - TASK 4 STILL PENDING
    # --------------------------------------------------------

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                PARTNER SECTION COMPLETE                      ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 1 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 2 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 3 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${YELLOW}${BOLD}║                   TASK 4 - PENDING                          ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Check my progress: Task 1${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Task 2${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Task 3${RESET}"

    echo
    echo "${BLUE}${BOLD}==============================================================${RESET}"
    echo "${YELLOW}${BOLD}NEXT REQUIRED STEP - TASK 4${RESET}"
    echo "${BLUE}${BOLD}==============================================================${RESET}"

    echo
    echo "${WHITE}1. Open ${CYAN}${BOLD}Customer Project A Console${RESET}"
    echo "${WHITE}2. Run ${GREEN}${BOLD}source lab.sh${RESET}"
    echo "${WHITE}3. Complete Customer A section"
    echo "${WHITE}4. Open ${MAGENTA}${BOLD}Customer Project B Console${RESET}"
    echo "${WHITE}5. Run ${GREEN}${BOLD}source lab.sh${RESET}"
    echo "${WHITE}6. Then click Check my progress for Task 4${RESET}"

    echo
    echo "${BLUE}${BOLD}==============================================================${RESET}"
    echo "${WHITE}${BOLD}PARTNER PROJECT ID - COPY THIS:${RESET}"
    echo
    echo "${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo
    echo "${BLUE}${BOLD}==============================================================${RESET}"
}

# ============================================================
# RUN PARTNER
# ============================================================

run_partner() {
    echo
    echo "${GREEN}${BOLD}MODE: DATA SHARING PARTNER${RESET}"

    task1
    task2
    task3
    verify_partner
}

# ============================================================
# EXPECT ACCESS DENIED
#
# Do not treat every error as success.
# Only permission/access errors are accepted.
# ============================================================

expect_access_denied() {
    local project="$1"
    local location="$2"
    local sql="$3"
    local description="$4"

    local error_log

    error_log="$(mktemp)"
    TMP_FILES+=("$error_log")

    if timeout 60s \
        bq \
            --project_id="$project" \
            --quiet \
            query \
            --location="$location" \
            --use_legacy_sql=false \
            "$sql" \
            >"$error_log" 2>&1
    then
        fail "${description}: query unexpectedly succeeded."
    fi

    if grep -Eqi \
        'Access Denied|Permission denied|does not have permission|PERMISSION_DENIED' \
        "$error_log"; then

        ok "Access Denied received as expected."
        return 0
    fi

    echo
    warn "Query failed, but NOT because of Access Denied."
    echo
    cat "$error_log"
    echo

    fail "${description}: unexpected error."
}

# ============================================================
# TASK 4 - CUSTOMER A
#
# EXACT LAB FLOW:
#
# 1. Query authorized_view_a
# 2. Save as customer_a_table
# 3. JOIN customer_info + authorized_view_a
# 4. Query authorized_view_b -> Access Denied
# ============================================================

run_customer_a() {
    step "[4/4] TASK 4 - CUSTOMER A"

    local location

    location="$(
        get_location \
            "$CURRENT_PROJECT" \
            "$CUSTOMER_A_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset          : ${CYAN}${CUSTOMER_A_DATASET}${RESET}"
    echo "${WHITE}Save View As     : ${GREEN}${CUSTOMER_A_TABLE}${RESET}"

    # ========================================================
    # CUSTOMER A - STEP 3
    #
    # SELECT * FROM Partner.demo_dataset.authorized_view_a
    # ========================================================

    echo
    info "[A-1/4] Query authorized_view_a..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=10 \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        "

    ok "Customer A can query ${VIEW_A}."

    # ========================================================
    # CUSTOMER A - STEPS 4-7
    #
    # SAVE > SAVE VIEW
    #
    # Dataset = customer_a_dataset
    # Table   = customer_a_table
    # ========================================================

    echo
    info "[A-2/4] Saving view as ${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CURRENT_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}\`
        AS

        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        "

    ok "${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE} created."

    info "Verifying ${CUSTOMER_A_TABLE}..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}" \
        >/dev/null

    ok "${CUSTOMER_A_TABLE} verified."

    # ========================================================
    # CUSTOMER A - STEP 8
    #
    # EXACT JOIN FROM LAB
    # ========================================================

    echo
    info "[A-3/4] Running Customer A JOIN query..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=20 \
        "
        SELECT
            geos.zip_code,
            geos.city,
            cust.last_name,
            cust.first_name
        FROM
            \`${CURRENT_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_INFO_TABLE}\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\` AS geos
        ON
            geos.zip_code = cust.postal_code;
        "

    ok "Customer A JOIN query completed."

    # ========================================================
    # CUSTOMER A - STEP 9
    #
    # authorized_view_b MUST FAIL WITH ACCESS DENIED
    # ========================================================

    echo
    info "[A-4/4] Confirming Customer A cannot access ${VIEW_B}..."

    expect_access_denied \
        "$CURRENT_PROJECT" \
        "$location" \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        " \
        "Customer A access check"

    ok "Customer A can access only ${VIEW_A}."

    # ========================================================
    # CUSTOMER A COMPLETE
    # TASK 4 IS NOT COMPLETE UNTIL CUSTOMER B IS ALSO DONE
    # ========================================================

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                  CUSTOMER A COMPLETE ✓                       ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${YELLOW}${BOLD}║                    TASK 4 STILL PENDING                      ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}NEXT REQUIRED STEP:${RESET}"
    echo
    echo "${WHITE}1. Close Customer A Console.${RESET}"
    echo "${WHITE}2. Open ${MAGENTA}${BOLD}Customer Project B Console${RESET}"
    echo "${WHITE}3. Run:${RESET}"
    echo
    echo "   ${GREEN}${BOLD}source lab.sh${RESET}"
    echo
    echo "${WHITE}Do NOT click Task 4 complete yet.${RESET}"
}

# ============================================================
# TASK 4 - CUSTOMER B
#
# EXACT LAB FLOW:
#
# 1. Query authorized_view_b
# 2. Save as customer_b_table
# 3. JOIN customer_info + authorized_view_b
# 4. Query authorized_view_a -> Access Denied
# ============================================================

run_customer_b() {
    step "[4/4] TASK 4 - CUSTOMER B"

    local location

    location="$(
        get_location \
            "$CURRENT_PROJECT" \
            "$CUSTOMER_B_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset          : ${CYAN}${CUSTOMER_B_DATASET}${RESET}"
    echo "${WHITE}Save View As     : ${GREEN}${CUSTOMER_B_TABLE}${RESET}"

    # ========================================================
    # CUSTOMER B - STEP 3
    #
    # SELECT * FROM Partner.demo_dataset.authorized_view_b
    # ========================================================

    echo
    info "[B-1/4] Query authorized_view_b..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=10 \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        "

    ok "Customer B can query ${VIEW_B}."

    # ========================================================
    # CUSTOMER B - STEPS 4-7
    #
    # SAVE > SAVE VIEW
    #
    # Dataset = customer_b_dataset
    # Table   = customer_b_table
    # ========================================================

    echo
    info "[B-2/4] Saving view as ${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CURRENT_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}\`
        AS

        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        "

    ok "${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE} created."

    info "Verifying ${CUSTOMER_B_TABLE}..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}" \
        >/dev/null

    ok "${CUSTOMER_B_TABLE} verified."

    # ========================================================
    # CUSTOMER B - STEP 8
    #
    # EXACT JOIN FROM LAB
    # ========================================================

    echo
    info "[B-3/4] Running Customer B JOIN query..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=20 \
        "
        SELECT
            geos.zip_code,
            geos.city,
            cust.last_name,
            cust.first_name
        FROM
            \`${CURRENT_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_INFO_TABLE}\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\` AS geos
        ON
            geos.zip_code = cust.postal_code;
        "

    ok "Customer B JOIN query completed."

    # ========================================================
    # CUSTOMER B - STEP 9
    #
    # authorized_view_a MUST FAIL WITH ACCESS DENIED
    # ========================================================

    echo
    info "[B-4/4] Confirming Customer B cannot access ${VIEW_A}..."

    expect_access_denied \
        "$CURRENT_PROJECT" \
        "$location" \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        " \
        "Customer B access check"

    ok "Customer B can access only ${VIEW_B}."

    # ========================================================
    # TASK 4 COMPLETE
    # ========================================================

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                  CUSTOMER B COMPLETE ✓                       ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 4 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                    LAB COMPLETE                              ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Click Check my progress: Task 4${RESET}"
}

# ============================================================
# MAIN
# ============================================================

main() {
    banner

    # ========================================================
    # IMMEDIATE INPUT
    # ========================================================

    ask_users

    # ========================================================
    # LOCAL COMMAND CHECK
    # ========================================================

    require_cmd gcloud
    require_cmd bq
    require_cmd jq
    require_cmd timeout
    require_cmd grep

    # ========================================================
    # DETECT ENVIRONMENT
    # ========================================================

    detect_current_project
    detect_current_account

    echo
    echo "${BLUE}--------------------------------------------------------------${RESET}"
    echo "${WHITE}${BOLD}GOOGLE CLOUD ENVIRONMENT${RESET}"
    echo "${BLUE}--------------------------------------------------------------${RESET}"
    echo "${WHITE}Account : ${CYAN}${BOLD}${CURRENT_ACCOUNT}${RESET}"
    echo "${WHITE}Project : ${GREEN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${BLUE}--------------------------------------------------------------${RESET}"

    # ========================================================
    # DETECT LAB ROLE
    # ========================================================

    detect_project_role

    if [[ "$PROJECT_ROLE" == "UNKNOWN" ]]; then
        ask_project_role
    fi

    # ========================================================
    # EXECUTE CORRECT SECTION
    # ========================================================

    case "$PROJECT_ROLE" in

        PARTNER)

            PARTNER_PROJECT="$CURRENT_PROJECT"

            run_partner
            ;;

        CUSTOMER_A)

            echo
            echo "${GREEN}${BOLD}MODE: CUSTOMER A${RESET}"

            ask_partner_project

            run_customer_a
            ;;

        CUSTOMER_B)

            echo
            echo "${GREEN}${BOLD}MODE: CUSTOMER B${RESET}"

            ask_partner_project

            run_customer_b
            ;;

        *)

            fail "Unknown lab project type."
            ;;
    esac

    echo
    echo "${CYAN}${BOLD}==============================================================${RESET}"
    echo "${CYAN}${BOLD}                       © ePlus.DEV                            ${RESET}"
    echo "${CYAN}${BOLD}==============================================================${RESET}"
}

main "$@"

)