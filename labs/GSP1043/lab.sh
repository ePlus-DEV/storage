#!/bin/bash

# ============================================================
# BigQuery Data Twin - Authorized Views Lab
# CHECK PROGRESS TASKS ONLY
#
# ONE TERMINAL • ONE SOURCE • TASK 1 → TASK 3
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
# NO PROJECT ID / USERNAME HARD-CODED
# ============================================================

PARTNER_DATASET="demo_dataset"
AUTHORIZED_TABLE="authorized_table"

PUBLISHER_DATASET="data_publisher_dataset"
AUTHORIZED_VIEW="authorized_view"

CUSTOMER_DATASET="customer_dataset"
CUSTOMER_INFO="customer_info"
CUSTOMER_TABLE="customer_table"

# ============================================================
# VARIABLES
# ============================================================

DATA_PUBLISHER_USER=""
CUSTOMER_USER=""

PARTNER_ACCOUNT=""
PARTNER_PROJECT=""

PUBLISHER_PROJECT=""
CUSTOMER_PROJECT=""

ORIGINAL_ACCOUNT=""
ORIGINAL_PROJECT=""

TMP_FILES=()

# ============================================================
# CLEANUP
# ============================================================

cleanup() {

    if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
        rm -f "${TMP_FILES[@]}" 2>/dev/null || true
    fi

    # Restore original Partner account
    if [[ -n "${ORIGINAL_ACCOUNT:-}" ]]; then
        gcloud config set account \
            "$ORIGINAL_ACCOUNT" \
            --quiet \
            >/dev/null 2>&1 || true
    fi

    # Restore original Partner project
    if [[ -n "${ORIGINAL_PROJECT:-}" && "$ORIGINAL_PROJECT" != "(unset)" ]]; then
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
# UI
# ============================================================

banner() {

    echo
    echo "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║              BIGQUERY DATA TWIN CHALLENGE LAB                ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║                CHECK PROGRESS TASKS ONLY                     ║${RESET}"
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

require_cmd() {

    command -v "$1" >/dev/null 2>&1 || \
        fail "Required command not found: $1"
}

# ============================================================
# ASK USERS IMMEDIATELY
#
# NO NETWORK CALL BEFORE THIS
# ============================================================

ask_users() {

    step "ENTER LAB ACCOUNTS"

    echo "${WHITE}Copy the usernames from the Lab setup panel.${RESET}"
    echo
    echo "${WHITE}Example:${RESET}"
    echo "${CYAN}student-04-xxxxxxxxxxxx@qwiklabs.net${RESET}"
    echo

    # --------------------------------------------------------
    # Data Publisher
    # --------------------------------------------------------

    while true; do

        colored_read \
            DATA_PUBLISHER_USER \
            "Data Publisher user"

        echo

        if valid_email "$DATA_PUBLISHER_USER"; then
            break
        fi

        warn "Invalid Data Publisher email."
        echo
    done

    echo

    # --------------------------------------------------------
    # Customer
    # --------------------------------------------------------

    while true; do

        colored_read \
            CUSTOMER_USER \
            "Customer user"

        echo

        if valid_email "$CUSTOMER_USER"; then
            break
        fi

        warn "Invalid Customer email."
        echo
    done

    echo
    echo "${BLUE}--------------------------------------------------------------${RESET}"
    echo "${WHITE}${BOLD}INPUT SUMMARY${RESET}"
    echo "${BLUE}--------------------------------------------------------------${RESET}"

    echo "${WHITE}Data Publisher : ${CYAN}${BOLD}${DATA_PUBLISHER_USER}${RESET}"
    echo "${WHITE}Customer       : ${MAGENTA}${BOLD}${CUSTOMER_USER}${RESET}"

    echo "${BLUE}--------------------------------------------------------------${RESET}"
}

# ============================================================
# GCLOUD HELPERS
# ============================================================

get_active_account() {

    gcloud auth list \
        --filter=status:ACTIVE \
        --format='value(account)' \
        2>/dev/null |
    head -n1
}

get_config_project() {

    local project=""

    project="$(
        gcloud config get-value project \
            2>/dev/null || true
    )"

    if [[ "$project" == "(unset)" ]]; then
        project=""
    fi

    printf "%s" "$project"
}

# ============================================================
# BIGQUERY HELPERS
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

table_exists() {

    local project="$1"
    local dataset="$2"
    local table="$3"

    timeout 20s \
    bq \
        --quiet \
        --project_id="$project" \
        show \
        "$project:$dataset.$table" \
        >/dev/null 2>&1
}

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
# SWITCH ACCOUNT + PROJECT
# ============================================================

switch_context() {

    local account="$1"
    local project="$2"

    info "Activating account: ${account}"

    gcloud config set account \
        "$account" \
        --quiet \
        >/dev/null

    info "Setting project: ${project}"

    gcloud config set project \
        "$project" \
        --quiet \
        >/dev/null

    ok "Account : ${account}"
    ok "Project : ${project}"
}

# ============================================================
# LOGIN USER IN SAME TERMINAL
# ============================================================

ensure_login() {

    local account="$1"
    local label="$2"

    step "LOGIN - ${label}"

    # --------------------------------------------------------
    # Reuse credential if already available
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

        ok "Existing credential found."
        ok "${account}"

    else

        echo "${WHITE}Authorization is required for:${RESET}"
        echo
        echo "${CYAN}${BOLD}${account}${RESET}"
        echo
        echo "${YELLOW}${BOLD}A Google login URL will appear below.${RESET}"
        echo
        echo "${WHITE}1. Open the URL in an Incognito window.${RESET}"
        echo "${WHITE}2. Login with ${CYAN}${account}${RESET}"
        echo "${WHITE}3. Use the temporary lab password.${RESET}"
        echo "${WHITE}4. Copy the authorization code.${RESET}"
        echo "${WHITE}5. Paste the code back here.${RESET}"
        echo

        # No timeout because the user needs time to login.
        gcloud auth login \
            "$account" \
            --no-launch-browser \
            --force \
            --quiet
    fi

    gcloud config set account \
        "$account" \
        --quiet \
        >/dev/null

    if [[ "$(get_active_account)" != "$account" ]]; then
        fail "Unable to activate ${account}."
    fi

    echo
    ok "${label} authenticated."
}

# ============================================================
# FIND PROJECT BY DATASET
# ============================================================

find_project_with_dataset() {

    local account="$1"
    local dataset="$2"
    local result_variable="$3"
    local label="$4"

    local projects=""
    local project=""
    local found=""

    step "DETECT ${label} PROJECT"

    info "Searching accessible projects..."

    projects="$(
        timeout 30s \
        gcloud projects list \
            --account="$account" \
            --format='value(projectId)' \
        2>/dev/null || true
    )"

    if [[ -n "$projects" ]]; then

        while IFS= read -r project; do

            [[ -n "$project" ]] || continue

            info "Checking ${project}..."

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

        warn "Could not detect ${label} Project automatically."
        echo

        while true; do

            colored_read \
                found \
                "${label} Project ID"

            echo

            if ! valid_project "$found"; then
                warn "Invalid Project ID."
                echo
                continue
            fi

            if dataset_exists "$found" "$dataset"; then
                break
            fi

            warn "Dataset ${dataset} not found in ${found}."
            echo
        done
    fi

    printf -v "$result_variable" '%s' "$found"

    ok "${label} Project: ${found}"
}

