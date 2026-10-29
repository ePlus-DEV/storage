#!/usr/bin/env bash
# GSP340 - Build a Data Warehouse with BigQuery: Challenge Lab
# Copyright (c) 2026 ePlus.DEV | Unlicense (repository LICENSE)
# This script targets the four-task variant documented in the linked README.
# Other challenge-lab variants can have different tables and expiration days.
set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  CYAN=$'\033[1;36m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' RED=$'\033[0;31m' RESET=$'\033[0m'
else
  CYAN='' GREEN='' YELLOW='' RED='' RESET=''
fi
printf '%s\n' "${CYAN}==========================================================${RESET}" \
  "${CYAN} ePlus.DEV - Starting Execution | GSP340${RESET}" \
  "${YELLOW} Copyright (c) 2026 ePlus.DEV | Unlicense${RESET}" \
  "${CYAN}==========================================================${RESET}"

info() { printf '%s\n' "${CYAN}[TASK $1]${RESET} $2"; }
warn() { printf '%s\n' "${YELLOW}[WARN]${RESET} $*" >&2; }
die() { printf '%s\n' "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
trap 'printf "[ERROR] Command failed at line %s. Review the BigQuery error above.\n" "$LINENO" >&2' ERR

for cmd in gcloud bq jq; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing command: $cmd (use Google Cloud Shell)."
done

PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == '(unset)' ]]; then
  if [[ -t 0 ]]; then
    read -r -p 'Lab project ID: ' PROJECT_ID
  fi
fi
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || die 'Set PROJECT_ID to the temporary lab project ID.'

