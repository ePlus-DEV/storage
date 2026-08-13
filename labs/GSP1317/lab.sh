#!/usr/bin/env bash
set -Eeuo pipefail

# ================================================================
#  Network Connectivity Center + Cloud SQL PSC Lab
#  Automated solution
#  © ePlus.DEV
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

section() {
  echo
  echo -e "${BLUE}${BOLD}======================================================================${NC}"
  echo -e "${BLUE}${BOLD}$*${NC}"
  echo -e "${BLUE}${BOLD}======================================================================${NC}"
}

echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║            NETWORK CONNECTIVITY CENTER + CLOUD SQL             ║
║                    PRIVATE SERVICE CONNECT                     ║
║                         © ePlus.DEV                             ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ----------------------------------------------------------------
# CONFIG
# ----------------------------------------------------------------

HUB="ncc-hub"

VPC1="vpc1-ncc"
VPC2="vpc2-ncc"

SPOKE1="vpc1-spoke1"
SPOKE2="vpc2-spoke2"

EXCLUDE1="10.1.2.0/24"
EXCLUDE2="10.3.3.0/24"

PSC_ADDRESS_NAME="cloudsql-psc"
PSC_FORWARDING_RULE="cloudsql-psc-ep"

DNS_ZONE="cloudsql-dns"

CLIENT_VM="cloudsql-client"
VM1="vm1-vpc1-ncc"
VM2="vm2-vpc2-ncc"

# ----------------------------------------------------------------
# [1/8] Detect environment
# ----------------------------------------------------------------

section "[1/8] Detecting Google Cloud environment"

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  die "Unable to detect Project ID. Open Cloud Shell from the lab project first."
fi

ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"

SUBNET="vpc2-ncc-subnet1"

REGION="$(
  gcloud compute networks subnets list \
    --project="$PROJECT" \
    --filter="name=$SUBNET" \
    --format='value(region.basename())' \
    --limit=1 2>/dev/null || true
)"

[[ -n "$REGION" ]] || REGION="us-west1"

echo "Project : $PROJECT"
echo "Account : $ACCOUNT"
echo "Region  : $REGION"
echo "Subnet  : $SUBNET"

gcloud config set project "$PROJECT" >/dev/null

ok "Google Cloud environment detected."

# ----------------------------------------------------------------
# [2/8] Enable APIs
# ----------------------------------------------------------------

section "[2/8] Enabling required APIs"

info "Enabling Network Connectivity, Compute, Cloud SQL and Cloud DNS APIs..."

gcloud services enable \
  networkconnectivity.googleapis.com \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  dns.googleapis.com \
  --project="$PROJECT" \
  --quiet

ok "Required APIs enabled."

# ----------------------------------------------------------------
# [3/8] Task 1 - NCC Hub
# ----------------------------------------------------------------

section "[3/8] TASK 1 - Creating NCC Hub"

if gcloud network-connectivity hubs describe "$HUB" \
    --project="$PROJECT" >/dev/null 2>&1; then

  ok "NCC Hub already exists: $HUB"

else
  info "Creating NCC Hub: $HUB"

  gcloud network-connectivity hubs create "$HUB" \
    --project="$PROJECT"

  ok "NCC Hub created."
fi

echo
gcloud network-connectivity hubs describe "$HUB" \
  --project="$PROJECT" \
  --format="table(name.basename(),state,createTime)"

# ----------------------------------------------------------------
# [4/8] Task 2 - VPC spokes
# ----------------------------------------------------------------

section "[4/8] TASK 2 - Configuring VPC spokes"

# Recreate spokes so rerunning the script always fixes their config.

if gcloud network-connectivity spokes describe "$SPOKE1" \
    --global \
    --project="$PROJECT" >/dev/null 2>&1; then

  warn "$SPOKE1 already exists - recreating with correct configuration..."

  gcloud network-connectivity spokes delete "$SPOKE1" \
    --global \
    --project="$PROJECT" \
    --quiet
fi

info "Creating $SPOKE1"

gcloud network-connectivity spokes linked-vpc-network create "$SPOKE1" \
  --hub="$HUB" \
  --vpc-network="$VPC1" \
  --exclude-export-ranges="$EXCLUDE1" \
  --global \
  --project="$PROJECT"

ok "$SPOKE1 configured with exclude range $EXCLUDE1"