# ============================================================
# AUTHORIZED DATASET
#
# Matches:
# Share → Authorize datasets
# ============================================================

authorize_dataset() {

    local shared_project="$1"
    local shared_dataset="$2"

    local authorized_project="$3"
    local authorized_dataset="$4"

    local before=""
    local after=""

    before="$(mktemp)"
    after="$(mktemp)"

    TMP_FILES+=("$before" "$after")

    info "Reading dataset access configuration..."

    bq \
        --quiet \
        --project_id="$shared_project" \
        show \
        --format=prettyjson \
        "$shared_project:$shared_dataset" \
        > "$before"

    info "Adding authorized dataset..."

    jq \
        --arg auth_project "$authorized_project" \
        --arg auth_dataset "$authorized_dataset" \
        '
        .access = (
            [
                (.access // [])[]

                |

                select(
                    (.dataset == null)

                    or

                    (
                        (
                            (
                                .dataset.dataset.project_id
                                //
                                .dataset.dataset.projectId
                                //
                                ""
                            )
                            != $auth_project
                        )

                        or

                        (
                            (
                                .dataset.dataset.dataset_id
                                //
                                .dataset.dataset.datasetId
                                //
                                ""
                            )
                            != $auth_dataset
                        )
                    )
                )
            ]

            +

            [
                {
                    "dataset": {
                        "dataset": {
                            "project_id": $auth_project,
                            "dataset_id": $auth_dataset
                        },
                        "target_types": "VIEWS"
                    }
                }
            ]
        )
        ' \
        "$before" \
        > "$after"

    bq \
        --quiet \
        --project_id="$shared_project" \
        update \
        --source="$after" \
        "$shared_project:$shared_dataset" \
        >/dev/null

    ok "Authorized dataset added."
}

# ============================================================
# AUTHORIZE VIEW
#
# Matches:
# Share → Authorize Views
# ============================================================

authorize_view() {

    local dataset_project="$1"
    local dataset_id="$2"

    local view_project="$3"
    local view_dataset="$4"
    local view_id="$5"

    local before=""
    local after=""

    before="$(mktemp)"
    after="$(mktemp)"

    TMP_FILES+=("$before" "$after")

    info "Reading dataset access configuration..."

    bq \
        --quiet \
        --project_id="$dataset_project" \
        show \
        --format=prettyjson \
        "$dataset_project:$dataset_id" \
        > "$before"

    info "Adding Authorized View..."

    jq \
        --arg view_project "$view_project" \
        --arg view_dataset "$view_dataset" \
        --arg view_id "$view_id" \
        '
        .access = (
            [
                (.access // [])[]

                |

                select(
                    (.view == null)

                    or

                    (.view.projectId != $view_project)

                    or

                    (.view.datasetId != $view_dataset)

                    or

                    (.view.tableId != $view_id)
                )
            ]

            +

            [
                {
                    "view": {
                        "projectId": $view_project,
                        "datasetId": $view_dataset,
                        "tableId": $view_id
                    }
                }
            ]
        )
        ' \
        "$before" \
        > "$after"

    bq \
        --quiet \
        --project_id="$dataset_project" \
        update \
        --source="$after" \
        "$dataset_project:$dataset_id" \
        >/dev/null

    ok "Authorized View added."
}

# ============================================================
# GRANT BIGQUERY DATA VIEWER TO TABLE / VIEW
# ============================================================

grant_data_viewer() {

    local project="$1"
    local dataset="$2"
    local resource="$3"
    local user="$4"

    bq \
        --quiet \
        --project_id="$project" \
        add-iam-policy-binding \
        --table=true \
        --member="user:${user}" \
        --role="roles/bigquery.dataViewer" \
        "${project}:${dataset}.${resource}" \
        >/dev/null
}

# ============================================================
# TASK 1
#
# CREATED AN AUTHORIZED TABLE
# ============================================================

task1() {

    step "[1/3] TASK 1 - CREATE AUTHORIZED TABLE"

    local location=""

    location="$(
        get_location \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    )"

    echo "${WHITE}Partner Project : ${CYAN}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset         : ${CYAN}${PARTNER_DATASET}${RESET}"
    echo "${WHITE}Table           : ${GREEN}${AUTHORIZED_TABLE}${RESET}"
    echo "${WHITE}Location        : ${CYAN}${location}${RESET}"

    # ========================================================
    # Create authorized_table
    # ========================================================

    echo
    info "Creating ${AUTHORIZED_TABLE}..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE TABLE
        \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${AUTHORIZED_TABLE}\`
        AS

        SELECT *
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY state_code
                    ORDER BY area_land_meters DESC
                ) AS cities_by_area
            FROM
                \`bigquery-public-data.geo_us_boundaries.zip_codes\`
        ) cities
        WHERE cities_by_area <= 10
        ORDER BY cities.state_code
        LIMIT 1000
        "

    if ! table_exists \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$AUTHORIZED_TABLE"
    then
        fail "${AUTHORIZED_TABLE} was not created."
    fi

    ok "${AUTHORIZED_TABLE} created."

    # ========================================================
    # Authorize dataset
    #
    # Exact resource requested by the lab:
    # PartnerProject.demo_dataset
    # ========================================================

    echo
    info "Authorizing ${PARTNER_PROJECT}.${PARTNER_DATASET}..."

    authorize_dataset \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET"

    # ========================================================
    # Grant Publisher + Customer users
    # BigQuery Data Viewer on authorized_table
    # ========================================================

    echo
    info "Granting Data Publisher access..."

    grant_data_viewer \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$AUTHORIZED_TABLE" \
        "$DATA_PUBLISHER_USER"

    ok "Data Publisher → ${AUTHORIZED_TABLE}"

    echo
    info "Granting Customer access..."

    grant_data_viewer \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$AUTHORIZED_TABLE" \
        "$CUSTOMER_USER"

    ok "Customer → ${AUTHORIZED_TABLE}"

    echo
    ok "TASK 1 COMPLETED"
}

# ============================================================
# TASK 2
#
# CREATE AUTHORIZED VIEW IN DATA PUBLISHING PROJECT
# ============================================================

task2() {

    step "[2/3] TASK 2 - CREATE AUTHORIZED VIEW"

    local location=""

    location="$(
        get_location \
            "$PUBLISHER_PROJECT" \
            "$PUBLISHER_DATASET"
    )"

    echo "${WHITE}Publisher Project : ${CYAN}${BOLD}${PUBLISHER_PROJECT}${RESET}"
    echo "${WHITE}Dataset           : ${CYAN}${PUBLISHER_DATASET}${RESET}"
    echo "${WHITE}View              : ${GREEN}${AUTHORIZED_VIEW}${RESET}"
    echo "${WHITE}Location          : ${CYAN}${location}${RESET}"

    # ========================================================
    # Create authorized_view
    # ========================================================

    echo
    info "Creating ${AUTHORIZED_VIEW} for New York..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$PUBLISHER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${PUBLISHER_PROJECT}.${PUBLISHER_DATASET}.${AUTHORIZED_VIEW}\`
        AS

        SELECT *
        FROM
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${AUTHORIZED_TABLE}\`
        WHERE state_code = 'NY'
        LIMIT 1000
        "

    if ! table_exists \
        "$PUBLISHER_PROJECT" \
        "$PUBLISHER_DATASET" \
        "$AUTHORIZED_VIEW"
    then
        fail "${AUTHORIZED_VIEW} was not created."
    fi

    ok "${AUTHORIZED_VIEW} created."

    # ========================================================
    # Authorize View
    #
    # Exact resource requested by lab:
    # PublisherProject.data_publisher_dataset.authorized_view
    # ========================================================

    echo
    info "Authorizing ${AUTHORIZED_VIEW}..."

    authorize_view \
        "$PUBLISHER_PROJECT" \
        "$PUBLISHER_DATASET" \
        "$PUBLISHER_PROJECT" \
        "$PUBLISHER_DATASET" \
        "$AUTHORIZED_VIEW"

    # ========================================================
    # Grant Customer Data Viewer
    # ========================================================

    echo
    info "Granting Customer access to ${AUTHORIZED_VIEW}..."

    grant_data_viewer \
        "$PUBLISHER_PROJECT" \
        "$PUBLISHER_DATASET" \
        "$AUTHORIZED_VIEW" \
        "$CUSTOMER_USER"

    ok "Customer → ${AUTHORIZED_VIEW}"

    echo
    ok "TASK 2 COMPLETED"
}

# ============================================================
# TASK 3
#
# ACCESS AUTHORIZED VIEW AS DATA TWIN
# ============================================================

task3() {

    step "[3/3] TASK 3 - ACCESS AUTHORIZED VIEW AS DATA TWIN"

    local location=""

    location="$(
        get_location \
            "$CUSTOMER_PROJECT" \
            "$CUSTOMER_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CUSTOMER_PROJECT}${RESET}"
    echo "${WHITE}Publisher Project: ${MAGENTA}${BOLD}${PUBLISHER_PROJECT}${RESET}"
    echo "${WHITE}Dataset          : ${CYAN}${CUSTOMER_DATASET}${RESET}"
    echo "${WHITE}View             : ${GREEN}${CUSTOMER_TABLE}${RESET}"

    # ========================================================
    # Run JOIN first
    # ========================================================

    echo
    info "Testing Data Twin JOIN..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=10 \
        "
        SELECT
            cities.zip_code,
            cities.city,
            cities.state_code,
            customers.last_name,
            customers.first_name
        FROM
            \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_INFO}\`
            AS customers
        JOIN
            \`${PUBLISHER_PROJECT}.${PUBLISHER_DATASET}.${AUTHORIZED_VIEW}\`
            AS cities
        ON
            cities.state_code = customers.state;
        "

    ok "Data Twin JOIN query successful."

    # ========================================================
    # Save View as customer_table
    # ========================================================

    echo
    info "Saving JOIN as ${CUSTOMER_DATASET}.${CUSTOMER_TABLE}..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_TABLE}\`
        AS

        SELECT
            cities.zip_code,
            cities.city,
            cities.state_code,
            customers.last_name,
            customers.first_name
        FROM
            \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_INFO}\`
            AS customers
        JOIN
            \`${PUBLISHER_PROJECT}.${PUBLISHER_DATASET}.${AUTHORIZED_VIEW}\`
            AS cities
        ON
            cities.state_code = customers.state
        "

    if ! table_exists \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_TABLE"
    then
        fail "${CUSTOMER_TABLE} was not created."
    fi

    ok "${CUSTOMER_TABLE} created."

    # ========================================================
    # Verify saved view
    # ========================================================

    echo
    info "Testing ${CUSTOMER_TABLE}..."

    timeout 60s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=5 \
        "
        SELECT *
        FROM
            \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_TABLE}\`
        LIMIT 5
        " \
        >/dev/null

    ok "${CUSTOMER_TABLE} query successful."

    echo
    ok "TASK 3 COMPLETED"
}

# ============================================================
# MAIN
# ============================================================

main() {

    banner

    # ========================================================
    # INPUT FIRST
    # ========================================================

    ask_users

    # ========================================================
    # LOCAL TOOLS
    # ========================================================

    require_cmd gcloud
    require_cmd bq
    require_cmd jq
    require_cmd grep
    require_cmd timeout

    # ========================================================
    # PARTNER ENVIRONMENT
    # ========================================================

    ORIGINAL_ACCOUNT="$(get_active_account)"
    ORIGINAL_PROJECT="$(get_config_project)"

    if [[ -z "$ORIGINAL_ACCOUNT" ]]; then
        fail "No active Data Sharing Partner account found."
    fi

    PARTNER_ACCOUNT="$ORIGINAL_ACCOUNT"

    PARTNER_PROJECT="${DEVSHELL_PROJECT_ID:-}"

    if [[ -z "$PARTNER_PROJECT" ]]; then
        PARTNER_PROJECT="$ORIGINAL_PROJECT"
    fi

    step "DATA SHARING PARTNER ENVIRONMENT"

    echo "${WHITE}Account : ${CYAN}${BOLD}${PARTNER_ACCOUNT}${RESET}"
    echo "${WHITE}Project : ${GREEN}${BOLD}${PARTNER_PROJECT:-not detected}${RESET}"

    # --------------------------------------------------------
    # Find Partner project if necessary
    # --------------------------------------------------------

    if \
        [[ -z "$PARTNER_PROJECT" ]] \
        ||
        ! dataset_exists \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    then

        find_project_with_dataset \
            "$PARTNER_ACCOUNT" \
            "$PARTNER_DATASET" \
            PARTNER_PROJECT \
            "Data Sharing Partner"
    fi

    switch_context \
        "$PARTNER_ACCOUNT" \
        "$PARTNER_PROJECT"

    # ========================================================
    # TASK 1
    # ========================================================

    task1

    # ========================================================
    # LOGIN DATA PUBLISHER
    # ========================================================

    ensure_login \
        "$DATA_PUBLISHER_USER" \
        "DATA PUBLISHER"

    # ========================================================
    # FIND PUBLISHER PROJECT
    # ========================================================

    find_project_with_dataset \
        "$DATA_PUBLISHER_USER" \
        "$PUBLISHER_DATASET" \
        PUBLISHER_PROJECT \
        "Data Publisher"

    switch_context \
        "$DATA_PUBLISHER_USER" \
        "$PUBLISHER_PROJECT"

    # ========================================================
    # TASK 2
    # ========================================================

    task2

    # ========================================================
    # LOGIN CUSTOMER
    # ========================================================

    ensure_login \
        "$CUSTOMER_USER" \
        "CUSTOMER"

    # ========================================================
    # FIND CUSTOMER PROJECT
    # ========================================================

    find_project_with_dataset \
        "$CUSTOMER_USER" \
        "$CUSTOMER_DATASET" \
        CUSTOMER_PROJECT \
        "Customer"

    switch_context \
        "$CUSTOMER_USER" \
        "$CUSTOMER_PROJECT"

    # ========================================================
    # TASK 3
    # ========================================================

    task3

    # ========================================================
    # FINISHED
    # ========================================================

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                    ALL GRADED TASKS DONE                     ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 1 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 2 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 3 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                      © ePlus.DEV                             ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Check my progress: Task 1${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Task 2${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Task 3${RESET}"

    echo
    echo "${CYAN}${BOLD}Task 4 has no Check my progress, so it is intentionally skipped.${RESET}"
    echo
    echo "${CYAN}${BOLD}The original Partner account/project will now be restored.${RESET}"
}

main "$@"

)