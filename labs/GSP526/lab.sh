#!/usr/bin/env bash

# ============================================================
# Privileged Access Manager Challenge Lab
# FULL ONE-SCRIPT AUTOMATION
# © ePlus.DEV
# ============================================================

set -Eeuo pipefail

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
# LAB VALUES
# ============================================================

ENTITLEMENT_ID="pam-entitlement"
LOCATION="global"

INITIAL_DURATION="36000s"   # 10 hours
UPDATED_DURATION="14400s"   # 4 hours
GRANT_DURATION="14400s"     # 4 hours

STATE_FILE="$HOME/.eplus_pam_lab_state"

# ============================================================
# BASIC HELPERS
# ============================================================

line() {
    printf '%*s\n' 72 '' | tr ' ' '='
}

section() {
    echo
    echo "${CYAN}${BOLD}$1${RESET}"
    line
}

success() {
    echo "${GREEN}✓ $1${RESET}"
}

warning() {
    echo "${YELLOW}⚠ $1${RESET}"
}

error() {
    echo "${RED}✗ $1${RESET}" >&2
}

info() {
    echo "${BLUE}→ $1${RESET}"
}

trap '
RC=$?
echo
error "Script failed at line ${LINENO}."
error "Exit code: ${RC}"
echo
echo "${YELLOW}You can safely rerun:${RESET}"
echo "  bash ~/lab.sh"
exit ${RC}
' ERR

# ============================================================
# PROGRESS
# ============================================================

run_progress() {

    local LABEL="$1"
    shift

    local LOG_FILE
    LOG_FILE="$(mktemp)"

    echo "${BLUE}→ ${LABEL}${RESET}"

    set +e

    "$@" >"$LOG_FILE" 2>&1 &
    local PID=$!

    set -e

    local ELAPSED=0
    local SPINNER='|/-\'
    local POS=0

    while kill -0 "$PID" 2>/dev/null; do

        printf "\r${YELLOW}  %s %-52s %4ds${RESET}" \
            "${SPINNER:POS++%4:1}" \
            "$LABEL" \
            "$ELAPSED"

        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    local RC

    set +e
    wait "$PID"
    RC=$?
    set -e

    printf "\r%-115s\r" ""

    if (( RC != 0 )); then

        error "$LABEL failed."
        echo
        cat "$LOG_FILE"

        rm -f "$LOG_FILE"

        return "$RC"
    fi

    success "$LABEL"

    rm -f "$LOG_FILE"
}

# ============================================================
# COUNTDOWN
# ============================================================

countdown() {

    local SECONDS="$1"
    local LABEL="$2"

    while (( SECONDS > 0 )); do

        printf "\r${YELLOW}  %-52s %3ds${RESET}" \
            "$LABEL" \
            "$SECONDS"

        sleep 1

        SECONDS=$((SECONDS - 1))
    done

    printf "\r%-110s\r" ""
}

# ============================================================
# GRADER CHECKPOINT
# ============================================================

checkpoint() {

    local TITLE="$1"
    shift

    echo
    echo "${MAGENTA}${BOLD}"
    line
    echo "$TITLE"
    line
    echo "${RESET}"

    local MESSAGE

    for MESSAGE in "$@"; do
        echo "${WHITE}${MESSAGE}${RESET}"
    done

    echo
    echo "${YELLOW}${BOLD}Click Check my progress now.${RESET}"
    echo "${YELLOW}Press ENTER only after the required task is GREEN.${RESET}"
    echo

    local WAITED=0

    while true; do

        if read -r -t 1; then
            printf "\r%-115s\r" ""
            break
        fi

        WAITED=$((WAITED + 1))

        printf "\r${CYAN}  Waiting for grader... elapsed: %3ds | Press ENTER when GREEN${RESET}" \
            "$WAITED"
    done

    echo
}

# ============================================================
# ACCOUNT HELPERS
# ============================================================

get_active_account() {

    gcloud auth list \
        --filter=status:ACTIVE \
        --format='value(account)' \
        2>/dev/null |
        head -n1
}

credential_exists() {

    local EMAIL="$1"

    gcloud auth list \
        --filter="account=${EMAIL}" \
        --format='value(account)' \
        2>/dev/null |
        grep -Fxq "$EMAIL"
}

credential_usable() {

    local EMAIL="$1"

    gcloud auth print-access-token \
        --account="$EMAIL" \
        >/dev/null 2>&1
}

# ============================================================
# GOOGLE LOGIN
#
# - Automatically answers Cloud Shell Y/n
# - Shows actual clickable Google OAuth URL
# - Verification code entered once
# - No extra ENTER required afterward
# ============================================================