if gcloud network-connectivity spokes describe "$SPOKE2" \
    --global \
    --project="$PROJECT" >/dev/null 2>&1; then

  warn "$SPOKE2 already exists - recreating with correct configuration..."

  gcloud network-connectivity spokes delete "$SPOKE2" \
    --global \
    --project="$PROJECT" \
    --quiet
fi

info "Creating $SPOKE2"

gcloud network-connectivity spokes linked-vpc-network create "$SPOKE2" \
  --hub="$HUB" \
  --vpc-network="$VPC2" \
  --exclude-export-ranges="$EXCLUDE2" \
  --global \
  --project="$PROJECT"

ok "$SPOKE2 configured with exclude range $EXCLUDE2"

echo
info "NCC default routing table:"

gcloud network-connectivity hubs route-tables routes list \
  --hub="$HUB" \
  --route-table=default \
  --project="$PROJECT" \
  --format="table(ipCidrRange,nextHopVpcNetwork.basename(),state)" \
  2>/dev/null || true

ok "TASK 2 complete."

# ----------------------------------------------------------------
# [5/8] Task 3 - Verify VPC connectivity
# ----------------------------------------------------------------

section "[5/8] TASK 3 - Checking VPC connectivity"

VM1_ZONE="$(
  gcloud compute instances list \
    --project="$PROJECT" \
    --filter="name=$VM1" \
    --format='value(zone.basename())' \
    --limit=1 2>/dev/null || true
)"

VM2_ZONE="$(
  gcloud compute instances list \
    --project="$PROJECT" \
    --filter="name=$VM2" \
    --format='value(zone.basename())' \
    --limit=1 2>/dev/null || true
)"

VM1_IP=""

if [[ -n "$VM1_ZONE" ]]; then
  VM1_IP="$(
    gcloud compute instances describe "$VM1" \
      --zone="$VM1_ZONE" \
      --project="$PROJECT" \
      --format='value(networkInterfaces[0].networkIP)' \
      2>/dev/null || true
  )"
fi

if [[ -n "$VM1_IP" && -n "$VM2_ZONE" ]]; then

  echo "Source      : $VM2"
  echo "Destination : $VM1 ($VM1_IP)"

  info "Sending ICMP packets through NCC..."

  if gcloud compute ssh "$VM2" \
      --zone="$VM2_ZONE" \
      --project="$PROJECT" \
      --tunnel-through-iap \
      --quiet \
      --command="ping -c 4 '$VM1_IP'" 2>/dev/null; then

    ok "VPC1 ↔ VPC2 connectivity verified."
  else
    warn "Automated SSH/ping could not be completed."
    warn "This does not stop the remaining graded tasks."
  fi

else
  warn "VM information could not be detected; skipping optional ping test."
fi

# ----------------------------------------------------------------
# [6/8] Task 4 - Private Service Connect
# ----------------------------------------------------------------

section "[6/8] TASK 4 - Setting up Private Service Connect"

SUBNET_CIDR="$(
  gcloud compute networks subnets describe "$SUBNET" \
    --region="$REGION" \
    --project="$PROJECT" \
    --format='value(ipCidrRange)'
)"

[[ -n "$SUBNET_CIDR" ]] || die "Could not determine subnet CIDR."

echo "Subnet CIDR : $SUBNET_CIDR"

# ------------------------------------------------------------
# Find Cloud SQL instance
# ------------------------------------------------------------

mapfile -t SQL_INSTANCES < <(
  gcloud sql instances list \
    --project="$PROJECT" \
    --format='value(name)' 2>/dev/null
)

SQL_INSTANCE="${SQL_INSTANCES[0]:-}"

[[ -n "$SQL_INSTANCE" ]] || die "No Cloud SQL instance found."

echo "Cloud SQL   : $SQL_INSTANCE"

info "Reading Cloud SQL PSC information..."

PSC_ATTACHMENT="$(
  gcloud sql instances describe "$SQL_INSTANCE" \
    --project="$PROJECT" \
    --format='value(pscServiceAttachmentLink)' \
    2>/dev/null || true
)"

DNS_NAME="$(
  gcloud sql instances describe "$SQL_INSTANCE" \
    --project="$PROJECT" \
    --format='value(dnsName)' \
    2>/dev/null || true
)"

[[ -n "$PSC_ATTACHMENT" ]] ||
  die "Cloud SQL pscServiceAttachmentLink is empty."

