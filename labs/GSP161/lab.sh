#!/bin/bash
set -Eeuo pipefail

# -----------------------------
# ePlus.DEV Cloud Lab Setup Script
# Fixed version
# -----------------------------

# Color variables
BLACK=$(tput setaf 0 || true)
RED=$(tput setaf 1 || true)
GREEN=$(tput setaf 2 || true)
YELLOW=$(tput setaf 3 || true)
BLUE=$(tput setaf 4 || true)
MAGENTA=$(tput setaf 5 || true)
CYAN=$(tput setaf 6 || true)
WHITE=$(tput setaf 7 || true)

BG_RED=$(tput setab 1 || true)
BG_GREEN=$(tput setab 2 || true)
BG_BLUE=$(tput setab 4 || true)

BOLD=$(tput bold || true)
RESET=$(tput sgr0 || true)

TEXT_COLORS=("$RED" "$GREEN" "$YELLOW" "$BLUE" "$MAGENTA" "$CYAN")
BG_COLORS=("$BG_RED" "$BG_GREEN" "$BG_BLUE")

RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

log() {
  echo "${BOLD}${CYAN}[$(date '+%H:%M:%S')] $*${RESET}"
}

success() {
  echo "${BOLD}${GREEN}✅ $*${RESET}"
}

warn() {
  echo "${BOLD}${YELLOW}⚠️  $*${RESET}"
}

error() {
  echo "${BOLD}${RED}❌ $*${RESET}"
}

die() {
  error "$*"
  exit 1
}

run() {
  echo "${BOLD}${BLUE}> $*${RESET}"
  "$@"
}

region_from_zone() {
  echo "$1" | sed 's/-[a-z]$//'
}

get_vm_zone() {
  local vm_name="$1"

  gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="name=($vm_name)" \
    --format="value(zone)" | awk -F/ 'NR==1{print $NF}'
}

wait_for_ssh() {
  local vm_name="$1"
  local zone="$2"

  log "Waiting for SSH on ${vm_name} (${zone})..."

  for i in {1..20}; do
    if gcloud compute ssh "$vm_name" \
      --project="$PROJECT_ID" \
      --zone="$zone" \
      --quiet \
      --command="echo SSH_OK" >/dev/null 2>&1; then
      success "SSH is ready on ${vm_name}"
      return 0
    fi

    echo "Waiting SSH... attempt $i/20"
    sleep 10
  done

  die "SSH is not ready on ${vm_name} after waiting."
}

ensure_subnet_exists() {
  local region="$1"
  local subnet="subnet-${region}"

  if ! gcloud compute networks subnets describe "$subnet" \
    --project="$PROJECT_ID" \
    --region="$region" >/dev/null 2>&1; then
    warn "Subnet ${subnet} was not found in region ${region}."
    echo
    echo "Available subnets:"
    gcloud compute networks subnets list \
      --project="$PROJECT_ID" \
      --format="table(name,region,network,range)"
    echo
    die "Please use a zone whose region has subnet ${subnet}, or create the subnet first."
  fi

  success "Subnet exists: ${subnet}"
}

create_instance_if_missing() {
  local vm_name="$1"
  local zone="$2"
  local machine_type="${3:-e2-standard-2}"
  local tags="${4:-ssh,http,rules}"

  local region
  region=$(region_from_zone "$zone")
  local subnet="subnet-${region}"

  ensure_subnet_exists "$region"

  local existing_zone
  existing_zone=$(get_vm_zone "$vm_name" || true)

  if [[ -n "$existing_zone" ]]; then
    success "Instance ${vm_name} already exists in zone ${existing_zone}. Skipping create."
    return 0
  fi

  log "Creating instance ${vm_name} in ${zone} using ${subnet}"

  run gcloud compute instances create "$vm_name" \
    --project="$PROJECT_ID" \
    --zone="$zone" \
    --subnet="$subnet" \
    --machine-type="$machine_type" \
    --tags="$tags"

  local created_zone
  created_zone=$(get_vm_zone "$vm_name" || true)

  if [[ -z "$created_zone" ]]; then
    die "Instance ${vm_name} was not created. Please check the error above."
  fi

  success "Created ${vm_name} in ${created_zone}"
}