# Match these defaults to the four tasks shown in your own GSP340 instance.
DS_COVID="${DS_COVID:-covid}"
DS_MAIN="${DS_MAIN:-covid_data}"
TBL_TRACKER="${TBL_TRACKER:-oxford_policy_tracker}"
TBL_CONSOLIDATED="${TBL_CONSOLIDATED:-consolidate_covid_tracker_data}"
TBL_WORLDWIDE="${TBL_WORLDWIDE:-oxford_policy_tracker_worldwide}"
TBL_POP="${TBL_POP:-pop_data_2019}"
EXPIRY_DAYS="${EXPIRY_DAYS:-1080}"
for ident in "$DS_COVID" "$DS_MAIN" "$TBL_TRACKER" "$TBL_CONSOLIDATED" "$TBL_WORLDWIDE" "$TBL_POP"; do
  [[ "$ident" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Invalid BigQuery identifier: $ident"
done
[[ "$EXPIRY_DAYS" =~ ^[0-9]+$ ]] && (( 10#$EXPIRY_DAYS > 0 )) || die 'EXPIRY_DAYS must be a positive integer.'

show() { bq --project_id="$PROJECT_ID" show --format=prettyjson "$1"; }
query() { bq --project_id="$PROJECT_ID" --location="$BQ_LOCATION" query --use_legacy_sql=false --format=pretty "$1"; }

# Lab-created resources may take a minute to appear; never create them ourselves.
wait_for_resource() {
  local resource="$1" attempt
  for attempt in 1 2 3 4 5 6; do
    if show "$resource" >/dev/null 2>&1; then return 0; fi
    if (( attempt < 6 )); then
      warn "Waiting for lab-provisioned $resource ($attempt/6); retry in 10s."
      sleep 10
    fi
  done
  die "Lab-provisioned $resource is missing or inaccessible. Verify lab credentials and provisioning."
}

wait_for_resource "$PROJECT_ID:$DS_MAIN"
MAIN_LOCATION="$(show "$PROJECT_ID:$DS_MAIN" | jq -r '.location // empty')"
[[ -n "$MAIN_LOCATION" ]] || die "Could not determine $DS_MAIN location."
BQ_LOCATION="${BQ_LOCATION:-$MAIN_LOCATION}"
[[ "${BQ_LOCATION,,}" == "${MAIN_LOCATION,,}" ]] || die "BQ_LOCATION=$BQ_LOCATION differs from lab dataset location $MAIN_LOCATION."
warn 'GSP340 is a challenge lab with randomized task variants. Confirm the table names and EXPIRY_DAYS on your lab page before proceeding.'
printf 'Project: %s | BigQuery location: %s | Partition expiry: %s days\n' "$PROJECT_ID" "$BQ_LOCATION" "$EXPIRY_DAYS"

info 1 "Create date-partitioned $DS_COVID.$TBL_TRACKER; exclude GBR/BRA/CAN/USA"
if show "$PROJECT_ID:$DS_COVID" >/dev/null 2>&1; then
  COVID_LOCATION="$(show "$PROJECT_ID:$DS_COVID" | jq -r '.location // empty')"
  [[ "${COVID_LOCATION,,}" == "${BQ_LOCATION,,}" ]] || die "$DS_COVID is in $COVID_LOCATION; expected $BQ_LOCATION."
else
  bq --project_id="$PROJECT_ID" --location="$BQ_LOCATION" mk --dataset "$PROJECT_ID:$DS_COVID"
fi
query "
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DS_COVID.$TBL_TRACKER\`
PARTITION BY date
OPTIONS (partition_expiration_days = $EXPIRY_DAYS) AS
SELECT *
FROM \`bigquery-public-data.covid19_govt_response.oxford_policy_tracker\`
WHERE alpha_3_code NOT IN ('GBR', 'BRA', 'CAN', 'USA');"

info 2 "Populate nested mobility averages in $DS_MAIN.$TBL_CONSOLIDATED"
wait_for_resource "$PROJECT_ID:$DS_MAIN.$TBL_CONSOLIDATED"
# The lab may pre-create mobility; IF NOT EXISTS keeps reruns safe.
query "
ALTER TABLE \`$PROJECT_ID.$DS_MAIN.$TBL_CONSOLIDATED\`
ADD COLUMN IF NOT EXISTS mobility STRUCT<
  avg_retail FLOAT64, avg_grocery FLOAT64, avg_parks FLOAT64,
  avg_transit FLOAT64, avg_workplace FLOAT64, avg_residential FLOAT64>;"
query "
UPDATE \`$PROJECT_ID.$DS_MAIN.$TBL_CONSOLIDATED\` AS target
SET mobility.avg_retail = source.avg_retail,
    mobility.avg_grocery = source.avg_grocery,
    mobility.avg_parks = source.avg_parks,
    mobility.avg_transit = source.avg_transit,
    mobility.avg_workplace = source.avg_workplace,
    mobility.avg_residential = source.avg_residential
FROM (
  SELECT country_region, date,
    AVG(retail_and_recreation_percent_change_from_baseline) AS avg_retail,
    AVG(grocery_and_pharmacy_percent_change_from_baseline) AS avg_grocery,
    AVG(parks_percent_change_from_baseline) AS avg_parks,
    AVG(transit_stations_percent_change_from_baseline) AS avg_transit,
    AVG(workplaces_percent_change_from_baseline) AS avg_workplace,
    AVG(residential_percent_change_from_baseline) AS avg_residential
  FROM \`bigquery-public-data.covid19_google_mobility.mobility_report\`
  GROUP BY country_region, date
) AS source
WHERE target.country_name = source.country_region
  AND target.date = source.date;"

info 3 "Query missing population/country_area (UNION ALL preserves both reasons)"
wait_for_resource "$PROJECT_ID:$DS_MAIN.$TBL_WORLDWIDE"
query "
SELECT DISTINCT country_name
FROM \`$PROJECT_ID.$DS_MAIN.$TBL_WORLDWIDE\`
WHERE population IS NULL
UNION ALL
SELECT DISTINCT country_name
FROM \`$PROJECT_ID.$DS_MAIN.$TBL_WORLDWIDE\`
WHERE country_area IS NULL
ORDER BY country_name;"

info 4 "Copy ECDC public dataset to $DS_MAIN.$TBL_POP"
query "
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DS_MAIN.$TBL_POP\` AS
SELECT * FROM \`bigquery-public-data.covid19_ecdc.covid_19_geographic_distribution_worldwide\`;"

info VERIFY 'Check partition metadata and target tables (not the Skills Boost grader)'
actual_ms="$(show "$PROJECT_ID:$DS_COVID.$TBL_TRACKER" | jq -r '.timePartitioning.expirationMs // empty')"
expected_ms=$(( 10#$EXPIRY_DAYS * 86400000 ))
[[ "$actual_ms" == "$expected_ms" ]] || die "Partition expiration is $actual_ms ms; expected $expected_ms ms."
show "$PROJECT_ID:$DS_MAIN.$TBL_POP" >/dev/null
query "SELECT COUNTIF(alpha_3_code IN ('GBR', 'BRA', 'CAN', 'USA')) AS excluded_rows
FROM \`$PROJECT_ID.$DS_COVID.$TBL_TRACKER\`;"
printf '%s\n' "${GREEN}BigQuery commands completed. Check each task with 'Check my progress' in Skills Boost.${RESET}"