[[ -n "$DNS_NAME" ]] ||
  die "Cloud SQL dnsName is empty."

# Ensure FQDN
if [[ "$DNS_NAME" != *. ]]; then
  DNS_NAME="${DNS_NAME}."
fi

echo "PSC attachment : $PSC_ATTACHMENT"
echo "Cloud SQL DNS  : $DNS_NAME"

# ------------------------------------------------------------
# Reserve PSC IP
# ------------------------------------------------------------

PSC_IP=""

if gcloud compute addresses describe "$PSC_ADDRESS_NAME" \
    --region="$REGION" \
    --project="$PROJECT" >/dev/null 2>&1; then

  PSC_IP="$(
    gcloud compute addresses describe "$PSC_ADDRESS_NAME" \
      --region="$REGION" \
      --project="$PROJECT" \
      --format='value(address)'
  )"

  ok "Existing PSC IP reservation found: $PSC_IP"

else

  info "Automatically searching for a free IP inside $SUBNET_CIDR..."

  mapfile -t PSC_CANDIDATES < <(
    python3 - "$SUBNET_CIDR" <<'PY'
import ipaddress
import sys

network = ipaddress.ip_network(sys.argv[1], strict=False)

# Start away from common VM addresses.
offsets = list(range(10, 250)) + list(range(4, 10))

for offset in offsets:
    try:
        ip = network.network_address + offset
    except Exception:
        continue

    if ip >= network.broadcast_address:
        continue

    if ip not in network:
        continue

    print(ip)
PY
  )

  TMP_LOG="/tmp/cloudsql-psc-address.log"
  : > "$TMP_LOG"

  for candidate in "${PSC_CANDIDATES[@]}"; do

    printf "\r${CYAN}→${NC} Trying PSC IP %-15s" "$candidate"

    if gcloud compute addresses create "$PSC_ADDRESS_NAME" \
        --project="$PROJECT" \
        --region="$REGION" \
        --subnet="$SUBNET" \
        --addresses="$candidate" \
        --quiet \
        >"$TMP_LOG" 2>&1; then

      PSC_IP="$candidate"
      echo
      ok "Reserved free PSC address: $PSC_IP"
      break
    fi
  done

  echo

  if [[ -z "$PSC_IP" ]]; then
    cat "$TMP_LOG" || true
    die "Could not reserve an available PSC IP."
  fi
fi

echo "PSC IP        : $PSC_IP"

# ------------------------------------------------------------
# Forwarding Rule
# ------------------------------------------------------------

if gcloud compute forwarding-rules describe "$PSC_FORWARDING_RULE" \
    --region="$REGION" \
    --project="$PROJECT" >/dev/null 2>&1; then

  warn "Existing PSC forwarding rule found. Recreating it..."

  gcloud compute forwarding-rules delete "$PSC_FORWARDING_RULE" \
    --region="$REGION" \
    --project="$PROJECT" \
    --quiet
fi

info "Creating Private Service Connect endpoint..."

gcloud compute forwarding-rules create "$PSC_FORWARDING_RULE" \
  --address="$PSC_ADDRESS_NAME" \
  --project="$PROJECT" \
  --region="$REGION" \
  --network="$VPC2" \
  --target-service-attachment="$PSC_ATTACHMENT" \
  --allow-psc-global-access

ok "PSC forwarding rule created."

# ------------------------------------------------------------
# Wait for ACCEPTED
# ------------------------------------------------------------

info "Waiting for PSC connection to become ACCEPTED..."

PSC_STATUS=""

for attempt in $(seq 1 40); do

  PSC_STATUS="$(
    gcloud compute forwarding-rules describe "$PSC_FORWARDING_RULE" \
      --project="$PROJECT" \
      --region="$REGION" \
      --format='value(pscConnectionStatus)' \
      2>/dev/null || true
  )"

  printf "\r${CYAN}→${NC} PSC status: %-16s check %02d/40" \
    "${PSC_STATUS:-PENDING}" "$attempt"

  if [[ "$PSC_STATUS" == "ACCEPTED" ]]; then
    echo
    ok "Private Service Connect status: ACCEPTED"
    break
  fi

  if [[ "$PSC_STATUS" == "REJECTED" ||
        "$PSC_STATUS" == "CLOSED" ||
        "$PSC_STATUS" == "NEEDS_ATTENTION" ]]; then
    echo
    die "PSC connection status: $PSC_STATUS"
  fi

  sleep 5
