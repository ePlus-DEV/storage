#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# BigQuery: Working with ARRAYs and STRUCTs - One Shot Lab
# Copyright © ePlus.DEV
# ============================================================

# ---------- Colors ----------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  CYAN="$(tput setaf 6)"
  BOLD="$(tput bold)"
  RESET="$(tput sgr0)"
else
  RED="" GREEN="" YELLOW="" BLUE="" CYAN="" BOLD="" RESET=""
fi

info()    { printf '%s\n' "${BLUE}▶${RESET} $*"; }
success() { printf '%s\n' "${GREEN}✔${RESET} $*"; }
warn()    { printf '%s\n' "${YELLOW}⚠${RESET} $*"; }
fail()    { printf '%s\n' "${RED}✘${RESET} $*" >&2; exit 1; }

printf '%s\n' "${CYAN}${BOLD}"
printf '%s\n' '╔══════════════════════════════════════════════════════════════╗'
printf '%s\n' '║          BIGQUERY ARRAYS & STRUCTS - ONE SHOT LAB           ║'
printf '%s\n' '║                    Copyright © ePlus.DEV                    ║'
printf '%s\n' '╚══════════════════════════════════════════════════════════════╝'
printf '%s\n' "${RESET}"

command -v gcloud >/dev/null 2>&1 || fail "gcloud CLI was not found. Run this script in Google Cloud Shell."
command -v bq >/dev/null 2>&1 || fail "bq CLI was not found. Run this script in Google Cloud Shell."

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || fail "No active Google Cloud project was detected."

ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
BQ_LOCATION="US"

printf 'Project ID : %s\n' "$PROJECT_ID"
printf 'Account    : %s\n' "$ACCOUNT"
printf 'BQ location: %s\n\n' "$BQ_LOCATION"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

run_query() {
  local title="$1"
  local sql="$2"
  info "$title"
  bq --location="$BQ_LOCATION" query \
    --use_legacy_sql=false \
    --format=pretty \
    "$sql"
  success "$title completed"
  echo
}

create_dataset() {
  local dataset="$1"
  if bq --location="$BQ_LOCATION" show --dataset "${PROJECT_ID}:${dataset}" >/dev/null 2>&1; then
    success "Dataset ${dataset} already exists"
  else
    info "Creating dataset ${dataset}"
    bq --location="$BQ_LOCATION" mk \
      --dataset \
      --description="Created automatically for the BigQuery ARRAY and STRUCT lab" \
      "${PROJECT_ID}:${dataset}" >/dev/null
    success "Dataset ${dataset} created"
  fi
}

# ============================================================
# Task 1 + Task 2: fruit_store dataset and fruit_details table
# ============================================================
create_dataset "fruit_store"

info "Loading fruit_details from Cloud Storage"
bq --location="$BQ_LOCATION" load \
  --replace \
  --autodetect \
  --source_format=NEWLINE_DELIMITED_JSON \
  "${PROJECT_ID}:fruit_store.fruit_details" \
  "gs://spls/gsp416/data-insights-course/labs/optimizing-for-performance/shopping_cart.json"
success "fruit_store.fruit_details loaded"
echo

run_query "Testing a string ARRAY" \
"SELECT ['raspberry', 'blackberry', 'strawberry', 'cherry'] AS fruit_array;"

run_query "Reading the public fruit_store table" \
"SELECT person, fruit_array, total_cost
 FROM \`data-to-insights.advanced.fruit_store\`;"

# ============================================================
# Task 3: ARRAY_AGG(), ARRAY_LENGTH(), DISTINCT
# ============================================================
run_query "Task 3 - Aggregate unique products and pages into arrays" \
"SELECT
   fullVisitorId,
   date,
   ARRAY_AGG(DISTINCT v2ProductName) AS products_viewed,
   ARRAY_LENGTH(ARRAY_AGG(DISTINCT v2ProductName)) AS distinct_products_viewed,
   ARRAY_AGG(DISTINCT pageTitle) AS pages_viewed,
   ARRAY_LENGTH(ARRAY_AGG(DISTINCT pageTitle)) AS distinct_pages_viewed
 FROM \`data-to-insights.ecommerce.all_sessions\`
 WHERE visitId = 1501570398
 GROUP BY fullVisitorId, date
 ORDER BY date;"

# ============================================================
# Task 4: UNNEST an ARRAY field
# ============================================================
run_query "Task 4 - UNNEST hits and list page titles" \
"SELECT DISTINCT
   visitId,
   h.page.pageTitle
 FROM \`bigquery-public-data.google_analytics_sample.ga_sessions_20170801\`,
 UNNEST(hits) AS h
 WHERE visitId = 1501570398
 LIMIT 10;"

# ============================================================
# Task 6: racing dataset and nested/repeated table
# ============================================================
create_dataset "racing"

cat > "${WORK_DIR}/race_schema.json" <<'JSON'
[
  {
    "name": "race",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "participants",
    "type": "RECORD",
    "mode": "REPEATED",
    "fields": [
      {
        "name": "name",
        "type": "STRING",
        "mode": "NULLABLE"
      },
      {
        "name": "splits",
        "type": "FLOAT",
        "mode": "REPEATED"
      }
    ]
  }
]
JSON

info "Loading racing.race_results with the nested schema"
bq --location="$BQ_LOCATION" load \
  --replace \
  --source_format=NEWLINE_DELIMITED_JSON \
  "${PROJECT_ID}:racing.race_results" \
  "gs://spls/gsp416/data-insights-course/labs/optimizing-for-performance/race_results.json" \
  "${WORK_DIR}/race_schema.json"
success "racing.race_results loaded"
echo

run_query "List every race participant" \
"SELECT
   race,
   p.name
 FROM \`${PROJECT_ID}.racing.race_results\` AS r,
 UNNEST(r.participants) AS p;"

# ============================================================
# Task 7: Count racers
# ============================================================
run_query "Task 7 - Count all racers" \
"SELECT COUNT(p.name) AS racer_count
 FROM \`${PROJECT_ID}.racing.race_results\` AS r,
 UNNEST(r.participants) AS p;"

# ============================================================
# Task 8: Total time for racers starting with R
# ============================================================
run_query "Task 8 - Total race time for names beginning with R" \
"SELECT
   p.name,
   SUM(split_time) AS total_race_time
 FROM \`${PROJECT_ID}.racing.race_results\` AS r,
 UNNEST(r.participants) AS p,
 UNNEST(p.splits) AS split_time
 WHERE p.name LIKE 'R%'
 GROUP BY p.name
 ORDER BY total_race_time ASC;"

# ============================================================
# Task 9: Find the runner with the 23.2 second split
# ============================================================
run_query "Task 9 - Find the runner who recorded a 23.2-second split" \
"SELECT
   p.name,
   split_time
 FROM \`${PROJECT_ID}.racing.race_results\` AS r,
 UNNEST(r.participants) AS p,
 UNNEST(p.splits) AS split_time
 WHERE split_time = 23.2;"

printf '%s\n' "${GREEN}${BOLD}"
printf '%s\n' '╔══════════════════════════════════════════════════════════════╗'
printf '%s\n' '║                    LAB SCRIPT COMPLETED                     ║'
printf '%s\n' '╚══════════════════════════════════════════════════════════════╝'
printf '%s\n' "${RESET}"
printf '%s\n' "Return to the lab page and click Check my progress for each objective."