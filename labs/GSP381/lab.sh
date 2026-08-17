#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Cloud Spanner Challenge Lab
# banking-ops-instance / banking-ops-db
# © ePlus.DEV
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

section() {
  echo
  echo -e "${BOLD}${CYAN}======================================================================${NC}"
  echo -e "${BOLD}${CYAN}$1${NC}"
  echo -e "${BOLD}${CYAN}======================================================================${NC}"
}

trap 'echo -e "${RED}✗ Script failed at line $LINENO.${NC}" >&2' ERR

INSTANCE="banking-ops-instance"
DATABASE="banking-ops-db"
CUSTOMER_URI="gs://spls/gsp381/Customer_List_500.csv"

clear 2>/dev/null || true

echo -e "${BOLD}${CYAN}CLOUD SPANNER CHALLENGE LAB${NC}"
echo -e "${CYAN}© ePlus.DEV${NC}"

# =====================================================================
# Detect environment
# =====================================================================

section "[1/7] Detecting Google Cloud environment"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || \
  die "No active Google Cloud project was detected."

REGION="${REGION:-${CLOUDSDK_COMPUTE_REGION:-${GOOGLE_CLOUD_REGION:-}}}"

# Try gcloud default region
if [[ -z "$REGION" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
  [[ "$REGION" == "(unset)" ]] && REGION=""
fi

# Try default zone -> region
if [[ -z "$REGION" ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
  [[ "$ZONE" == "(unset)" ]] && ZONE=""

  if [[ -n "$ZONE" ]]; then
    REGION="${ZONE%-*}"
  fi
fi

# Try project metadata used by many Skills Boost labs
if [[ -z "$REGION" ]]; then
  REGION="$(
    gcloud compute project-info describe \
      --project="$PROJECT_ID" \
      --format=json 2>/dev/null |
    python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit

items = (
    data.get("commonInstanceMetadata", {})
        .get("items", [])
    or []
)

meta = {
    item.get("key", ""): item.get("value", "")
    for item in items
}

region = meta.get("google-compute-default-region", "")

if not region:
    zone = meta.get("google-compute-default-zone", "")
    if zone and "-" in zone:
        region = zone.rsplit("-", 1)[0]

print(region)
' 2>/dev/null || true
  )"
fi

[[ -n "$REGION" ]] || {
  echo
  echo -e "${RED}Lab Region could not be detected automatically.${NC}"
  echo
  echo "Look at the Region shown in the Lab setup panel, then run:"
  echo
  echo "  REGION=YOUR_LAB_REGION bash lab.sh"
  echo
  exit 1
}

ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"

echo "Project ID : $PROJECT_ID"
echo "Account    : $ACCOUNT"
echo "Region     : $REGION"

gcloud config set project "$PROJECT_ID" --quiet >/dev/null

ok "Cloud environment detected."

# =====================================================================
# API
# =====================================================================

section "[2/7] Enabling Cloud Spanner API"

gcloud services enable spanner.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

ok "Cloud Spanner API enabled."

# =====================================================================
# TASK 1
# =====================================================================

section "[3/7] TASK 1 - Create Cloud Spanner instance"

if gcloud spanner instances describe "$INSTANCE" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Instance already exists: $INSTANCE"

  CURRENT_CONFIG="$(
    gcloud spanner instances describe "$INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(config)' 2>/dev/null || true
  )"

  CURRENT_NODES="$(
    gcloud spanner instances describe "$INSTANCE" \
      --project="$PROJECT_ID" \
      --format='value(nodeCount)' 2>/dev/null || true
  )"

  echo "Configuration : $CURRENT_CONFIG"
  echo "Nodes         : ${CURRENT_NODES:-unknown}"

  if [[ "$CURRENT_CONFIG" != *"regional-${REGION}"* ]]; then
    warn "Existing instance is not in regional-${REGION}."
    warn "If Task 1 fails, this instance was probably created previously in the wrong region."
  fi

  if [[ -n "$CURRENT_NODES" && "$CURRENT_NODES" != "1" ]]; then
    info "Changing compute capacity to 1 node..."

    gcloud spanner instances update "$INSTANCE" \
      --nodes=1 \
      --project="$PROJECT_ID" \
      --quiet

    ok "Compute capacity changed to 1 node."
  fi

else

  info "Creating $INSTANCE..."
  echo "Configuration : regional-${REGION}"
  echo "Nodes         : 1"

  gcloud spanner instances create "$INSTANCE" \
    --config="regional-${REGION}" \
    --description="banking-ops-instance" \
    --nodes=1 \
    --project="$PROJECT_ID" \
    --quiet

  ok "Cloud Spanner instance created."

fi

# =====================================================================
# TASK 2
# =====================================================================

section "[4/7] TASK 2 + TASK 3 - Create database and tables"

if gcloud spanner databases describe "$DATABASE" \
    --instance="$INSTANCE" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Database already exists: $DATABASE"

else

  info "Creating database: $DATABASE"

  gcloud spanner databases create "$DATABASE" \
    --instance="$INSTANCE" \
    --project="$PROJECT_ID" \
    --quiet

  ok "Database created."

fi

# =====================================================================
# TASK 3
# =====================================================================

create_table_if_missing() {

  local TABLE_NAME="$1"
  local TABLE_DDL="$2"

  CURRENT_DDL="$(
    gcloud spanner databases ddl describe "$DATABASE" \
      --instance="$INSTANCE" \
      --project="$PROJECT_ID" \
      2>/dev/null || true
  )"

  if grep -Eq \
      "CREATE TABLE[[:space:]]+${TABLE_NAME}([[:space:]]|\\()" \
      <<< "$CURRENT_DDL"; then

    ok "Table already exists: $TABLE_NAME"

  else

    info "Creating table: $TABLE_NAME"

    gcloud spanner databases ddl update "$DATABASE" \
      --instance="$INSTANCE" \
      --project="$PROJECT_ID" \
      --ddl="$TABLE_DDL" \
      --quiet

    ok "Table created: $TABLE_NAME"

  fi
}

