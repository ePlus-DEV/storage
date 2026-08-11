#!/bin/bash

# ============================================================
# BigQuery Authorized Views Challenge Lab
# ONE TERMINAL - ONE SOURCE - TASK 1 → TASK 4
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
# LAB CONSTANTS
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

PARTNER_ACCOUNT=""
PARTNER_PROJECT=""

CUSTOMER_A_PROJECT=""
CUSTOMER_B_PROJECT=""

ORIGINAL_ACCOUNT=""
ORIGINAL_PROJECT=""

TMP_FILES=()

# ============================================================
# UI
# ============================================================

banner() {
    echo
    echo "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║          BIGQUERY AUTHORIZED VIEWS CHALLENGE LAB             ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║                ONE TERMINAL • TASK 1 → 4                     ║${RESET}"
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
# REQUIRED COMMAND
# ============================================================

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || \
        fail "Required command not found: $1"
}

# ============================================================
# CLEANUP / RESTORE PARTNER ENVIRONMENT
# ============================================================

cleanup() {
    if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
        rm -f "${TMP_FILES[@]}" 2>/dev/null || true
    fi

    # Restore original active account.
    if [[ -n "$ORIGINAL_ACCOUNT" ]]; then
        gcloud config set account \
            "$ORIGINAL_ACCOUNT" \
            --quiet \
            >/dev/null 2>&1 || true
    fi

    # Restore original project.
    if [[ -n "$ORIGINAL_PROJECT" && "$ORIGINAL_PROJECT" != "(unset)" ]]; then
        gcloud config set project \
            "$ORIGINAL_PROJECT" \
            --quiet \
            >/dev/null 2>&1 || true
    fi

    printf "%s" "$RESET" 2>/dev/null || true
}

trap cleanup EXIT
trap 'exit 130' INT TERM

# ============================================================
# ASK CUSTOMER USERS
#
# THIS HAPPENS IMMEDIATELY.
# NO GOOGLE CLOUD NETWORK COMMAND BEFORE THESE INPUTS.
# ============================================================

ask_users() {
    step "ENTER CUSTOMER ACCOUNTS"

    echo "${WHITE}Enter Customer A and Customer B users from the lab panel.${RESET}"
    echo
    echo "${WHITE}Example:${RESET}"
    echo "${CYAN}student-02-xxxxxxxxxxxx@qwiklabs.net${RESET}"
    echo

    # --------------------------------------------------------
    # CUSTOMER A
    # --------------------------------------------------------

    while true; do

        colored_read \
            CUSTOMER_A_USER \
            "Customer A user"

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

        colored_read \
            CUSTOMER_B_USER \
            "Customer B user"

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
# CURRENT ACTIVE ACCOUNT
# ============================================================

current_account() {
    gcloud auth list \
        --filter=status:ACTIVE \
        --format='value(account)' \
        2>/dev/null |
    head -n1
}

# ============================================================
# CURRENT PROJECT
# ============================================================

current_project() {
    local project=""

    project="${DEVSHELL_PROJECT_ID:-}"

    if [[ -z "$project" ]]; then
        project="$(
            gcloud config get-value project \
                2>/dev/null || true
        )"
    fi

    if [[ "$project" == "(unset)" ]]; then
        project=""
    fi

    printf "%s" "$project"
}

# ============================================================
# DATASET EXISTS
# ============================================================

dataset_exists() {
    local project="$1"
    local dataset="$2"

    timeout 20s \
    bq \
        --quiet \
        --project_id="$project" \
        show \
        "$project:$dataset" \
        >/dev/null 2>&1
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
            --quiet \
            --project_id="$project" \
            show \
            --format=prettyjson \
            "$project:$dataset" \
            2>/dev/null |
        jq -r '.location // empty' \
        || true
    )"

    if [[ -z "$location" ]]; then
        location="US"
    fi

    printf "%s" "$location"
}