install_tools() {
  local vm_name="$1"

  local zone
  zone=$(get_vm_zone "$vm_name" || true)

  if [[ -z "$zone" ]]; then
    die "Instance ${vm_name} was not found in project ${PROJECT_ID}."
  fi

  log "Installing tools on ${vm_name} in zone ${zone}"

  cat > prepare_disk.sh <<'EOF_END'
#!/bin/bash
set -Eeuo pipefail

sudo apt-get update
sudo apt-get -y install traceroute mtr tcpdump iperf whois host dnsutils siege

echo "Tools installed successfully."
EOF_END

  run gcloud compute scp prepare_disk.sh "${vm_name}:/tmp/prepare_disk.sh" \
    --project="$PROJECT_ID" \
    --zone="$zone" \
    --quiet

  run gcloud compute ssh "$vm_name" \
    --project="$PROJECT_ID" \
    --zone="$zone" \
    --quiet \
    --command="bash /tmp/prepare_disk.sh"
}

start_iperf_server() {
  local vm_name="$1"

  local zone
  zone=$(get_vm_zone "$vm_name" || true)

  if [[ -z "$zone" ]]; then
    die "Instance ${vm_name} was not found in project ${PROJECT_ID}."
  fi

  log "Starting iperf server on ${vm_name}"

  cat > prepare_disk.sh <<'EOF_END'
#!/bin/bash
set -Eeuo pipefail

nohup iperf -s > ~/iperf-server.log 2>&1 &
echo "iperf server started."
EOF_END

  run gcloud compute scp prepare_disk.sh "${vm_name}:/tmp/prepare_disk.sh" \
    --project="$PROJECT_ID" \
    --zone="$zone" \
    --quiet

  run gcloud compute ssh "$vm_name" \
    --project="$PROJECT_ID" \
    --zone="$zone" \
    --quiet \
    --command="bash /tmp/prepare_disk.sh"
}

run_iperf_client() {
  local client_vm="$1"
  local server_vm="$2"

  local client_zone
  client_zone=$(get_vm_zone "$client_vm" || true)

  local server_zone
  server_zone=$(get_vm_zone "$server_vm" || true)

  if [[ -z "$client_zone" ]]; then
    die "Client instance ${client_vm} was not found."
  fi

  if [[ -z "$server_zone" ]]; then
    die "Server instance ${server_vm} was not found."
  fi

  log "Running iperf client on ${client_vm} to ${server_vm}.${server_zone}"

  cat > prepare_disk.sh <<EOF_END
#!/bin/bash
set -Eeuo pipefail

sudo apt-get update
sudo apt-get -y install traceroute mtr tcpdump iperf whois host dnsutils siege

iperf -c ${server_vm}.${server_zone}
EOF_END

  run gcloud compute scp prepare_disk.sh "${client_vm}:/tmp/prepare_disk.sh" \
    --project="$PROJECT_ID" \
    --zone="$client_zone" \
    --quiet

  run gcloud compute ssh "$client_vm" \
    --project="$PROJECT_ID" \
    --zone="$client_zone" \
    --quiet \
    --command="bash /tmp/prepare_disk.sh"
}

cleanup_local_files() {
  for file in *; do
    if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
      if [[ -f "$file" ]]; then
        rm -f "$file"
        echo "File removed: $file"
      fi
    fi
  done

  rm -f prepare_disk.sh
}

clear || true

echo "${BG_BLUE}${BOLD}${WHITE}╔════════════════════════════════════════════════════════╗${RESET}"
echo "${BG_BLUE}${BOLD}${WHITE}   Welcome to ePlus.DEV Cloud Lab Setup Script          ${RESET}"
echo "${BG_BLUE}${BOLD}${WHITE}╚════════════════════════════════════════════════════════╝${RESET}"
echo
echo "${GREEN}${BOLD}This script will help you set up your cloud lab environment${RESET}"
echo "${CYAN}For more tutorials, visit: https://eplus.dev${RESET}"
echo
echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Execution${RESET}"
echo

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"