login_account_interactive() {

    local EMAIL="$1"

    echo
    echo "${MAGENTA}${BOLD}"
    line
    echo "GOOGLE CLOUD ACCOUNT LOGIN REQUIRED"
    line
    echo "${RESET}"

    echo "Account:"
    echo
    echo "${CYAN}${BOLD}  $EMAIL${RESET}"
    echo

    echo "${GREEN}✓ Cloud Shell confirmation is automatic.${RESET}"
    echo
    echo "${YELLOW}${BOLD}A CLICKABLE GOOGLE LOGIN URL WILL APPEAR BELOW.${RESET}"
    echo

    echo "1. Click the https://accounts.google.com/... link"
    echo "2. Sign in as:"
    echo
    echo "${CYAN}${BOLD}   $EMAIL${RESET}"
    echo
    echo "3. Use the password from the lab panel"
    echo "4. Authorize Google Cloud CLI"
    echo "5. Copy the verification code"
    echo "6. Paste it here and press ENTER once"
    echo

    line
    echo "${CYAN}${BOLD}GENERATING CLICKABLE GOOGLE LOGIN LINK...${RESET}"
    line
    echo

    set +e

    LOGIN_EMAIL="$EMAIL" python3 <<'PY'
import errno
import os
import pty
import select
import sys

email = os.environ["LOGIN_EMAIL"]

pid, master_fd = pty.fork()

if pid == 0:
    os.execvp(
        "gcloud",
        [
            "gcloud",
            "auth",
            "login",
            email,
            "--no-launch-browser",
            "--force",
            "--activate",
        ],
    )

tty_fd = os.open("/dev/tty", os.O_RDONLY)

buffer = ""
confirmed = False

try:
    while True:

        readable, _, _ = select.select(
            [master_fd, tty_fd],
            [],
            []
        )

        if master_fd in readable:

            try:
                data = os.read(master_fd, 4096)

            except OSError as exc:

                if exc.errno == errno.EIO:
                    break

                raise

            if not data:
                break

            text = data.decode(
                "utf-8",
                errors="replace"
            )

            sys.stdout.write(text)
            sys.stdout.flush()

            buffer = (buffer + text)[-8192:]

            if (
                not confirmed
                and "Do you want to continue (Y/n)?" in buffer
            ):
                os.write(
                    master_fd,
                    b"Y\r"
                )

                confirmed = True
                buffer = ""

        if tty_fd in readable:

            try:
                user_input = os.read(
                    tty_fd,
                    4096
                )

            except OSError:
                break

            if user_input:

                try:
                    os.write(
                        master_fd,
                        user_input
                    )

                except OSError:
                    break

finally:

    try:
        os.close(tty_fd)
    except OSError:
        pass

    try:
        os.close(master_fd)
    except OSError:
        pass

_, status = os.waitpid(pid, 0)

if os.WIFEXITED(status):
    rc = os.WEXITSTATUS(status)

elif os.WIFSIGNALED(status):
    rc = 128 + os.WTERMSIG(status)

else:
    rc = 1

sys.exit(rc)
PY

    RC=$?

    set -e

    if (( RC != 0 )); then

        error "Google authentication failed."
        return "$RC"
    fi

    echo
    success "Google authentication completed."
}

activate_account_only() {

    local EMAIL="$1"

    info "Switching to $EMAIL"

    if credential_exists "$EMAIL" &&
       credential_usable "$EMAIL"; then

        gcloud config set account "$EMAIL" \
            >/dev/null

    else

        login_account_interactive "$EMAIL"

        gcloud config set account "$EMAIL" \
            >/dev/null
    fi

    local CURRENT
    CURRENT="$(get_active_account)"

    if [[ "$CURRENT" != "$EMAIL" ]]; then

        error "Unable to activate account."

        echo "Expected : $EMAIL"
        echo "Current  : $CURRENT"

        exit 1
    fi

    success "Active account: $EMAIL"
}

# ============================================================
# IMPORTANT FIX
#
# PRIMARY:
#   Set project normally.
#
# SECONDARY:
#   DO NOT set core/project.
#   Secondary may intentionally have no normal project access.
#   PAM grant operations below always use FULL resource names.
# ============================================================

use_primary() {

    activate_account_only "$PRIMARY_USER"

    gcloud config set project "$PROJECT_ID" \
        --quiet \
        >/dev/null

    success "Primary project context: $PROJECT_ID"
}