# Portfolio
create_table_if_missing \
  "Portfolio" \
'CREATE TABLE Portfolio (
  PortfolioId INT64 NOT NULL,
  Name STRING(MAX),
  ShortName STRING(MAX),
  PortfolioInfo STRING(MAX)
) PRIMARY KEY (PortfolioId)'

# Category
create_table_if_missing \
  "Category" \
'CREATE TABLE Category (
  CategoryId INT64 NOT NULL,
  PortfolioId INT64 NOT NULL,
  CategoryName STRING(MAX),
  PortfolioInfo STRING(MAX)
) PRIMARY KEY (CategoryId)'

# Product
create_table_if_missing \
  "Product" \
'CREATE TABLE Product (
  ProductId INT64 NOT NULL,
  CategoryId INT64 NOT NULL,
  PortfolioId INT64 NOT NULL,
  ProductName STRING(MAX),
  ProductAssetCode STRING(25),
  ProductClass STRING(25)
) PRIMARY KEY (ProductId)'

# Customer
create_table_if_missing \
  "Customer" \
'CREATE TABLE Customer (
  CustomerId STRING(36) NOT NULL,
  Name STRING(MAX) NOT NULL,
  Location STRING(MAX) NOT NULL
) PRIMARY KEY (CustomerId)'

ok "All required tables are ready."

# =====================================================================
# SQL helper
# =====================================================================

exec_sql() {

  local SQL="$1"

  gcloud spanner databases execute-sql "$DATABASE" \
    --instance="$INSTANCE" \
    --project="$PROJECT_ID" \
    --sql="$SQL" \
    --timeout=10m \
    --quiet \
    >/dev/null
}

# =====================================================================
# TASK 4
# =====================================================================

section "[5/7] TASK 4 - Load Portfolio, Category and Product"

# ---------------------------------------------------------------------
# Portfolio
# ---------------------------------------------------------------------

info "Loading Portfolio..."

exec_sql "
INSERT OR UPDATE INTO Portfolio
(
  PortfolioId,
  Name,
  ShortName,
  PortfolioInfo
)
VALUES
  (
    1,
    'Banking',
    'Bnkg',
    'All Banking Business'
  ),
  (
    2,
    'Asset Growth',
    'AsstGrwth',
    'All Asset Focused Products'
  ),
  (
    3,
    'Insurance',
    'Insurance',
    'All Insurance Focused Products'
  )
"

ok "Portfolio loaded."

# ---------------------------------------------------------------------
# Category
# ---------------------------------------------------------------------

info "Loading Category..."

# The supplied Category dataset has only:
# CategoryId, PortfolioId, CategoryName
#
# PortfolioInfo is nullable, therefore it is intentionally omitted.