# ============================================================
# SWITCH ACTIVE ACCOUNT + PROJECT
# ============================================================

switch_context() {
    local account="$1"
    local project="$2"

    info "Switching active account to ${account}..."

    gcloud config set account \
        "$account" \
        --quiet \
        >/dev/null

    info "Switching project to ${project}..."

    gcloud config set project \
        "$project" \
        --quiet \
        >/dev/null

    local active=""

    active="$(current_account)"

    if [[ "$active" != "$account" ]]; then
        fail "Failed to activate account ${account}."
    fi

    ok "Active account : ${account}"
    ok "Active project : ${project}"
}

# ============================================================
# LOGIN CUSTOMER ACCOUNT
#
# If valid credentials already exist → reuse.
# Otherwise → OAuth browser login.
# ============================================================

ensure_user_login() {
    local account="$1"
    local label="$2"

    step "LOGIN - ${label}"

    # --------------------------------------------------------
    # Reuse existing credential when possible
    # --------------------------------------------------------

    if \
        gcloud auth list \
            --format='value(account)' \
            2>/dev/null |
        grep -Fxq "$account" \
        &&
        gcloud auth print-access-token \
            --account="$account" \
            >/dev/null 2>&1
    then

        ok "Stored credential is already valid."
        ok "$account"

    else

        echo "${WHITE}Google Cloud CLI needs authorization for:${RESET}"
        echo
        echo "${CYAN}${BOLD}${account}${RESET}"
        echo
        echo "${YELLOW}${BOLD}A Google login URL will appear below.${RESET}"
        echo
        echo "${WHITE}1. Open the URL in an Incognito/private window.${RESET}"
        echo "${WHITE}2. Login using ${CYAN}${account}${RESET}"
        echo "${WHITE}3. Use the temporary password from the lab panel.${RESET}"
        echo "${WHITE}4. Copy the authorization code.${RESET}"
        echo "${WHITE}5. Paste the code back into this terminal.${RESET}"
        echo

        # Do NOT put a timeout here.
        # User needs enough time to complete browser login.
        gcloud auth login \
        "$account" \
        --no-launch-browser \
        --force \
        --quiet

    fi

    # --------------------------------------------------------
    # Activate
    # --------------------------------------------------------

    gcloud config set account \
        "$account" \
        --quiet \
        >/dev/null

    local active=""

    active="$(current_account)"

    if [[ "$active" != "$account" ]]; then
        fail "Active account is ${active}; expected ${account}."
    fi

    echo
    ok "${label} login successful."
    ok "Active account: ${account}"
}

# ============================================================
# AUTO FIND PROJECT CONTAINING SPECIFIC DATASET
#
# If auto detection fails → ask user.
# ============================================================

find_project_with_dataset() {
    local account="$1"
    local dataset="$2"
    local result_variable="$3"
    local label="$4"

    local projects=""
    local project=""
    local found=""

    step "AUTO-DETECT ${label} PROJECT"

    info "Listing projects available to ${account}..."

    projects="$(
        timeout 30s \
        gcloud projects list \
            --account="$account" \
            --format='value(projectId)' \
            2>/dev/null \
        || true
    )"

    # --------------------------------------------------------
    # Search accessible projects
    # --------------------------------------------------------

    if [[ -n "$projects" ]]; then

        while IFS= read -r project; do

            [[ -n "$project" ]] || continue

            info "Checking ${project} for ${dataset}..."

            if dataset_exists "$project" "$dataset"; then

                found="$project"

                break
            fi

        done <<< "$projects"

    fi

    # --------------------------------------------------------
    # Manual fallback
    # --------------------------------------------------------

    if [[ -z "$found" ]]; then

        warn "Could not auto-detect ${label} project."

        echo
        echo "${WHITE}Enter the Project ID from the lab panel.${RESET}"
        echo

        while true; do

            colored_read \
                found \
                "${label} Project ID"

            echo

            if ! valid_project "$found"; then

                warn "Invalid Google Cloud Project ID."
                echo

                continue
            fi

            if dataset_exists "$found" "$dataset"; then
                break
            fi

            warn "Dataset ${dataset} was not found in ${found}."
            echo

        done

    fi

    printf -v "$result_variable" '%s' "$found"

    ok "${label} project: ${found}"
}