use_secondary() {

    # Remove ambient project before using Security Lead.
    # Prevents:
    #
    # WARNING: You do not appear to have access to project...
    # Do you want to continue (Y/n)?
    #
    gcloud config unset project \
        --quiet \
        >/dev/null 2>&1 || true

    activate_account_only "$SECONDARY_USER"

    success "Security Lead ready - no project property required."
}

# ============================================================
# PAM CLI
# ============================================================

detect_pam_cli() {

    if gcloud pam --help >/dev/null 2>&1; then

        PAM=(gcloud pam)
        PAM_CHANNEL="GA"

    elif gcloud beta pam --help >/dev/null 2>&1; then

        PAM=(gcloud beta pam)
        PAM_CHANNEL="BETA"

    else

        PAM=(gcloud alpha pam)
        PAM_CHANNEL="ALPHA"
    fi
}

# ============================================================
# ENTITLEMENT HELPERS
# ============================================================

entitlement_exists() {

    "${PAM[@]}" entitlements describe "$ENTITLEMENT_ID" \
        --project="$PROJECT_ID" \
        --location="$LOCATION" \
        >/dev/null 2>&1
}

entitlement_state() {

    "${PAM[@]}" entitlements describe "$ENTITLEMENT_ID" \
        --project="$PROJECT_ID" \
        --location="$LOCATION" \
        --format='value(state)' \
        2>/dev/null || true
}

entitlement_duration() {

    "${PAM[@]}" entitlements describe "$ENTITLEMENT_ID" \
        --project="$PROJECT_ID" \
        --location="$LOCATION" \
        --format='value(maxRequestDuration)' \
        2>/dev/null || true
}

wait_entitlement_available() {

    echo
    info "Waiting for entitlement propagation"

    local ATTEMPT
    local STATE

    for ATTEMPT in $(seq 1 60); do

        STATE="$(entitlement_state)"

        printf "\r${YELLOW}  Entitlement state: %-20s check %02d/60${RESET}" \
            "${STATE:-NOT_READY}" \
            "$ATTEMPT"

        if [[ "$STATE" == "AVAILABLE" ]]; then

            echo

            success "Entitlement state = AVAILABLE"

            return 0
        fi

        sleep 5
    done

    echo
    error "Entitlement did not reach AVAILABLE."

    return 1
}

# ============================================================
# GRANT HELPERS
#
# All secondary operations use FULL resource names.
# ============================================================

latest_primary_grant() {

    "${PAM[@]}" grants search \
        --entitlement="$ENTITLEMENT_NAME" \
        --caller-relationship=had-created \
        --sort-by='~createTime' \
        --limit=1 \
        --format='value(name)' \
        2>/dev/null || true
}

grant_state() {

    local GRANT="$1"

    "${PAM[@]}" grants describe "$GRANT" \
        --format='value(state)' \
        2>/dev/null || true
}

wait_grant_state() {

    local GRANT="$1"
    local TARGET="$2"
    local MAX="${3:-120}"

    echo
    info "Waiting for grant state: $TARGET"

    local ATTEMPT
    local STATE

    for ATTEMPT in $(seq 1 "$MAX"); do

        STATE="$(grant_state "$GRANT")"

        printf "\r${YELLOW}  Grant state: %-20s check %03d/%03d${RESET}" \
            "${STATE:-UNKNOWN}" \
            "$ATTEMPT" \
            "$MAX"

        if [[ "$STATE" == "$TARGET" ]]; then

            echo
            success "Grant state = $TARGET"

            return 0
        fi

        sleep 4
    done

    echo
    error "Grant did not reach $TARGET."

    return 1
}

wait_grant_not_open() {

    local GRANT="$1"

    echo
    info "Waiting for stale grant to close"

    for ATTEMPT in $(seq 1 60); do

        STATE="$(grant_state "$GRANT")"

        printf "\r${YELLOW}  Old grant state: %-20s check %02d/60${RESET}" \
            "${STATE:-UNKNOWN}" \
            "$ATTEMPT"

        case "$STATE" in

            ACTIVE|ACTIVATING|APPROVAL_AWAITED|SCHEDULED|REVOKING)
                ;;

            *)
                echo
                success "Stale grant closed: ${STATE:-TERMINAL}"
                return 0
                ;;
        esac

        sleep 3
    done

    echo
    error "Stale grant did not close."

    return 1
}

# ============================================================
# CLEAN OLD TASK 4 GRANT
#
# We deliberately DO NOT reuse stale grants.
# ============================================================

