#!/bin/bash

# ==============================================================
# GSP328 - Develop Serverless Applications on Cloud Run
# Challenge Lab
#
# © ePlus.DEV
# ==============================================================

set -Eeuo pipefail

# ==============================================================
# COLORS
# ==============================================================

BLACK=$(tput setaf 0 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
MAGENTA=$(tput setaf 5 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
WHITE=$(tput setaf 7 2>/dev/null || true)

BG_RED=$(tput setab 1 2>/dev/null || true)
BG_GREEN=$(tput setab 2 2>/dev/null || true)
BG_BLUE=$(tput setab 4 2>/dev/null || true)
BG_MAGENTA=$(tput setab 5 2>/dev/null || true)
BG_CYAN=$(tput setab 6 2>/dev/null || true)

BOLD=$(tput bold 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# ==============================================================
# FUNCTIONS
# ==============================================================

header() {
    clear

    echo
    echo "${BG_MAGENTA}${WHITE}${BOLD}==============================================================${RESET}"
    echo "${BG_MAGENTA}${WHITE}${BOLD}     DEVELOP SERVERLESS APPLICATIONS ON CLOUD RUN             ${RESET}"
    echo "${BG_MAGENTA}${WHITE}${BOLD}                    CHALLENGE LAB                              ${RESET}"
    echo "${BG_MAGENTA}${WHITE}${BOLD}                      ePlus.DEV                                ${RESET}"
    echo "${BG_MAGENTA}${WHITE}${BOLD}==============================================================${RESET}"
    echo
}

section() {
    echo
    echo "${CYAN}${BOLD}==============================================================${RESET}"
    echo "${CYAN}${BOLD} $1${RESET}"
    echo "${CYAN}${BOLD}==============================================================${RESET}"
}

info() {
    echo "${BLUE}${BOLD}➜${RESET} $1"
}

success() {
    echo "${GREEN}${BOLD}✓${RESET} $1"
}

warn() {
    echo "${YELLOW}${BOLD}⚠${RESET} $1"
}

error() {
    echo "${RED}${BOLD}✗ $1${RESET}"
}

die() {
    error "$1"
    exit 1
}

on_error() {
    echo
    error "Script stopped at line $1."
    echo "${YELLOW}Check the error immediately above this message.${RESET}"
    exit 1
}

trap 'on_error $LINENO' ERR

wait_for_service() {

    local SERVICE_NAME="$1"
    local READY=""

    info "Waiting for ${SERVICE_NAME}..."

    for i in {1..40}; do

        READY=$(gcloud run services describe "$SERVICE_NAME" \
            --region="$REGION" \
            --platform=managed \
            --project="$PROJECT_ID" \
            --format="value(status.conditions[0].status)" \
            2>/dev/null || true)

        if [[ "$READY" == "True" ]]; then
            echo
            success "${SERVICE_NAME} is ready."
            return 0
        fi

        printf "\r${YELLOW}Waiting for Cloud Run... %02d/40${RESET}" "$i"

        sleep 3
    done

    echo
    warn "Service readiness check timed out."
}

get_service_url() {

    local SERVICE_NAME="$1"

    gcloud run services describe "$SERVICE_NAME" \
        --region="$REGION" \
        --platform=managed \
        --project="$PROJECT_ID" \
        --format="value(status.url)"
}

# ==============================================================
# START
# ==============================================================

header

# ==============================================================
# PROJECT
# ==============================================================

section "DETECT GOOGLE CLOUD ENVIRONMENT"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then

    PROJECT_ID=$(gcloud projects list \
        --filter="projectId:qwiklabs-gcp" \
        --format="value(projectId)" \
        --limit=1)
fi

[[ -n "$PROJECT_ID" ]] || die "Unable to detect Qwiklabs Project ID."

gcloud config set project "$PROJECT_ID" --quiet >/dev/null


# ==============================================================
# INPUT VARIABLES
# ==============================================================

section "ENTER LAB VARIABLES"

echo "${YELLOW}${BOLD}Enter values from your lab.${RESET}"
echo "${WHITE}Press Enter if the default value inside [ ] is correct.${RESET}"
echo

printf "${CYAN}${BOLD}Task 1${RESET} ${WHITE}Public Billing Service${RESET} ${GREEN}[public-billing-service-748]${RESET}: "
read -r TASK_1_SERVICES_NAME
TASK_1_SERVICES_NAME="${TASK_1_SERVICES_NAME:-public-billing-service-748}"

printf "${BLUE}${BOLD}Task 2${RESET} ${WHITE}Staging Frontend Service${RESET} ${GREEN}[frontend-staging-service-657]${RESET}: "
read -r TASK_2_SERVICES_NAME
TASK_2_SERVICES_NAME="${TASK_2_SERVICES_NAME:-frontend-staging-service-657}"

printf "${MAGENTA}${BOLD}Task 3${RESET} ${WHITE}Private Billing Service${RESET} ${GREEN}[private-billing-service-473]${RESET}: "
read -r TASK_3_SERVICES_NAME
TASK_3_SERVICES_NAME="${TASK_3_SERVICES_NAME:-private-billing-service-473}"

printf "${YELLOW}${BOLD}Task 4${RESET} ${WHITE}Billing Service Account${RESET} ${GREEN}[billing-service-sa-699]${RESET}: "
read -r TASK_4_SERVICES_NAME
TASK_4_SERVICES_NAME="${TASK_4_SERVICES_NAME:-billing-service-sa-699}"

printf "${CYAN}${BOLD}Task 5${RESET} ${WHITE}Production Billing Service${RESET} ${GREEN}[billing-prod-service-311]${RESET}: "
read -r TASK_5_SERVICES_NAME
TASK_5_SERVICES_NAME="${TASK_5_SERVICES_NAME:-billing-prod-service-311}"

printf "${BLUE}${BOLD}Task 6${RESET} ${WHITE}Frontend Service Account${RESET} ${GREEN}[frontend-service-sa-122]${RESET}: "
read -r TASK_6_SERVICES_NAME
TASK_6_SERVICES_NAME="${TASK_6_SERVICES_NAME:-frontend-service-sa-122}"

printf "${MAGENTA}${BOLD}Task 7${RESET} ${WHITE}Production Frontend Service${RESET} ${GREEN}[frontend-prod-service-578]${RESET}: "
read -r TASK_7_SERVICES_NAME
TASK_7_SERVICES_NAME="${TASK_7_SERVICES_NAME:-frontend-prod-service-578}"

export PROJECT_ID

export REGION=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
    2>/dev/null || true)

export TASK_1_SERVICES_NAME
export TASK_2_SERVICES_NAME
export TASK_3_SERVICES_NAME
export TASK_4_SERVICES_NAME
export TASK_5_SERVICES_NAME
export TASK_6_SERVICES_NAME
export TASK_7_SERVICES_NAME

# ==============================================================
# CONFIG SUMMARY
# ==============================================================

section "LAB CONFIGURATION"

echo "${WHITE}Project ID              : ${GREEN}$PROJECT_ID${RESET}"
echo "${WHITE}Region                  : ${GREEN}$REGION${RESET}"
echo
echo "${WHITE}Task 1 Public Billing   : ${GREEN}$TASK_1_SERVICES_NAME${RESET}"
echo "${WHITE}Task 2 Staging Frontend : ${GREEN}$TASK_2_SERVICES_NAME${RESET}"
echo "${WHITE}Task 3 Private Billing  : ${GREEN}$TASK_3_SERVICES_NAME${RESET}"
echo "${WHITE}Task 4 Billing SA       : ${GREEN}$TASK_4_SERVICES_NAME${RESET}"
echo "${WHITE}Task 5 Prod Billing     : ${GREEN}$TASK_5_SERVICES_NAME${RESET}"
echo "${WHITE}Task 6 Frontend SA      : ${GREEN}$TASK_6_SERVICES_NAME${RESET}"
echo "${WHITE}Task 7 Prod Frontend    : ${GREEN}$TASK_7_SERVICES_NAME${RESET}"

echo
success "Input completed. Starting automatically..."

# ==============================================================
# GCLOUD CONFIG
# ==============================================================

section "CONFIGURE GCLOUD"

gcloud config set project "$PROJECT_ID" --quiet
gcloud config set run/region "$REGION" --quiet
gcloud config set run/platform managed --quiet

success "gcloud configured."

# ==============================================================
# ENABLE APIS
# ==============================================================

section "ENABLE REQUIRED APIS"

info "Enabling required Google Cloud APIs..."

gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

success "Required APIs enabled."

# ==============================================================
# SOURCE CODE
# ==============================================================

section "PREPARE PET THEORY SOURCE CODE"

cd "$HOME"

if [[ -d "$HOME/pet-theory/.git" ]]; then

    info "Existing pet-theory repository found."

    git -C "$HOME/pet-theory" fetch origin --quiet || true
    git -C "$HOME/pet-theory" reset --hard origin/main --quiet || true

else

    info "Cloning pet-theory repository..."

    git clone \
        https://github.com/rosera/pet-theory.git \
        "$HOME/pet-theory"
fi

[[ -d "$HOME/pet-theory/lab07" ]] || \
    die "pet-theory/lab07 was not found."

success "Pet Theory source code ready."

# ==============================================================
# TASK 1
# PUBLIC BILLING SERVICE
# ==============================================================

section "TASK 1 - PUBLIC BILLING SERVICE"

TASK_1_IMAGE="gcr.io/${PROJECT_ID}/billing-staging-api:0.1"

cd "$HOME/pet-theory/lab07/unit-api-billing"

info "Building image:"
echo "${WHITE}$TASK_1_IMAGE${RESET}"

gcloud builds submit \
    --tag="$TASK_1_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

success "Task 1 image built."

info "Deploying public Cloud Run service..."

gcloud run deploy "$TASK_1_SERVICES_NAME" \
    --image="$TASK_1_IMAGE" \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

wait_for_service "$TASK_1_SERVICES_NAME"

PUBLIC_BILLING_URL=$(get_service_url "$TASK_1_SERVICES_NAME")

export PUBLIC_BILLING_URL

success "Task 1 deployed successfully."

echo
echo "${WHITE}Public Billing URL:${RESET}"
echo "${GREEN}${BOLD}$PUBLIC_BILLING_URL${RESET}"
echo

info "Testing public Billing endpoint..."

HTTP_CODE=$(curl \
    -L \
    -s \
    -o /tmp/task1-response.txt \
    -w "%{http_code}" \
    "$PUBLIC_BILLING_URL" || true)

if [[ "$HTTP_CODE" =~ ^2 ]]; then
    success "Task 1 HTTP status: $HTTP_CODE"
else
    warn "Task 1 HTTP status: $HTTP_CODE"
fi

# ==============================================================
# TASK 2
# STAGING FRONTEND
# ==============================================================

section "TASK 2 - STAGING FRONTEND"

TASK_2_IMAGE="gcr.io/${PROJECT_ID}/frontend-staging:0.1"

cd "$HOME/pet-theory/lab07/staging-frontend-billing"

info "Building image:"
echo "${WHITE}$TASK_2_IMAGE${RESET}"

gcloud builds submit \
    --tag="$TASK_2_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

success "Task 2 image built."

info "Deploying staging frontend..."

gcloud run deploy "$TASK_2_SERVICES_NAME" \
    --image="$TASK_2_IMAGE" \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

wait_for_service "$TASK_2_SERVICES_NAME"

STAGING_FRONTEND_URL=$(get_service_url "$TASK_2_SERVICES_NAME")

export STAGING_FRONTEND_URL

success "Task 2 deployed successfully."

echo
echo "${WHITE}Staging Frontend URL:${RESET}"
echo "${GREEN}${BOLD}$STAGING_FRONTEND_URL${RESET}"
echo

HTTP_CODE=$(curl \
    -L \
    -s \
    -o /dev/null \
    -w "%{http_code}" \
    "$STAGING_FRONTEND_URL" || true)

if [[ "$HTTP_CODE" =~ ^2|^3 ]]; then
    success "Task 2 HTTP status: $HTTP_CODE"
else
    warn "Task 2 HTTP status: $HTTP_CODE"
fi

# ==============================================================
# TASK 3
# PRIVATE BILLING SERVICE
# ==============================================================

section "TASK 3 - PRIVATE BILLING SERVICE"

info "Deleting previous public Billing Service..."

if gcloud run services describe "$TASK_1_SERVICES_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    gcloud run services delete "$TASK_1_SERVICES_NAME" \
        --region="$REGION" \
        --platform=managed \
        --project="$PROJECT_ID" \
        --quiet

    success "$TASK_1_SERVICES_NAME deleted."

else

    warn "$TASK_1_SERVICES_NAME is already deleted."
fi

TASK_3_IMAGE="gcr.io/${PROJECT_ID}/billing-staging-api:0.2"

cd "$HOME/pet-theory/lab07/staging-api-billing"

info "Building image:"
echo "${WHITE}$TASK_3_IMAGE${RESET}"

gcloud builds submit \
    --tag="$TASK_3_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

success "Task 3 image built."

info "Deploying authenticated private Billing Service..."

gcloud run deploy "$TASK_3_SERVICES_NAME" \
    --image="$TASK_3_IMAGE" \
    --region="$REGION" \
    --platform=managed \
    --no-allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

# Remove public invoker if a previous deployment left one behind
gcloud run services remove-iam-policy-binding \
    "$TASK_3_SERVICES_NAME" \
    --region="$REGION" \
    --platform=managed \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1 || true

wait_for_service "$TASK_3_SERVICES_NAME"

BILLING_URL=$(get_service_url "$TASK_3_SERVICES_NAME")

export BILLING_URL

success "Task 3 deployed successfully."

echo
echo "${WHITE}Private Billing URL:${RESET}"
echo "${GREEN}${BOLD}$BILLING_URL${RESET}"
echo

info "Testing authenticated Billing endpoint..."

IDENTITY_TOKEN=$(gcloud auth print-identity-token)

HTTP_CODE=$(curl \
    -L \
    -s \
    -o /tmp/task3-response.txt \
    -w "%{http_code}" \
    -H "Authorization: Bearer ${IDENTITY_TOKEN}" \
    "$BILLING_URL" || true)

if [[ "$HTTP_CODE" =~ ^2 ]]; then
    success "Task 3 HTTP status: $HTTP_CODE"
else
    warn "Task 3 HTTP status: $HTTP_CODE"
fi

# ==============================================================
# TASK 4
# BILLING SERVICE ACCOUNT
# ==============================================================

section "TASK 4 - BILLING SERVICE ACCOUNT"

BILLING_SA_EMAIL="${TASK_4_SERVICES_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$BILLING_SA_EMAIL" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    warn "Billing Service Account already exists."

else

    info "Creating Billing Service Account..."

    gcloud iam service-accounts create "$TASK_4_SERVICES_NAME" \
        --display-name="Billing Service Cloud Run" \
        --project="$PROJECT_ID" \
        --quiet
fi

success "Task 4 completed."

echo "${WHITE}Service Account:${RESET}"
echo "${GREEN}$BILLING_SA_EMAIL${RESET}"

# Small propagation delay without user interaction
sleep 5

# ==============================================================
# TASK 5
# PRODUCTION BILLING SERVICE
# ==============================================================

section "TASK 5 - PRODUCTION BILLING SERVICE"

TASK_5_IMAGE="gcr.io/${PROJECT_ID}/billing-prod-api:0.1"

cd "$HOME/pet-theory/lab07/prod-api-billing"

info "Building image:"
echo "${WHITE}$TASK_5_IMAGE${RESET}"

gcloud builds submit \
    --tag="$TASK_5_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

success "Task 5 image built."

info "Deploying production Billing Service..."
info "Service Account: $BILLING_SA_EMAIL"

gcloud run deploy "$TASK_5_SERVICES_NAME" \
    --image="$TASK_5_IMAGE" \
    --service-account="$BILLING_SA_EMAIL" \
    --region="$REGION" \
    --platform=managed \
    --no-allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

gcloud run services remove-iam-policy-binding \
    "$TASK_5_SERVICES_NAME" \
    --region="$REGION" \
    --platform=managed \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1 || true

wait_for_service "$TASK_5_SERVICES_NAME"

PROD_BILLING_URL=$(get_service_url "$TASK_5_SERVICES_NAME")

export PROD_BILLING_URL

success "Task 5 deployed successfully."

echo
echo "${WHITE}Production Billing URL:${RESET}"
echo "${GREEN}${BOLD}$PROD_BILLING_URL${RESET}"
echo

info "Testing authenticated Production Billing endpoint..."

IDENTITY_TOKEN=$(gcloud auth print-identity-token)

HTTP_CODE=$(curl \
    -L \
    -s \
    -o /tmp/task5-response.txt \
    -w "%{http_code}" \
    -H "Authorization: Bearer ${IDENTITY_TOKEN}" \
    "$PROD_BILLING_URL" || true)

if [[ "$HTTP_CODE" =~ ^2 ]]; then
    success "Task 5 HTTP status: $HTTP_CODE"
else
    warn "Task 5 HTTP status: $HTTP_CODE"
fi

# ==============================================================
# TASK 6
# FRONTEND SERVICE ACCOUNT
# ==============================================================

section "TASK 6 - FRONTEND SERVICE ACCOUNT"

FRONTEND_SA_EMAIL="${TASK_6_SERVICES_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$FRONTEND_SA_EMAIL" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    warn "Frontend Service Account already exists."

else

    info "Creating Frontend Service Account..."

    gcloud iam service-accounts create "$TASK_6_SERVICES_NAME" \
        --display-name="Billing Service Cloud Run Invoker" \
        --project="$PROJECT_ID" \
        --quiet
fi

success "Frontend Service Account ready."

echo "${WHITE}Service Account:${RESET}"
echo "${GREEN}$FRONTEND_SA_EMAIL${RESET}"

sleep 5

info "Granting roles/run.invoker on Production Billing Service..."

gcloud run services add-iam-policy-binding \
    "$TASK_5_SERVICES_NAME" \
    --region="$REGION" \
    --platform=managed \
    --member="serviceAccount:${FRONTEND_SA_EMAIL}" \
    --role="roles/run.invoker" \
    --project="$PROJECT_ID" \
    --quiet

success "roles/run.invoker granted."

# ==============================================================
# TASK 7
# PRODUCTION FRONTEND
# ==============================================================

section "TASK 7 - PRODUCTION FRONTEND"

TASK_7_IMAGE="gcr.io/${PROJECT_ID}/frontend-prod:0.1"

cd "$HOME/pet-theory/lab07/prod-frontend-billing"

info "Building image:"
echo "${WHITE}$TASK_7_IMAGE${RESET}"

gcloud builds submit \
    --tag="$TASK_7_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

success "Task 7 image built."

info "Deploying Production Frontend..."
echo
echo "${WHITE}Frontend Service Account:${RESET}"
echo "${GREEN}$FRONTEND_SA_EMAIL${RESET}"
echo
echo "${WHITE}Billing URL:${RESET}"
echo "${GREEN}$PROD_BILLING_URL${RESET}"
echo

gcloud run deploy "$TASK_7_SERVICES_NAME" \
    --image="$TASK_7_IMAGE" \
    --service-account="$FRONTEND_SA_EMAIL" \
    --set-env-vars="BILLING_URL=${PROD_BILLING_URL}" \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

wait_for_service "$TASK_7_SERVICES_NAME"

FRONTEND_PROD_URL=$(get_service_url "$TASK_7_SERVICES_NAME")

export FRONTEND_PROD_URL

success "Task 7 deployed successfully."

echo
echo "${WHITE}Production Frontend URL:${RESET}"
echo "${GREEN}${BOLD}$FRONTEND_PROD_URL${RESET}"
echo

info "Testing Production Frontend..."

HTTP_CODE=$(curl \
    -L \
    -s \
    -o /tmp/task7-response.html \
    -w "%{http_code}" \
    "$FRONTEND_PROD_URL" || true)

if [[ "$HTTP_CODE" =~ ^2|^3 ]]; then
    success "Task 7 HTTP status: $HTTP_CODE"
else
    warn "Task 7 HTTP status: $HTTP_CODE"

    echo
    warn "Recent frontend logs:"

    gcloud run services logs read "$TASK_7_SERVICES_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --limit=20 \
        2>/dev/null || true
fi

# ==============================================================
# VERIFY SERVICE ACCOUNTS
# ==============================================================

section "VERIFY SERVICE ACCOUNTS"

echo "${CYAN}${BOLD}Billing Service Account${RESET}"

gcloud iam service-accounts describe "$BILLING_SA_EMAIL" \
    --project="$PROJECT_ID" \
    --format="table(
        email:label=EMAIL,
        displayName:label=DISPLAY_NAME
    )"

echo

echo "${CYAN}${BOLD}Frontend Service Account${RESET}"

gcloud iam service-accounts describe "$FRONTEND_SA_EMAIL" \
    --project="$PROJECT_ID" \
    --format="table(
        email:label=EMAIL,
        displayName:label=DISPLAY_NAME
    )"