if [[ -z "$PROJECT_ID" ]]; then
  die "PROJECT_ID is empty. Please run: gcloud config set project YOUR_PROJECT_ID"
fi

gcloud config set project "$PROJECT_ID" >/dev/null

log "Using project: ${PROJECT_ID}"

ZONE_1=$(gcloud compute project-info describe \
  --project="$PROJECT_ID" \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)

REGION_1=$(gcloud compute project-info describe \
  --project="$PROJECT_ID" \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)

if [[ -z "$ZONE_1" ]]; then
  warn "Default zone metadata is empty."
  read -r -p "$(echo -e "${CYAN}${BOLD}Enter ZONE_1 (e.g., us-west1-b): ${RESET}")" ZONE_1
fi

if [[ -z "$REGION_1" ]]; then
  REGION_1=$(region_from_zone "$ZONE_1")
fi

gcloud config set compute/zone "$ZONE_1" >/dev/null
gcloud config set compute/region "$REGION_1" >/dev/null

echo
echo "${YELLOW}${BOLD}Please enter values for the following:${RESET}"
echo

read -r -p "$(echo -e "${CYAN}${BOLD}Enter ZONE_2 (e.g., us-central1-a): ${RESET}")" ZONE_2
REGION_2=$(region_from_zone "$ZONE_2")

echo

read -r -p "$(echo -e "${CYAN}${BOLD}Enter ZONE_3 (e.g., us-central1-b): ${RESET}")" ZONE_3
REGION_3=$(region_from_zone "$ZONE_3")

echo
echo "${BOLD}${MAGENTA}Configuration summary:${RESET}"
echo "PROJECT_ID = ${PROJECT_ID}"
echo "ZONE_1     = ${ZONE_1}"
echo "REGION_1   = ${REGION_1}"
echo "ZONE_2     = ${ZONE_2}"
echo "REGION_2   = ${REGION_2}"
echo "ZONE_3     = ${ZONE_3}"
echo "REGION_3   = ${REGION_3}"
echo

ensure_subnet_exists "$REGION_1"
ensure_subnet_exists "$REGION_2"
ensure_subnet_exists "$REGION_3"

create_instance_if_missing "us-test-01" "$ZONE_1" "e2-standard-2" "ssh,http,rules"
create_instance_if_missing "us-test-02" "$ZONE_2" "e2-standard-2" "ssh,http,rules"
create_instance_if_missing "us-test-03" "$ZONE_3" "e2-standard-2" "ssh,http,rules"
create_instance_if_missing "us-test-04" "$ZONE_1" "e2-standard-2" "ssh,http"

wait_for_ssh "us-test-01" "$(get_vm_zone us-test-01)"
wait_for_ssh "us-test-02" "$(get_vm_zone us-test-02)"
wait_for_ssh "us-test-04" "$(get_vm_zone us-test-04)"

install_tools "us-test-01"
install_tools "us-test-02"

start_iperf_server "us-test-01"
run_iperf_client "us-test-02" "us-test-01"

install_tools "us-test-04"

echo
echo "${BG_GREEN}${BOLD}${BLACK}╔════════════════════════════════════════════════════════╗${RESET}"
echo "${BG_GREEN}${BOLD}${BLACK}   Congratulations! Lab Setup Completed Successfully!   ${RESET}"
echo "${BG_GREEN}${BOLD}${BLACK}╚════════════════════════════════════════════════════════╝${RESET}"
echo
echo "${MAGENTA}${BOLD}Thank you for using ePlus.DEV Cloud Lab Setup Script${RESET}"
echo "${CYAN}${BOLD}For more tutorials and cloud computing content, subscribe to:${RESET}"
echo "${BLUE}https://eplus.dev${RESET}"
echo

cleanup_local_files