cleanup_stale_grant() {

    use_primary

    local OLD_GRANT
    OLD_GRANT="$(latest_primary_grant)"

    if [[ -z "$OLD_GRANT" ]]; then

        success "No previous grant found."
        return 0
    fi

    local OLD_STATE
    OLD_STATE="$(grant_state "$OLD_GRANT")"

    echo
    warning "Previous grant found:"
    echo "  $OLD_GRANT"
    echo "  state = $OLD_STATE"
    echo

    case "$OLD_STATE" in

        APPROVAL_AWAITED)

            use_secondary

            info "Denying stale pending grant"

            "${PAM[@]}" grants deny "$OLD_GRANT" \
                --reason="Cleanup stale challenge-lab request"

            wait_grant_not_open "$OLD_GRANT"
            ;;

        ACTIVATING)

            use_secondary

            wait_grant_state \
                "$OLD_GRANT" \
                "ACTIVE" \
                120

            info "Revoking stale active grant"

            "${PAM[@]}" grants revoke "$OLD_GRANT" \
                --reason="Cleanup stale challenge-lab request"

            wait_grant_state \
                "$OLD_GRANT" \
                "REVOKED" \
                120
            ;;

        ACTIVE)

            use_secondary

            info "Revoking stale active grant"

            "${PAM[@]}" grants revoke "$OLD_GRANT" \
                --reason="Cleanup stale challenge-lab request"

            wait_grant_state \
                "$OLD_GRANT" \
                "REVOKED" \
                120
            ;;

        REVOKING)

            use_secondary

            wait_grant_state \
                "$OLD_GRANT" \
                "REVOKED" \
                120
            ;;

        SCHEDULED)

            use_secondary

            info "Revoking stale scheduled grant"

            "${PAM[@]}" grants revoke "$OLD_GRANT" \
                --reason="Cleanup stale challenge-lab request" \
                || true

            wait_grant_not_open "$OLD_GRANT"
            ;;

        *)

            success "Previous grant is already terminal: $OLD_STATE"
            ;;
    esac

    use_primary
}

# ============================================================
# BANNER
# ============================================================

clear

echo "${MAGENTA}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║          PRIVILEGED ACCESS MANAGER CHALLENGE LAB                  ║"
echo "║                     ONE-SCRIPT AUTOMATION                         ║"
echo "║                         © ePlus.DEV                                ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo "${RESET}"

# ============================================================
# INPUT
# ============================================================

echo "${CYAN}${BOLD}"
echo "┌──────────────────────────────────────────────────────────────────────┐"
echo "│                    LAB REQUIRED INFORMATION                        │"
echo "└──────────────────────────────────────────────────────────────────────┘"
echo "${RESET}"

echo

read -r -p "$(echo -e "${YELLOW}${BOLD}Cymbal Security Lead Username: ${RESET}")" SECONDARY_USER

SECONDARY_USER="$(
    printf '%s' "$SECONDARY_USER" |
    xargs
)"

SECONDARY_USER="${SECONDARY_USER#\"}"
SECONDARY_USER="${SECONDARY_USER%\"}"
SECONDARY_USER="${SECONDARY_USER#\'}"
SECONDARY_USER="${SECONDARY_USER%\'}"

if [[ -z "$SECONDARY_USER" ||
      "$SECONDARY_USER" != *@* ]]; then

    error "Invalid Cymbal Security Lead Username."
    exit 1
fi

success "Security Lead: $SECONDARY_USER"

# ============================================================
# PROJECT + PRIMARY
# ============================================================

PROJECT_ID="$(
    gcloud config get-value project 2>/dev/null || true
)"

if [[ -z "$PROJECT_ID" ||
      "$PROJECT_ID" == "(unset)" ]]; then

    PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi

if [[ -z "$PROJECT_ID" ]]; then

    error "Unable to detect Project ID."
    exit 1
fi

CURRENT_ACCOUNT="$(get_active_account)"

PRIMARY_USER=""

if [[ -f "$STATE_FILE" ]]; then

    SAVED_PROJECT="$(
        grep '^PROJECT_ID=' "$STATE_FILE" 2>/dev/null |
        cut -d= -f2- || true
    )"

    SAVED_PRIMARY="$(
        grep '^PRIMARY_USER=' "$STATE_FILE" 2>/dev/null |
        cut -d= -f2- || true
    )"

    if [[ "$SAVED_PROJECT" == "$PROJECT_ID" &&
          -n "$SAVED_PRIMARY" ]]; then

        PRIMARY_USER="$SAVED_PRIMARY"
    fi
fi

if [[ -z "$PRIMARY_USER" ]]; then

    if [[ "$CURRENT_ACCOUNT" == "$SECONDARY_USER" ]]; then

        error "Run this script initially from the Systems Admin account."
        exit 1
    fi

    PRIMARY_USER="$CURRENT_ACCOUNT"
