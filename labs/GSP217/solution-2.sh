#!/usr/bin/env bash
set -euo pipefail

# ======================================================
#  ePlus.DEV - Proprietary Script
# ======================================================
#  Copyright (c) 2026 ePlus.DEV
#  All rights reserved.
#
#  This software is the confidential and proprietary
#  information of ePlus.DEV.
#  Unauthorized copying, modification, distribution,
#  or use of this software is strictly prohibited.
# ======================================================


# ================= COLORS =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

YEAR="$(date +%Y)"

# ================= CONFIG =================
BUCKET_LOCATION="US"        # US / EU / ASIA (chọn xa bạn)
TTL_SECONDS=60

LB_NAME="cdn-lb"
BACKEND_BUCKET_NAME="cdn-backend-bucket"
URL_MAP_NAME="cdn-url-map"
HTTP_PROXY_NAME="cdn-http-proxy"
FWD_RULE_NAME="cdn-forwarding-rule"

# ================= FUNCTIONS =================
print_banner() {
  echo -e "${MAGENTA}${BOLD}"
  echo "============================================================"
  echo "              ePlus.DEV - Cloud CDN Lab Script              "
  echo "============================================================"
  echo -e "${NC}"
}

print_copyright() {
  echo -e "${GREEN}${BOLD}© ${YEAR} ePlus.DEV${NC}"
  echo -e "${YELLOW}All rights reserved.${NC}"
  echo -e "${CYAN}Proprietary & Confidential software.${NC}"
  echo -e "${CYAN}Unauthorized use is strictly prohibited.${NC}"
  echo
}

log() {
  echo -e "${CYAN}➜ $1${NC}"
}

success() {
  echo -e "${GREEN}✔ $1${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
  echo -e "${RED}✖ $1${NC}"
  exit 1
}

# ================= START =================
clear
print_banner
print_copyright

PROJECT_ID="$(gcloud config get-value project -q)"
[[ -z "$PROJECT_ID" ]] && error "No active GCP project found"

success "Using project: $PROJECT_ID"

RAND="$(date +%s)-$RANDOM"
BUCKET_NAME="eplus-cdn-${PROJECT_ID//:/-}-${RAND}"
BUCKET_URI="gs://${BUCKET_NAME}"

echo
log "Bucket name: ${BUCKET_NAME}"
log "Bucket location: ${BUCKET_LOCATION}"
echo

# ================= TASK 1 =================
log "Creating Cloud Storage bucket..."
gsutil mb -p "$PROJECT_ID" -l "$BUCKET_LOCATION" "$BUCKET_URI"
success "Bucket created"

log "Copying image to bucket..."
gsutil cp gs://spls/gsp217/cdn/cdn.png "$BUCKET_URI/cdn.png"
success "Image uploaded"

log "Making bucket public (allUsers: Storage Object Viewer)..."
gsutil iam ch allUsers:objectViewer "$BUCKET_URI"
success "Bucket is now public"

PUBLIC_GCS_URL="https://storage.googleapis.com/${BUCKET_NAME}/cdn.png"
success "Public URL: $PUBLIC_GCS_URL"

# ================= TASK 2 =================
echo
log "Creating backend bucket with Cloud CDN enabled..."
gcloud compute backend-buckets create "$BACKEND_BUCKET_NAME" \
  --gcs-bucket-name="$BUCKET_NAME" \
  --enable-cdn \
  --cache-mode=CACHE_ALL_STATIC \
  --default-ttl="$TTL_SECONDS" \
  --client-ttl="$TTL_SECONDS" \
  --max-ttl="$TTL_SECONDS" \
  --quiet

success "Backend bucket created (Cloud CDN ON)"

log "Creating URL map..."
gcloud compute url-maps create "$URL_MAP_NAME" \
  --default-backend-bucket="$BACKEND_BUCKET_NAME" \
  --quiet
success "URL map created"

log "Creating HTTP proxy..."
gcloud compute target-http-proxies create "$HTTP_PROXY_NAME" \
  --url-map="$URL_MAP_NAME" \
  --quiet
success "HTTP proxy created"

log "Creating global forwarding rule (port 80)..."
gcloud compute forwarding-rules create "$FWD_RULE_NAME" \
  --global \
  --target-http-proxy="$HTTP_PROXY_NAME" \
  --ports=80 \
  --quiet
success "Forwarding rule created"

LB_IP_ADDRESS="$(gcloud compute forwarding-rules describe "$FWD_RULE_NAME" \
  --global --format='value(IPAddress)')"

echo
success "Load Balancer IP: ${LB_IP_ADDRESS}"
success "CDN URL: http://${LB_IP_ADDRESS}/cdn.png"

# ================= TASK 3 =================
echo
log "Testing CDN cache (first hit = MISS, next = HIT)..."
for i in {1..3}; do
  curl -s -w "Request $i → %{time_total}s\n" -o /dev/null \
    "http://${LB_IP_ADDRESS}/cdn.png"
done

echo
warn "Run again to generate more Cloud CDN logs if needed"
for i in {1..3}; do
  curl -s -w "Request $i → %{time_total}s\n" -o /dev/null \
    "http://${LB_IP_ADDRESS}/cdn.png"
done

# ================= DONE =================
echo
echo -e "${MAGENTA}${BOLD}============================================================${NC}"
success "Cloud CDN lab setup completed successfully"
echo -e "${GRAY}Check Logs Explorer → Application Load Balancer → CDN logs${NC}"
echo -e "${MAGENTA}${BOLD}============================================================${NC}"