# ==============================================================
# VERIFY CLOUD RUN
# ==============================================================

section "VERIFY CLOUD RUN SERVICES"

gcloud run services list \
    --region="$REGION" \
    --platform=managed \
    --project="$PROJECT_ID" \
    --format="table(
        metadata.name:label=SERVICE,
        status.url:label=URL,
        spec.template.spec.serviceAccountName:label=SERVICE_ACCOUNT
    )"

# ==============================================================
# VERIFY FRONTEND -> BILLING IAM
# ==============================================================

section "VERIFY BILLING INVOKER IAM"

gcloud run services get-iam-policy "$TASK_5_SERVICES_NAME" \
    --region="$REGION" \
    --platform=managed \
    --project="$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.role=roles/run.invoker" \
    --format="table(
        bindings.role:label=ROLE,
        bindings.members:label=MEMBER
    )"

# ==============================================================
# RESULT
# ==============================================================

echo
echo "${BG_GREEN}${BLACK}${BOLD}==============================================================${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}                 EXECUTION COMPLETED                           ${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}                     ePlus.DEV                                 ${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}==============================================================${RESET}"
echo

echo "${CYAN}${BOLD}PROJECT${RESET}"
echo "$PROJECT_ID"

echo
echo "${CYAN}${BOLD}REGION${RESET}"
echo "$REGION"

echo
echo "${CYAN}${BOLD}TASK 3 - PRIVATE BILLING${RESET}"
echo "$BILLING_URL"

echo
echo "${CYAN}${BOLD}TASK 5 - PRODUCTION BILLING${RESET}"
echo "$PROD_BILLING_URL"

echo
echo "${CYAN}${BOLD}TASK 7 - PRODUCTION FRONTEND${RESET}"
echo "${GREEN}${BOLD}$FRONTEND_PROD_URL${RESET}"

echo
echo "${MAGENTA}${BOLD}© ePlus.DEV${RESET}"
echo