fi

if [[ "$PRIMARY_USER" == "$SECONDARY_USER" ]]; then

    error "Systems Admin and Security Lead must be different."
    exit 1
fi

cat > "$STATE_FILE" <<STATE
PROJECT_ID=$PROJECT_ID
PRIMARY_USER=$PRIMARY_USER
SECONDARY_USER=$SECONDARY_USER
STATE

chmod 600 "$STATE_FILE"

success "Systems Admin: $PRIMARY_USER"

use_primary

# ============================================================
# ENVIRONMENT
# ============================================================

section "[0/8] Detecting Google Cloud environment"

PROJECT_NUMBER="$(
    gcloud projects describe "$PROJECT_ID" \
        --format='value(projectNumber)'
)"

ORG_ID="$(
    gcloud projects get-ancestors "$PROJECT_ID" \
        --format='csv[no-heading](type,id)' \
        2>/dev/null |
        awk -F',' '$1=="organization" {print $2; exit}'
)"

if [[ -z "$ORG_ID" ]]; then

    error "Unable to detect Organization ID."
    exit 1
fi

PAM_SERVICE_AGENT="service-org-${ORG_ID}@gcp-sa-pam.iam.gserviceaccount.com"

ENTITLEMENT_NAME="projects/${PROJECT_ID}/locations/${LOCATION}/entitlements/${ENTITLEMENT_ID}"

detect_pam_cli

echo "Project ID        : $PROJECT_ID"
echo "Project number    : $PROJECT_NUMBER"
echo "Organization ID   : $ORG_ID"
echo "Location          : $LOCATION"
echo "PAM CLI           : $PAM_CHANNEL"
echo
echo "Systems Admin     : $PRIMARY_USER"
echo "Security Lead     : $SECONDARY_USER"
echo
echo "PAM service agent : $PAM_SERVICE_AGENT"

success "Environment detected."

# ============================================================
# TASK 1
# ============================================================

section "[1/8] TASK 1 - Enable Privileged Access Manager"

run_progress \
    "Enable Privileged Access Manager API" \
    gcloud services enable \
        privilegedaccessmanager.googleapis.com \
        --project="$PROJECT_ID" \
        --quiet

"${PAM[@]}" check-onboarding-status \
    --project="$PROJECT_ID" \
    --location="$LOCATION" \
    >/tmp/pam-onboarding.log \
    2>&1 || true

echo
info "Configure PAM service agent"

IAM_OK=0

for ATTEMPT in $(seq 1 18); do

    echo "${BLUE}→ Service Agent IAM attempt ${ATTEMPT}/18${RESET}"

    set +e

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${PAM_SERVICE_AGENT}" \
        --role="roles/privilegedaccessmanager.serviceAgent" \
        --condition=None \
        --quiet \
        >/tmp/pam-service-agent.log \
        2>&1

    RC=$?

    set -e

    if (( RC == 0 )); then

        IAM_OK=1
        break
    fi

    warning "Service agent still propagating."

    tail -n 4 /tmp/pam-service-agent.log || true

    countdown 5 "Retrying Service Agent IAM"
done

if (( IAM_OK == 0 )); then

    cat /tmp/pam-service-agent.log

    error "Unable to configure PAM Service Agent."

    exit 1
fi

success "TASK 1 configuration complete."

# ============================================================
# TASK 2
# ============================================================

section "[2/8] TASK 2 - Create pam-entitlement"

if entitlement_exists; then

    warning "pam-entitlement already exists."

    echo "State    : $(entitlement_state)"
    echo "Duration : $(entitlement_duration)"

else

    cat > /tmp/pam-entitlement.yaml <<YAML
privilegedAccess:
  gcpIamAccess:
    resourceType: cloudresourcemanager.googleapis.com/Project
    resource: //cloudresourcemanager.googleapis.com/projects/${PROJECT_ID}
    roleBindings:
    - role: roles/compute.admin

maxRequestDuration: ${INITIAL_DURATION}

eligibleUsers:
- principals:
  - user:${PRIMARY_USER}

approvalWorkflow:
  manualApprovals:
    requireApproverJustification: false
    steps:
    - approvalsNeeded: 1
      approvers:
      - principals:
        - user:${SECONDARY_USER}

requesterJustificationConfig:
  notMandatory: {}
YAML

    echo
    cat /tmp/pam-entitlement.yaml
    echo

    run_progress \
        "Create 10-hour Compute Admin entitlement" \
        "${PAM[@]}" entitlements create "$ENTITLEMENT_ID" \
            --project="$PROJECT_ID" \
            --location="$LOCATION" \
            --entitlement-file=/tmp/pam-entitlement.yaml \
            --quiet