exec_sql "
INSERT OR UPDATE INTO Category
(
  CategoryId,
  PortfolioId,
  CategoryName
)
VALUES
  (
    1,
    1,
    'Cash'
  ),
  (
    2,
    2,
    'Investments - Short Return'
  ),
  (
    3,
    2,
    'Annuities'
  ),
  (
    4,
    3,
    'Life Insurance'
  )
"

ok "Category loaded."

# ---------------------------------------------------------------------
# Product
# ---------------------------------------------------------------------

info "Loading Product..."

exec_sql "
INSERT OR UPDATE INTO Product
(
  ProductId,
  CategoryId,
  PortfolioId,
  ProductName,
  ProductAssetCode,
  ProductClass
)
VALUES
  (
    1,
    1,
    1,
    'Checking Account',
    'ChkAcct',
    'Banking LOB'
  ),
  (
    2,
    2,
    2,
    'Mutual Fund Consumer Goods',
    'MFundCG',
    'Investment LOB'
  ),
  (
    3,
    3,
    2,
    'Annuity Early Retirement',
    'AnnuFixed',
    'Investment LOB'
  ),
  (
    4,
    4,
    3,
    'Term Life Insurance',
    'TermLife',
    'Insurance LOB'
  ),
  (
    5,
    1,
    1,
    'Savings Account',
    'SavAcct',
    'Banking LOB'
  ),
  (
    6,
    1,
    1,
    'Personal Loan',
    'PersLn',
    'Banking LOB'
  ),
  (
    7,
    1,
    1,
    'Auto Loan',
    'AutLn',
    'Banking LOB'
  ),
  (
    8,
    4,
    3,
    'Permanent Life Insurance',
    'PermLife',
    'Insurance LOB'
  ),
  (
    9,
    2,
    2,
    'US Savings Bonds',
    'USSavBond',
    'Investment LOB'
  )
"

ok "Product loaded."

# =====================================================================
# TASK 5
# =====================================================================

section "[6/7] TASK 5 - Load 500 Customer records"

WORK_DIR="$(mktemp -d)"
CSV_FILE="$WORK_DIR/Customer_List_500.csv"
BATCH_DIR="$WORK_DIR/sql"

mkdir -p "$BATCH_DIR"

cleanup() {
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

# ---------------------------------------------------------------------
# Download CSV
# ---------------------------------------------------------------------

info "Downloading Customer_List_500.csv..."

gcloud storage cp \
  "$CUSTOMER_URI" \
  "$CSV_FILE" \
  --quiet

ok "Customer CSV downloaded."

# ---------------------------------------------------------------------
# Convert CSV -> safe batched GoogleSQL
# ---------------------------------------------------------------------

info "Preparing Customer batches..."

ROW_COUNT="$(
python3 - "$CSV_FILE" "$BATCH_DIR" <<'PY'
import csv
import os
import sys

csv_file = sys.argv[1]
output_dir = sys.argv[2]

with open(
    csv_file,
    "r",
    encoding="utf-8-sig",
    newline=""
) as f:
    rows = [
        row
        for row in csv.reader(f)
        if any(cell.strip() for cell in row)
    ]

# Be tolerant if the source file contains a header.
if rows:
    first = rows[0][0].strip().lower()

    if first in {
        "customerid",
        "customer_id"
    }:
        rows = rows[1:]

if len(rows) != 500:
    raise SystemExit(
        f"Expected exactly 500 customer rows, found {len(rows)}"
    )

for index, row in enumerate(rows, start=1):

    if len(row) != 3:
        raise SystemExit(
            f"CSV row {index} contains {len(row)} columns; expected 3"
        )

    customer_id = row[0]

    if len(customer_id) > 36:
        raise SystemExit(
            f"CustomerId on row {index} exceeds STRING(36)"
        )

def sql_string(value: str) -> str:

    # Escape according to GoogleSQL quoted-string rules.
    value = (
        value
        .replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )

    return "'" + value + "'"

# 500 rows / 50 rows = 10 small DML batches
batch_size = 50

for start in range(
    0,
    len(rows),
    batch_size
):

    batch = rows[
        start:start + batch_size
    ]

    values = ",\n".join(
        "  ({}, {}, {})".format(
            sql_string(customer_id),
            sql_string(name),
            sql_string(location)
        )
        for customer_id, name, location in batch
    )

    statement = (
        "INSERT OR UPDATE INTO Customer "
        "(CustomerId, Name, Location) VALUES\n"
        + values
    )

    batch_number = (
        start // batch_size
    ) + 1

    filename = os.path.join(
        output_dir,
        f"batch_{batch_number:02d}.sql"
    )

    with open(
        filename,
        "w",
        encoding="utf-8"
    ) as output:
        output.write(statement)

print(len(rows))
PY
)"