done

echo

[[ "$PSC_STATUS" == "ACCEPTED" ]] ||
  die "PSC endpoint did not reach ACCEPTED state."

# ------------------------------------------------------------
# Cloud DNS private zone
# ------------------------------------------------------------

DNS_SUFFIX="${REGION}.sql.goog."

if gcloud dns managed-zones describe "$DNS_ZONE" \
    --project="$PROJECT" >/dev/null 2>&1; then

  ok "Private DNS zone already exists: $DNS_ZONE"

else

  info "Creating private DNS zone: $DNS_SUFFIX"

  gcloud dns managed-zones create "$DNS_ZONE" \
    --project="$PROJECT" \
    --description="DNS zone for the Cloud SQL instances" \
    --dns-name="$DNS_SUFFIX" \
    --networks="$VPC2" \
    --visibility=private

  ok "Private DNS zone created."
fi

# ------------------------------------------------------------
# DNS A record
# ------------------------------------------------------------

if gcloud dns record-sets describe "$DNS_NAME" \
    --project="$PROJECT" \
    --zone="$DNS_ZONE" \
    --type=A >/dev/null 2>&1; then

  info "Updating existing Cloud SQL DNS A record..."

  gcloud dns record-sets update "$DNS_NAME" \
    --project="$PROJECT" \
    --zone="$DNS_ZONE" \
    --type=A \
    --ttl=300 \
    --rrdatas="$PSC_IP"

else

  info "Creating Cloud SQL DNS A record..."

  gcloud dns record-sets create "$DNS_NAME" \
    --project="$PROJECT" \
    --zone="$DNS_ZONE" \
    --type=A \
    --ttl=300 \
    --rrdatas="$PSC_IP"
fi

ok "DNS record configured:"
echo "  $DNS_NAME -> $PSC_IP"

# ----------------------------------------------------------------
# [7/8] Task 5 - Connect to Cloud SQL
# ----------------------------------------------------------------

section "[7/8] TASK 5 - Connecting to Cloud SQL through PSC"

CLIENT_ZONE="$(
  gcloud compute instances list \
    --project="$PROJECT" \
    --filter="name=$CLIENT_VM" \
    --format='value(zone.basename())' \
    --limit=1 2>/dev/null || true
)"

[[ -n "$CLIENT_ZONE" ]] ||
  die "Unable to find zone for $CLIENT_VM."

echo "Client VM : $CLIENT_VM"
echo "Zone      : $CLIENT_ZONE"
echo "DB host   : ${DNS_NAME%.}"

DB_HOST="${DNS_NAME%.}"

REMOTE_SCRIPT=$(cat <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail

export PGPASSWORD="changeme"

DB_HOST="__DB_HOST__"

echo
echo "============================================================"
echo " Cloud SQL connectivity test"
echo "============================================================"
echo "Host: $DB_HOST"
echo

CONNECTED=0

for attempt in $(seq 1 36); do

    DNS_OK=0
    DB_OK=0

    if getent hosts "$DB_HOST" >/dev/null 2>&1; then
        DNS_OK=1
    fi

    if [[ "$DNS_OK" == "1" ]]; then
        if psql \
            "sslmode=disable dbname=postgres user=postgres host=$DB_HOST connect_timeout=5" \
            -tAc "SELECT 1;" >/dev/null 2>&1; then
            DB_OK=1
        fi
    fi

    printf "\r→ DNS/Cloud SQL readiness check %02d/36" "$attempt"

    if [[ "$DB_OK" == "1" ]]; then
        echo
        echo "✓ Connected to Cloud SQL successfully."
        CONNECTED=1
        break
    fi

    sleep 5
done

echo

if [[ "$CONNECTED" != "1" ]]; then
    echo "✗ Could not establish Cloud SQL connection." >&2
    exit 1
fi

PSQL_POSTGRES="sslmode=disable dbname=postgres user=postgres host=$DB_HOST"
PSQL_COMPANY="sslmode=disable dbname=company user=postgres host=$DB_HOST"

echo
echo "Checking database company..."

DB_EXISTS="$(
    psql "$PSQL_POSTGRES" \
        -tAc "SELECT 1 FROM pg_database WHERE datname='company';" \
        | tr -d '[:space:]'
)"