fi

wait_entitlement_available

CURRENT_DURATION="$(entitlement_duration)"

echo
echo "Maximum duration : $CURRENT_DURATION"

"${PAM[@]}" entitlements describe "$ENTITLEMENT_ID" \
    --project="$PROJECT_ID" \
    --location="$LOCATION" \
    --format='yaml(
        name,
        state,
        maxRequestDuration,
        privilegedAccess,
        eligibleUsers,
        approvalWorkflow,
        requesterJustificationConfig
    )'

if [[ "$CURRENT_DURATION" == "$INITIAL_DURATION" ]]; then

    checkpoint \
        "CHECKPOINT #1 - TASK 1 + TASK 2" \
        "" \
        "Click Check my progress:" \
        "" \
        "  TASK 1 - Enable Privileged Access Manager" \
        "  TASK 2 - Create the entitlement" \
        "" \
        "Maximum duration is currently 10 hours." \
        "" \
        "Continue only after both tasks are GREEN."
fi

# ============================================================
# TASK 3
# ============================================================

section "[3/8] TASK 3 - Update entitlement to 4 hours"

CURRENT_DURATION="$(entitlement_duration)"

if [[ "$CURRENT_DURATION" != "$UPDATED_DURATION" ]]; then

    rm -f /tmp/pam-entitlement-update.yaml

    run_progress \
        "Export current entitlement" \
        "${PAM[@]}" entitlements export "$ENTITLEMENT_ID" \
            --project="$PROJECT_ID" \
            --location="$LOCATION" \
            --destination=/tmp/pam-entitlement-update.yaml

    sed -i \
        -E \
        "s/^maxRequestDuration:[[:space:]]*.*/maxRequestDuration: ${UPDATED_DURATION}/" \
        /tmp/pam-entitlement-update.yaml

    run_progress \
        "Update maximum duration to 4 hours" \
        "${PAM[@]}" entitlements update "$ENTITLEMENT_ID" \
            --project="$PROJECT_ID" \
            --location="$LOCATION" \
            --entitlement-file=/tmp/pam-entitlement-update.yaml \
            --quiet

    wait_entitlement_available

else

    success "Maximum duration is already 4 hours."
fi

CURRENT_DURATION="$(entitlement_duration)"

if [[ "$CURRENT_DURATION" != "$UPDATED_DURATION" ]]; then

    error "Task 3 verification failed."

    echo "Expected : $UPDATED_DURATION"
    echo "Actual   : $CURRENT_DURATION"

    exit 1
fi

success "TASK 3 - Maximum duration = 4 hours."

# ============================================================
# TASK 4
# CLEAN STALE GRANTS FIRST
# ============================================================

section "[4/8] TASK 4 - Prepare a fresh grant request"

cleanup_stale_grant

use_primary

# ============================================================
# TASK 4
# CREATE FRESH GRANT
# ============================================================

echo
info "Creating a FRESH 4-hour grant"

CREATE_STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

"${PAM[@]}" grants create \
    --entitlement="$ENTITLEMENT_NAME" \
    --requested-duration="$GRANT_DURATION" \
    --justification="Test justification for temporary Compute Admin access"

echo
info "Resolving newly created grant"

GRANT_NAME=""

for ATTEMPT in $(seq 1 45); do

    GRANT_NAME="$(latest_primary_grant)"

    if [[ -n "$GRANT_NAME" ]] &&
       [[ "$(grant_state "$GRANT_NAME")" == "APPROVAL_AWAITED" ]]; then

        break
    fi

    printf "\r${YELLOW}  Waiting for fresh grant... %02d/45${RESET}" \
        "$ATTEMPT"

    sleep 3
done

printf "\r%-110s\r" ""

if [[ -z "$GRANT_NAME" ]]; then

    error "Unable to resolve fresh grant."
    exit 1
fi

echo
echo "Fresh grant:"
echo "  $GRANT_NAME"

echo

"${PAM[@]}" grants describe "$GRANT_NAME" \
    --format='yaml(
        name,
        requester,
        requestedDuration,
        justification,
        state,
        createTime
    )'

# ============================================================
# TASK 4
# APPROVE EXACT FRESH GRANT AS SECONDARY
# ============================================================

section "[5/8] TASK 4 - Approve as Cymbal Security Lead"

use_secondary

echo
echo "Security Lead:"
echo "  $SECONDARY_USER"

echo
echo "Exact grant to approve:"
echo "  $GRANT_NAME"
echo

STATE="$(grant_state "$GRANT_NAME")"