[[ "$ROW_COUNT" == "500" ]] || \
  die "Customer CSV validation failed."

ok "CSV validated: 500 Customer rows."

TOTAL_BATCHES="$(
  find "$BATCH_DIR" \
    -maxdepth 1 \
    -name 'batch_*.sql' |
  wc -l |
  tr -d ' '
)"

CURRENT_BATCH=0

# ---------------------------------------------------------------------
# Load batches
# ---------------------------------------------------------------------

for SQL_FILE in "$BATCH_DIR"/batch_*.sql
do

  CURRENT_BATCH=$((CURRENT_BATCH + 1))

  info "Loading Customer batch ${CURRENT_BATCH}/${TOTAL_BATCHES}..."

  gcloud spanner databases execute-sql "$DATABASE" \
    --instance="$INSTANCE" \
    --project="$PROJECT_ID" \
    --sql="$(cat "$SQL_FILE")" \
    --timeout=10m \
    --quiet \
    >/dev/null

  ok "Customer batch ${CURRENT_BATCH}/${TOTAL_BATCHES} loaded."

done

# ---------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------

info "Verifying Customer table..."

CUSTOMER_COUNT="$(
  gcloud spanner databases execute-sql "$DATABASE" \
    --instance="$INSTANCE" \
    --project="$PROJECT_ID" \
    --sql='
      SELECT COUNT(*) AS CustomerCount
      FROM Customer
    ' \
    --format='value(CustomerCount)' \
    --quiet \
    2>/dev/null |
  tail -n 1 || true
)"

if [[ "$CUSTOMER_COUNT" == "500" ]]; then

  ok "Customer table contains exactly 500 rows."

else

  warn "Count output could not be parsed automatically."
  echo
  echo "Verification result:"

  gcloud spanner databases execute-sql "$DATABASE" \
    --instance="$INSTANCE" \
    --project="$PROJECT_ID" \
    --sql='
      SELECT COUNT(*) AS CustomerCount
      FROM Customer
    ' \
    --quiet

fi

# =====================================================================
# TASK 6
# =====================================================================

section "[7/7] TASK 6 - Add Category.MarketingBudget"

CURRENT_DDL="$(
  gcloud spanner databases ddl describe "$DATABASE" \
    --instance="$INSTANCE" \
    --project="$PROJECT_ID" \
    2>/dev/null || true
)"

if grep -Eq \
  'MarketingBudget[[:space:]]+INT64' \
  <<< "$CURRENT_DDL"; then

  ok "MarketingBudget already exists."

else

  info "Adding MarketingBudget INT64..."

  gcloud spanner databases ddl update "$DATABASE" \
    --instance="$INSTANCE" \
    --project="$PROJECT_ID" \
    --ddl='ALTER TABLE Category ADD COLUMN MarketingBudget INT64' \
    --quiet

  ok "MarketingBudget added."

fi

# =====================================================================
# Finished
# =====================================================================

echo
echo -e "${BOLD}${GREEN}======================================================================${NC}"
echo -e "${BOLD}${GREEN}CLOUD SPANNER LAB COMPLETE${NC}"
echo -e "${BOLD}${GREEN}======================================================================${NC}"
echo
echo "TASK 1  ✓ banking-ops-instance"
echo "          regional-${REGION}"
echo "          1 node"
echo
echo "TASK 2  ✓ banking-ops-db"
echo
echo "TASK 3  ✓ Portfolio"
echo "        ✓ Category"
echo "        ✓ Product"
echo "        ✓ Customer"
echo
echo "TASK 4  ✓ Simple datasets loaded"
echo
echo "TASK 5  ✓ 500 Customer records loaded"
echo
echo "TASK 6  ✓ Category.MarketingBudget INT64"
echo
echo -e "${BOLD}${CYAN}Now click all Check my progress buttons.${NC}"
echo
echo -e "${CYAN}© ePlus.DEV${NC}"