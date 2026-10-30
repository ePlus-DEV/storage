#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  bash "${BASH_SOURCE[0]}" "$@"
  return $?
fi
set -Eeuo pipefail
BLUE=''; GREEN=''; RED=''; RESET=''
if [[ -z "${NO_COLOR:-}" && ( -t 1 || "${FORCE_COLOR:-0}" == "1" ) ]]; then
  BLUE=$(printf '\\033[1;34m' || true)
  GREEN=$(printf '\\033[1;32m' || true)
  RED=$(printf '\\033[1;31m' || true)
  RESET=$(printf '\\033[0m' || true)
fi
step(){ printf '\n%s== %s ==%s\n' "$BLUE" "$1" "$RESET"; }
ok(){ printf '%s✔ %s%s\n' "$GREEN" "$1" "$RESET"; }
echo "ePlus.DEV – Starting Execution"
echo "Copyright (c) 2026 ePlus.DEV | Unlicense"
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="${REGION:-${CLOUDSDK_COMPUTE_REGION:-$(gcloud config get-value compute/region 2>/dev/null || true)}}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
 read -r -p "GCP Region from lab launch page: " REGION
fi
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" && -n "$REGION" && "$REGION" != "(unset)" ]] || { echo "Project or region missing" >&2; exit 1; }
[[ "$REGION" =~ ^[a-z]+(-[a-z0-9]+)+[0-9]+$ ]] || { echo "Invalid GCP Region: $REGION" >&2; exit 1; }
printf 'Project: %s | Region: %s\n' "$PROJECT_ID" "$REGION"
step "Task 1 — Create AlloyDB cluster and primary"
if ! gcloud alloydb clusters describe lab-cluster --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
 gcloud alloydb clusters create lab-cluster --password=Change3Me --network=peering-network --region="$REGION" --project="$PROJECT_ID"
fi
if ! gcloud alloydb instances describe lab-instance --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
 gcloud alloydb instances create lab-instance --instance-type=PRIMARY --cpu-count=2 --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID"
fi
for i in $(seq 1 45); do
 STATE=$(gcloud alloydb instances describe lab-instance --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID" --format='value(state)' 2>/dev/null || true)
 [[ "$STATE" == READY ]] && break
 sleep 20
done
[[ "$STATE" == READY ]] || { echo "Primary not READY"; exit 1; }
IP=$(gcloud alloydb instances describe lab-instance --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID" --format='value(ipAddress)')
[[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
step "Task 2–3 — Create and populate HR tables"
ZONE=$(gcloud compute instances list --project="$PROJECT_ID" --filter='name=alloydb-client' --format='value(zone)' | awk -F/ 'NF{print $NF;exit}')
[[ -n "$ZONE" ]] || { echo "Missing alloydb-client"; exit 1; }
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
cat > "$TEMP/seed.sql" <<'SQL'
\set ON_ERROR_STOP on
BEGIN;
CREATE TABLE IF NOT EXISTS regions (region_id bigint NOT NULL PRIMARY KEY, region_name varchar(25));
CREATE TABLE IF NOT EXISTS countries (country_id char(2) NOT NULL PRIMARY KEY, country_name varchar(40), region_id bigint);
CREATE TABLE IF NOT EXISTS departments (department_id smallint NOT NULL PRIMARY KEY, department_name varchar(30), manager_id integer, location_id smallint);
INSERT INTO regions VALUES (1,'Europe'),(2,'Americas'),(3,'Asia'),(4,'Middle East and Africa') ON CONFLICT(region_id) DO NOTHING;
INSERT INTO countries VALUES ('IT','Italy',1),('JP','Japan',3),('US','United States of America',2),('CA','Canada',2),('CN','China',3),('IN','India',3),('AU','Australia',3),('ZW','Zimbabwe',4),('SG','Singapore',3) ON CONFLICT(country_id) DO NOTHING;
INSERT INTO departments VALUES (10,'Administration',200,1700),(20,'Marketing',201,1800),(30,'Purchasing',114,1700),(40,'Human Resources',203,2400),(50,'Shipping',121,1500),(60,'IT',103,1400) ON CONFLICT(department_id) DO NOTHING;
COMMIT;
SELECT 'regions' AS name,count(*) FROM regions UNION ALL SELECT 'countries',count(*) FROM countries UNION ALL SELECT 'departments',count(*) FROM departments;
SQL
gcloud compute scp "$TEMP/seed.sql" alloydb-client:/tmp/eplus-gsp395-seed.sql --zone="$ZONE" --project="$PROJECT_ID" --quiet
gcloud compute ssh alloydb-client --zone="$ZONE" --project="$PROJECT_ID" --quiet --command="export ALLOYDB='$IP'; echo \"\$ALLOYDB\" > ~/alloydbip.txt; PGPASSWORD=Change3Me psql -X -v ON_ERROR_STOP=1 -h \"\$ALLOYDB\" -U postgres -d postgres -f /tmp/eplus-gsp395-seed.sql; rm /tmp/eplus-gsp395-seed.sql"
ok "HR tables populated"
step "Task 4 — Create 2-node read pool"
if ! gcloud alloydb instances describe lab-instance-rp1 --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
 gcloud alloydb instances create lab-instance-rp1 --instance-type=READ_POOL --cpu-count=2 --read-pool-node-count=2 --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID"
fi
step "Task 5 — Create backup"
if ! gcloud alloydb backups describe lab-backup --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
 gcloud alloydb backups create lab-backup --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID"
fi
gcloud alloydb backups describe lab-backup --region="$REGION" --project="$PROJECT_ID" --format='yaml(name,state)'
ok "Finished; click Check my progress for each task. Grader not verified."