if [[ "$STATE" != "APPROVAL_AWAITED" ]]; then

    error "Fresh grant is not awaiting approval."

    echo "Current state: $STATE"

    exit 1
fi

run_progress \
    "Approve exact fresh PAM grant" \
    "${PAM[@]}" grants approve "$GRANT_NAME" \
        --reason="Approved by Cymbal Security Lead for challenge lab"

wait_grant_state \
    "$GRANT_NAME" \
    "ACTIVE" \
    120

echo

"${PAM[@]}" grants describe "$GRANT_NAME" \
    --format='yaml(
        name,
        requester,
        requestedDuration,
        justification,
        state,
        auditTrail,
        timeline
    )'

# ============================================================
# VERIFY TASK 4 VALUES
# ============================================================

REQUESTER="$(
    "${PAM[@]}" grants describe "$GRANT_NAME" \
        --format='value(requester)'
)"

REQUESTED_DURATION="$(
    "${PAM[@]}" grants describe "$GRANT_NAME" \
        --format='value(requestedDuration)'
)"

FINAL_STATE="$(grant_state "$GRANT_NAME")"

echo
echo "${CYAN}${BOLD}TASK 4 VERIFICATION${RESET}"
echo
echo "Expected requester : $PRIMARY_USER"
echo "Actual requester   : $REQUESTER"
echo
echo "Expected duration  : 14400s"
echo "Actual duration    : $REQUESTED_DURATION"
echo
echo "Expected state     : ACTIVE"
echo "Actual state       : $FINAL_STATE"

if [[ "$REQUESTER" != "$PRIMARY_USER" ]]; then

    error "Requester does not match Systems Admin."
    exit 1
fi

if [[ "$REQUESTED_DURATION" != "$GRANT_DURATION" ]]; then

    error "Grant duration is not 4 hours."
    exit 1
fi

if [[ "$FINAL_STATE" != "ACTIVE" ]]; then

    error "Grant is not ACTIVE."
    exit 1
fi

# ============================================================
# WAIT FOR TASK 4 AUDIT EVENT
#
# Switch to PRIMARY to query logs.
# Grant remains ACTIVE.
# ============================================================

section "[6/8] TASK 4 - Wait for approval audit propagation"

use_primary

CREATE_LOG=0
APPROVE_LOG=0

for ATTEMPT in $(seq 1 30); do

    LOGS="$(
        gcloud logging read \
            'protoPayload.serviceName="privilegedaccessmanager.googleapis.com"' \
            --project="$PROJECT_ID" \
            --freshness=30m \
            --limit=100 \
            --format='csv[no-heading](
                protoPayload.methodName,
                protoPayload.authenticationInfo.principalEmail,
                protoPayload.resourceName
            )' \
            2>/dev/null || true
    )"

    if echo "$LOGS" |
       grep -i 'CreateGrant' |
       grep -F "$PRIMARY_USER" \
       >/dev/null; then

        CREATE_LOG=1
    fi

    if echo "$LOGS" |
       grep -i 'ApproveGrant' |
       grep -F "$SECONDARY_USER" \
       >/dev/null; then

        APPROVE_LOG=1
    fi

    printf "\r${YELLOW}  CreateGrant: %-3s | ApproveGrant: %-3s | check %02d/30${RESET}" \
        "$([[ $CREATE_LOG == 1 ]] && echo YES || echo NO)" \
        "$([[ $APPROVE_LOG == 1 ]] && echo YES || echo NO)" \
        "$ATTEMPT"

    if (( CREATE_LOG == 1 &&
          APPROVE_LOG == 1 )); then

        break
    fi

    sleep 5
done

echo
echo

if (( CREATE_LOG == 1 )); then
    success "CreateGrant audit event detected."
else
    warning "CreateGrant log is still propagating."
fi

if (( APPROVE_LOG == 1 )); then
    success "ApproveGrant audit event detected."
else
    warning "ApproveGrant log is still propagating."
fi

echo
success "TASK 4 fresh grant is ACTIVE."

# ============================================================
# TASK 3 + TASK 4 CHECKPOINT
# ============================================================

checkpoint \
    "CHECKPOINT #2 - TASK 3 + TASK 4" \
    "" \
    "Fresh grant created AFTER Task 3." \
    "" \
    "Requester:" \
    "  $PRIMARY_USER" \
    "" \
    "Approver:" \
    "  $SECONDARY_USER" \
    "" \
    "Duration:" \
    "  4 hours" \
    "" \
    "State:" \
    "  ACTIVE" \
    "" \
    "Click Check my progress:" \
    "" \
    "  TASK 3 - Update the entitlement" \
    "  TASK 4 - Request temporary elevated access" \
    "" \
    "DO NOT continue until Task 4 is GREEN."