if [[ "$DB_EXISTS" != "1" ]]; then
    echo "→ Creating database company..."

    psql "$PSQL_POSTGRES" \
        -v ON_ERROR_STOP=1 \
        -c "CREATE DATABASE company;"

    echo "✓ Database company created."
else
    echo "✓ Database company already exists."
fi

echo
echo "Creating employees table and lab data..."

psql "$PSQL_COMPANY" -v ON_ERROR_STOP=1 <<'SQL'

CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    first VARCHAR(255) NOT NULL,
    last VARCHAR(255) NOT NULL,
    salary DECIMAL (10, 2)
);

TRUNCATE TABLE employees RESTART IDENTITY;

INSERT INTO employees (first, last, salary) VALUES
    ('Max', 'Mustermann', 5000.00),
    ('Anna', 'Schmidt', 7000.00),
    ('Peter', 'Mayer', 6000.00);

SELECT * FROM employees;

SQL

echo
echo "✓ Cloud SQL database/table/data configuration complete."
REMOTE
)

REMOTE_SCRIPT="${REMOTE_SCRIPT/__DB_HOST__/$DB_HOST}"

REMOTE_B64="$(
  printf '%s' "$REMOTE_SCRIPT" | base64 | tr -d '\n'
)"

info "Running PostgreSQL setup from $CLIENT_VM..."

gcloud compute ssh "$CLIENT_VM" \
  --zone="$CLIENT_ZONE" \
  --project="$PROJECT" \
  --tunnel-through-iap \
  --quiet \
  --command="echo '$REMOTE_B64' | base64 -d | bash"

ok "TASK 5 Cloud SQL setup complete."

# ----------------------------------------------------------------
# [8/8] Verification
# ----------------------------------------------------------------

section "[8/8] FINAL VERIFICATION"

HUB_OK="$(
  gcloud network-connectivity hubs describe "$HUB" \
    --project="$PROJECT" \
    --format='value(name)' 2>/dev/null || true
)"

SPOKE1_OK="$(
  gcloud network-connectivity spokes describe "$SPOKE1" \
    --global \
    --project="$PROJECT" \
    --format='value(name)' 2>/dev/null || true
)"

SPOKE2_OK="$(
  gcloud network-connectivity spokes describe "$SPOKE2" \
    --global \
    --project="$PROJECT" \
    --format='value(name)' 2>/dev/null || true
)"

PSC_STATUS="$(
  gcloud compute forwarding-rules describe "$PSC_FORWARDING_RULE" \
    --region="$REGION" \
    --project="$PROJECT" \
    --format='value(pscConnectionStatus)' 2>/dev/null || true
)"

DNS_DATA="$(
  gcloud dns record-sets describe "$DNS_NAME" \
    --zone="$DNS_ZONE" \
    --type=A \
    --project="$PROJECT" \
    --format='value(rrdatas)' 2>/dev/null || true
)"

echo
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗"
echo -e "║                        LAB COMPLETE                             ║"
echo -e "╠══════════════════════════════════════════════════════════════════╣"
printf  "║ %-64s ║\n" "TASK 1  NCC Hub                         ✓"
printf  "║ %-64s ║\n" "TASK 2  VPC Spokes                      ✓"
printf  "║ %-64s ║\n" "TASK 3  IPv4 Data Path                  ✓ / checked"
printf  "║ %-64s ║\n" "TASK 4  Private Service Connect         ✓"
printf  "║ %-64s ║\n" "TASK 5  Cloud SQL via PSC               ✓"
echo -e "╠══════════════════════════════════════════════════════════════════╣"
printf  "║ %-64s ║\n" "PSC IP     : $PSC_IP"
printf  "║ %-64s ║\n" "PSC Status : $PSC_STATUS"
printf  "║ %-64s ║\n" "DNS        : $DNS_NAME"
echo -e "╠══════════════════════════════════════════════════════════════════╣"
printf  "║ %-64s ║\n" "DO NOT RUN TASK 6 BEFORE CHECK MY PROGRESS"
echo -e "║                         © ePlus.DEV                             ║"
echo -e "╚══════════════════════════════════════════════════════════════════╝${NC}"

echo
echo -e "${YELLOW}${BOLD}Now return to the lab page and click Check my progress.${NC}"
echo -e "${YELLOW}Do NOT delete the Hub, spokes, PSC or DNS until all graded tasks pass.${NC}"
echo