# ============================================================
# ACCESS DENIED CHECK
#
# Only permission errors count as expected.
# Other failures are treated as actual errors.
# ============================================================

expect_access_denied() {
    local project="$1"
    local location="$2"
    local sql="$3"
    local description="$4"

    local log=""

    log="$(mktemp)"
    TMP_FILES+=("$log")

    if timeout 60s \
        bq \
            --quiet \
            --project_id="$project" \
            query \
            --location="$location" \
            --use_legacy_sql=false \
            "$sql" \
            >"$log" 2>&1
    then

        fail "${description}: query unexpectedly succeeded."

    fi

    if grep -Eqi \
        'Access Denied|Permission denied|does not have permission|PERMISSION_DENIED' \
        "$log"
    then

        ok "Access Denied received as expected."

        return 0
    fi

    echo
    warn "Query failed, but it was not an Access Denied error."
    echo

    cat "$log"

    echo

    fail "${description}: unexpected query failure."
}

# ============================================================
# TASK 1
# CREATE AUTHORIZED VIEW A + B
# ============================================================

task1() {
    step "[1/4] TASK 1 - CREATE AUTHORIZED VIEWS"

    local location=""

    location="$(
        get_location \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    )"

    echo "${WHITE}Partner Project : ${CYAN}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset         : ${CYAN}${PARTNER_DATASET}${RESET}"
    echo "${WHITE}Location        : ${CYAN}${location}${RESET}"

    # ========================================================
    # VIEW A - TEXAS
    # ========================================================

    echo
    info "Creating ${VIEW_A} - Texas..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        AS

        SELECT *
        FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`
        WHERE state_code = 'TX'
        LIMIT 4000
        "

    ok "${VIEW_A} created."

    # ========================================================
    # VIEW B - CALIFORNIA
    # ========================================================

    echo
    info "Creating ${VIEW_B} - California..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
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

    local source_json=""
    local update_json=""

    source_json="$(mktemp)"
    update_json="$(mktemp)"

    TMP_FILES+=(
        "$source_json"
        "$update_json"
    )

    # --------------------------------------------------------
    # Read dataset metadata
    # --------------------------------------------------------

    info "Reading ${PARTNER_DATASET} access list..."

    timeout 30s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        show \
        --format=prettyjson \
        "$PARTNER_PROJECT:$PARTNER_DATASET" \
        > "$source_json"

    # --------------------------------------------------------
    # Preserve existing ACL
    # Remove duplicate View A / View B
    # Add correct Authorized View entries
    # --------------------------------------------------------

    info "Adding ${VIEW_A} and ${VIEW_B} to Authorized Views..."

    jq \
        --arg project "$PARTNER_PROJECT" \
        --arg dataset "$PARTNER_DATASET" \
        --arg view_a "$VIEW_A" \
        --arg view_b "$VIEW_B" \
        '
        .access = (
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
                        (.view.tableId != $view_a)
                        and
                        (.view.tableId != $view_b)
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
        ' \
        "$source_json" \
        > "$update_json"

    # --------------------------------------------------------
    # Update
    # --------------------------------------------------------

    timeout 60s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        update \
        --source="$update_json" \
        "$PARTNER_PROJECT:$PARTNER_DATASET" \
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
    step "[3/4] TASK 3 - GRANT VIEW PERMISSIONS"

    # ========================================================
    # CUSTOMER A
    # ========================================================

    echo "${WHITE}${BOLD}Customer A${RESET}"
    echo "${WHITE}User : ${CYAN}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}View : ${GREEN}${VIEW_A}${RESET}"

    echo
    info "Granting BigQuery Data Viewer..."

    timeout 60s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        add-iam-policy-binding \
        --table=true \
        --member="user:${CUSTOMER_A_USER}" \
        --role="roles/bigquery.dataViewer" \
        "${PARTNER_PROJECT}:${PARTNER_DATASET}.${VIEW_A}" \
        >/dev/null

    ok "Customer A → ${VIEW_A}"

    # ========================================================
    # CUSTOMER B
    # ========================================================

    echo
    echo "${WHITE}${BOLD}Customer B${RESET}"
    echo "${WHITE}User : ${MAGENTA}${CUSTOMER_B_USER}${RESET}"
    echo "${WHITE}View : ${GREEN}${VIEW_B}${RESET}"

    echo
    info "Granting BigQuery Data Viewer..."

    timeout 60s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        add-iam-policy-binding \
        --table=true \
        --member="user:${CUSTOMER_B_USER}" \
        --role="roles/bigquery.dataViewer" \
        "${PARTNER_PROJECT}:${PARTNER_DATASET}.${VIEW_B}" \
        >/dev/null

    ok "Customer B → ${VIEW_B}"

    echo
    ok "TASK 3 COMPLETED"
}

# ============================================================
# VERIFY TASK 1 - 3
# ============================================================

verify_partner() {
    step "VERIFY TASKS 1 - 3"

    # --------------------------------------------------------
    # View A exists
    # --------------------------------------------------------

    info "Checking ${VIEW_A}..."

    timeout 20s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        show \
        "${PARTNER_PROJECT}:${PARTNER_DATASET}.${VIEW_A}" \
        >/dev/null

    ok "${VIEW_A} exists."

    # --------------------------------------------------------
    # View B exists
    # --------------------------------------------------------

    info "Checking ${VIEW_B}..."

    timeout 20s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        show \
        "${PARTNER_PROJECT}:${PARTNER_DATASET}.${VIEW_B}" \
        >/dev/null

    ok "${VIEW_B} exists."

    # --------------------------------------------------------
    # Authorized View ACL
    # --------------------------------------------------------

    info "Checking Authorized View ACL..."

    local count=""

    count="$(
        timeout 20s \
        bq \
            --quiet \
            --project_id="$PARTNER_PROJECT" \
            show \
            --format=prettyjson \
            "$PARTNER_PROJECT:$PARTNER_DATASET" |
        jq \
            --arg project "$PARTNER_PROJECT" \
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

    ok "Authorized View A verified."
    ok "Authorized View B verified."

    echo
    echo "${GREEN}${BOLD}✓ TASK 1 COMPLETE${RESET}"
    echo "${GREEN}${BOLD}✓ TASK 2 COMPLETE${RESET}"
    echo "${GREEN}${BOLD}✓ TASK 3 COMPLETE${RESET}"
    echo
    echo "${YELLOW}${BOLD}→ Continuing automatically to Task 4...${RESET}"
}

# ============================================================
# TASK 4 - CUSTOMER A
#
# EXACT FLOW:
#
# A-1 SELECT authorized_view_a
# A-2 Save View → customer_a_table
# A-3 JOIN customer_info + authorized_view_a
# A-4 authorized_view_b → Access Denied
# ============================================================

run_customer_a() {
    step "[4/4] TASK 4 - CUSTOMER A"

    local location=""

    location="$(
        get_location \
            "$CUSTOMER_A_PROJECT" \
            "$CUSTOMER_A_DATASET"
    )"

    echo "${WHITE}Account          : ${CYAN}${BOLD}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}Customer Project : ${CYAN}${CUSTOMER_A_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset          : ${CYAN}${CUSTOMER_A_DATASET}${RESET}"

    # ========================================================
    # A-1
    # SELECT authorized_view_a
    # ========================================================

    echo
    info "[A-1/4] Query authorized_view_a..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_A_PROJECT" \
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
    # A-2
    # SAVE VIEW → customer_a_table
    # ========================================================

    echo
    info "[A-2/4] Save View → ${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_A_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CUSTOMER_A_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}\`
        AS

        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        "

    timeout 30s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_A_PROJECT" \
        show \
        "${CUSTOMER_A_PROJECT}:${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}" \
        >/dev/null

    ok "${CUSTOMER_A_TABLE} created and verified."

    # ========================================================
    # A-3
    # JOIN EXACTLY AS LAB
    # ========================================================

    echo
    info "[A-3/4] JOIN customer_info + authorized_view_a..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_A_PROJECT" \
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
            \`${CUSTOMER_A_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_INFO_TABLE}\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\` AS geos
        ON
            geos.zip_code = cust.postal_code;
        "

    ok "Customer A JOIN completed."

    # ========================================================
    # A-4
    # authorized_view_b MUST BE DENIED
    # ========================================================

    echo
    info "[A-4/4] Verify authorized_view_b is NOT accessible..."

    expect_access_denied \
        "$CUSTOMER_A_PROJECT" \
        "$location" \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        " \
        "Customer A permission check"

    ok "Customer A can only access ${VIEW_A}."

    echo
    echo "${GREEN}${BOLD}✓ CUSTOMER A SECTION OF TASK 4 COMPLETE${RESET}"
}

# ============================================================
# TASK 4 - CUSTOMER B
#
# EXACT FLOW:
#
# B-1 SELECT authorized_view_b
# B-2 Save View → customer_b_table
# B-3 JOIN customer_info + authorized_view_b
# B-4 authorized_view_a → Access Denied
# ============================================================

run_customer_b() {
    step "[4/4] TASK 4 - CUSTOMER B"

    local location=""

    location="$(
        get_location \
            "$CUSTOMER_B_PROJECT" \
            "$CUSTOMER_B_DATASET"
    )"

    echo "${WHITE}Account          : ${MAGENTA}${BOLD}${CUSTOMER_B_USER}${RESET}"
    echo "${WHITE}Customer Project : ${CYAN}${CUSTOMER_B_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset          : ${CYAN}${CUSTOMER_B_DATASET}${RESET}"

    # ========================================================
    # B-1
    # SELECT authorized_view_b
    # ========================================================

    echo
    info "[B-1/4] Query authorized_view_b..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_B_PROJECT" \
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
    # B-2
    # SAVE VIEW → customer_b_table
    # ========================================================

    echo
    info "[B-2/4] Save View → ${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_B_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CUSTOMER_B_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}\`
        AS

        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        "

    timeout 30s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_B_PROJECT" \
        show \
        "${CUSTOMER_B_PROJECT}:${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}" \
        >/dev/null

    ok "${CUSTOMER_B_TABLE} created and verified."

    # ========================================================
    # B-3
    # JOIN EXACTLY AS LAB
    # ========================================================

    echo
    info "[B-3/4] JOIN customer_info + authorized_view_b..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_B_PROJECT" \
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
            \`${CUSTOMER_B_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_INFO_TABLE}\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\` AS geos
        ON
            geos.zip_code = cust.postal_code;
        "

    ok "Customer B JOIN completed."

    # ========================================================
    # B-4
    # authorized_view_a MUST BE DENIED
    # ========================================================

    echo
    info "[B-4/4] Verify authorized_view_a is NOT accessible..."

    expect_access_denied \
        "$CUSTOMER_B_PROJECT" \
        "$location" \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        " \
        "Customer B permission check"

    ok "Customer B can only access ${VIEW_B}."

    echo
    echo "${GREEN}${BOLD}✓ CUSTOMER B SECTION OF TASK 4 COMPLETE${RESET}"
    echo "${GREEN}${BOLD}✓ TASK 4 COMPLETE${RESET}"
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
    # LOCAL TOOLS
    # ========================================================

    require_cmd gcloud
    require_cmd bq
    require_cmd jq
    require_cmd timeout
    require_cmd grep

    # ========================================================
    # SAVE ORIGINAL PARTNER ENVIRONMENT
    # ========================================================

    ORIGINAL_ACCOUNT="$(current_account)"
    ORIGINAL_PROJECT="$(current_project)"

    if [[ -z "$ORIGINAL_ACCOUNT" ]]; then
        fail "No active Partner account was detected."
    fi

    PARTNER_ACCOUNT="$ORIGINAL_ACCOUNT"
    PARTNER_PROJECT="$ORIGINAL_PROJECT"

    step "DATA SHARING PARTNER ENVIRONMENT"

    echo "${WHITE}Partner account : ${CYAN}${BOLD}${PARTNER_ACCOUNT}${RESET}"
    echo "${WHITE}Partner project : ${GREEN}${BOLD}${PARTNER_PROJECT:-not detected}${RESET}"

    # ========================================================
    # AUTO FIND PARTNER PROJECT IF NEEDED
    # ========================================================

    if \
        [[ -z "$PARTNER_PROJECT" ]] \
        ||
        ! dataset_exists "$PARTNER_PROJECT" "$PARTNER_DATASET"
    then

        find_project_with_dataset \
            "$PARTNER_ACCOUNT" \
            "$PARTNER_DATASET" \
            PARTNER_PROJECT \
            "Partner"
    fi

    # ========================================================
    # PARTNER CONTEXT
    # ========================================================

    switch_context \
        "$PARTNER_ACCOUNT" \
        "$PARTNER_PROJECT"

    # ========================================================
    # TASK 1 - 3
    # ========================================================

    task1
    task2
    task3
    verify_partner

    # ========================================================
    # CUSTOMER A LOGIN IN SAME TERMINAL
    # ========================================================

    ensure_user_login \
        "$CUSTOMER_A_USER" \
        "CUSTOMER A"

    # ========================================================
    # AUTO FIND CUSTOMER A PROJECT
    # ========================================================

    find_project_with_dataset \
        "$CUSTOMER_A_USER" \
        "$CUSTOMER_A_DATASET" \
        CUSTOMER_A_PROJECT \
        "Customer A"

    # ========================================================
    # CUSTOMER A CONTEXT
    # ========================================================

    switch_context \
        "$CUSTOMER_A_USER" \
        "$CUSTOMER_A_PROJECT"

    # ========================================================
    # TASK 4 - CUSTOMER A
    # ========================================================

    run_customer_a

    # ========================================================
    # CUSTOMER B LOGIN IN SAME TERMINAL
    # ========================================================

    ensure_user_login \
        "$CUSTOMER_B_USER" \
        "CUSTOMER B"

    # ========================================================
    # AUTO FIND CUSTOMER B PROJECT
    # ========================================================

    find_project_with_dataset \
        "$CUSTOMER_B_USER" \
        "$CUSTOMER_B_DATASET" \
        CUSTOMER_B_PROJECT \
        "Customer B"

    # ========================================================
    # CUSTOMER B CONTEXT
    # ========================================================

    switch_context \
        "$CUSTOMER_B_USER" \
        "$CUSTOMER_B_PROJECT"

    # ========================================================
    # TASK 4 - CUSTOMER B
    # ========================================================

    run_customer_b

    # ========================================================
    # FINAL
    # ========================================================

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                    ALL TASKS COMPLETE                        ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 1 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 2 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 3 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 4 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                      © ePlus.DEV                             ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Click Check my progress for Task 1${RESET}"
    echo "${YELLOW}${BOLD}→ Click Check my progress for Task 2${RESET}"
    echo "${YELLOW}${BOLD}→ Click Check my progress for Task 3${RESET}"
    echo "${YELLOW}${BOLD}→ Click Check my progress for Task 4${RESET}"

    echo
    echo "${CYAN}${BOLD}Partner account/project will now be restored automatically.${RESET}"
}

main "$@"

)