# ============================================================
# TASK 5
# ============================================================

section "[7/8] TASK 5 - Revoke fresh active grant"

use_secondary

STATE="$(grant_state "$GRANT_NAME")"

echo
echo "Grant:"
echo "  $GRANT_NAME"
echo
echo "State:"
echo "  $STATE"
echo

if [[ "$STATE" == "ACTIVATING" ]]; then

    wait_grant_state \
        "$GRANT_NAME" \
        "ACTIVE" \
        120

    STATE="ACTIVE"
fi

if [[ "$STATE" == "ACTIVE" ]]; then

    run_progress \
        "Revoke fresh PAM grant" \
        "${PAM[@]}" grants revoke "$GRANT_NAME" \
            --reason="Challenge lab complete - restore least privilege"

elif [[ "$STATE" == "REVOKED" ]]; then

    warning "Grant is already revoked."

else

    error "Cannot revoke grant in state: $STATE"

    exit 1
fi

wait_grant_state \
    "$GRANT_NAME" \
    "REVOKED" \
    120

success "TASK 5 - Fresh grant is REVOKED."

checkpoint \
    "CHECKPOINT #3 - TASK 5" \
    "" \
    "The fresh Task 4 grant is now REVOKED." \
    "" \
    "Click Check my progress:" \
    "" \
    "  TASK 5 - Revoke a grant" \
    "" \
    "Continue only after Task 5 is GREEN."

# ============================================================
# TASK 6
# ============================================================

section "[8/8] TASK 6 - Delete entitlement"

use_primary

FINAL_STATE="$(grant_state "$GRANT_NAME")"

if [[ "$FINAL_STATE" != "REVOKED" &&
      "$FINAL_STATE" != "ENDED" ]]; then

    error "Grant is not in a terminal state."

    echo "Current state: $FINAL_STATE"

    exit 1
fi

if entitlement_exists; then

    run_progress \
        "Delete pam-entitlement" \
        "${PAM[@]}" entitlements delete "$ENTITLEMENT_ID" \
            --project="$PROJECT_ID" \
            --location="$LOCATION" \
            --quiet

else

    warning "pam-entitlement is already deleted."
fi

echo
info "Verify entitlement deletion"

for ATTEMPT in $(seq 1 40); do

    if ! entitlement_exists; then

        success "pam-entitlement deleted."
        break
    fi

    printf "\r${YELLOW}  Waiting for deletion... %02d/40${RESET}" \
        "$ATTEMPT"

    sleep 3
done

printf "\r%-110s\r" ""

# ============================================================
# AUDIT LOGS
# ============================================================

section "[TASK 6] PAM audit logs"

echo
gcloud logging read \
    'protoPayload.serviceName="privilegedaccessmanager.googleapis.com"' \
    --project="$PROJECT_ID" \
    --limit=50 \
    --order=asc \
    --format='table(
        timestamp:label=TIME,
        protoPayload.authenticationInfo.principalEmail:label=PRINCIPAL,
        protoPayload.methodName:label=METHOD,
        protoPayload.resourceName:label=RESOURCE
    )' \
    || true

# ============================================================
# FINAL
# ============================================================

echo
echo "${GREEN}${BOLD}"
line
echo "                PAM CHALLENGE LAB COMPLETED"
line
echo "${RESET}"

echo "${GREEN}✓ TASK 1 - PAM enabled${RESET}"
echo "${GREEN}✓ TASK 2 - 10-hour entitlement created${RESET}"
echo "${GREEN}✓ TASK 3 - Entitlement updated to 4 hours${RESET}"
echo "${GREEN}✓ TASK 4 - Fresh 4-hour grant requested${RESET}"
echo "${GREEN}✓ TASK 4 - Fresh grant approved by Security Lead${RESET}"
echo "${GREEN}✓ TASK 5 - Fresh active grant revoked${RESET}"
echo "${GREEN}✓ TASK 6 - Entitlement deleted${RESET}"
echo "${GREEN}✓ TASK 6 - Audit logs reviewed${RESET}"

echo
echo "Project:"
echo "  $PROJECT_ID"

echo
echo "Systems Admin:"
echo "  $PRIMARY_USER"

echo
echo "Security Lead:"
echo "  $SECONDARY_USER"

echo
echo "${YELLOW}${BOLD}Now click Check my progress for TASK 6.${RESET}"

echo
echo "${MAGENTA}${BOLD}© ePlus.DEV${RESET}"