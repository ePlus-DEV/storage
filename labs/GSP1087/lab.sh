#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  bash "${BASH_SOURCE[0]}" "$@"
  return $?
fi
set -Eeuo pipefail
if [[ -z "${NO_COLOR:-}" && ( -t 1 || "${FORCE_COLOR:-0}" == "1" ) ]]; then
  BLUE=$'\033[1;34m'; GREEN=$'\033[1;32m'; RED=$'\033[1;31m'; RESET=$'\033[0m'
else
  BLUE=''; GREEN=''; RED=''; RESET=''
fi
printf '%s\n' "${BLUE}ePlus.DEV – Starting Execution${RESET}" "Copyright (c) 2026 ePlus.DEV | Unlicense"
trap 'printf "%sError at line %s%s\n" "$RED" "$LINENO" "$RESET" >&2' ERR
step() { printf '\n%s== %s ==%s\n' "$BLUE" "$1" "$RESET"; }
fail() { printf '%sERROR: %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }
ask() { local key="$1" label="$2" value; [[ -t 0 ]] || fail "Set $key before running non-interactively"; read -r -p "$label: " value; [[ -n "$value" ]] || fail "$key is required"; printf -v "$key" '%s' "$value"; }
need gcloud
PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}}"
[[ -n "$PROJECT_ID" ]] || PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || ask PROJECT_ID 'Lab project ID'
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,61}[a-z0-9]$ ]] || fail 'Invalid project ID'
CLUSTER_ID=lab-cluster
INSTANCE_ID=lab-instance
REGION="${REGION:-${CLOUDSDK_COMPUTE_REGION:-}}"
if [[ -z "$REGION" ]]; then
  REGION="$(gcloud alloydb clusters list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | awk -F/ '$NF=="lab-cluster" {print $(NF-2); exit}')"
fi
[[ -n "$REGION" ]] || ask REGION 'AlloyDB cluster region'
[[ "$REGION" =~ ^[a-z]+(-[a-z0-9]+)+[0-9]+$ ]] || fail 'Invalid region'
instance_ip() {
  gcloud alloydb instances describe "$INSTANCE_ID" --project="$PROJECT_ID" --cluster="$CLUSTER_ID" --region="$REGION" --format='value(ipAddress)'
}
wait_primary() {
  local state
  for ((i=1;i<=30;i++)); do
    state="$(gcloud alloydb instances describe "$INSTANCE_ID" --project="$PROJECT_ID" --cluster="$CLUSTER_ID" --region="$REGION" --format='value(state)' 2>/dev/null || true)"
    [[ "$state" == READY ]] && return 0
    printf 'Primary status: %s (attempt %d/30)\n' "${state:-unavailable}" "$i"
    sleep 20
  done
  fail 'Primary did not become READY within 10 minutes'
}
vm_zone() {
  local vm="$1" zone candidate
  # Project metadata is a useful hint, but the provisioned VM is authoritative.
  candidate="$(gcloud compute project-info describe --project="$PROJECT_ID" --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)"
  zone="$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$vm" --format='value(zone)' 2>/dev/null | awk -F/ 'NF && $NF != "" {print $NF}' | sort -u)"
  [[ -n "$zone" ]] || fail "Could not discover zone for VM $vm (project default: ${candidate:-unset})"
  [[ "$zone" != *$'\n'* ]] || fail "Multiple zones found for VM $vm: $zone"
  [[ "$zone" =~ ^[a-z]+(-[a-z0-9]+)+[0-9]+-[a-z]$ ]] || fail "Invalid zone for $vm: $zone"
  printf '%s' "$zone"
}

remote_run() {
  local vm="$1" zone="$2" command="$3"
  gcloud compute ssh "$vm" --project="$PROJECT_ID" --zone="$zone" --quiet --command="$command" -- -tt
}
remote_copy() {
  local src="$1" vm="$2" zone="$3" dest="$4"
  gcloud compute scp --quiet --project="$PROJECT_ID" --zone="$zone" "$src" "$vm:$dest"
}
workdir="$(mktemp -d)"
trap 'rm -rf -- "$workdir"' EXIT

step 'Task 1 — Verify preprovisioned instance and VM'
wait_primary
IP="$(instance_ip)"
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail 'No valid private IP found'
ZONE="$(vm_zone alloydb-client)"
REMOTE_DIR="/tmp/eplus-gsp1087-$PROJECT_ID"
remote_run alloydb-client "$ZONE" "mkdir -p -m 700 '$REMOTE_DIR'"
cat > "$workdir/remote.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -z "${PGPASSWORD:-}" ]]; then
  [[ -r /dev/tty ]] || { echo 'Interactive SSH TTY required for the lab-provided database password' >&2; exit 2; }
  printf '%s\n' 'GSP1087 lab hint: the official instructions specify PostgreSQL password Change3Me.' 'Input is hidden; press Enter after typing it. Do not share passwords in logs.' >/dev/tty
  read -r -s -p 'PostgreSQL password (press Enter to continue): ' PGPASSWORD </dev/tty
  printf '\n' >/dev/tty
  [[ -n "$PGPASSWORD" ]] || { echo 'Password required' >&2; exit 2; }
  export PGPASSWORD
fi
IP="$1"
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || exit 2
sql() { psql -X -v ON_ERROR_STOP=1 -h "$IP" -U postgres -d postgres -c "$1"; }
scalar() { psql -X -At -v ON_ERROR_STOP=1 -h "$IP" -U postgres -d postgres -c "$1"; }
if ! scalar 'SELECT 1;' >/dev/null; then
  echo 'PostgreSQL login failed. Confirm the password from this lab and rerun; no database changes were made.' >&2
  exit 1
fi
echo 'Task 1 — Generate 50-million-row baseline dataset (checkpoint 50)'
exists="$(scalar "SELECT to_regclass('public.pgbench_accounts') IS NOT NULL;")"
if [[ "$exists" == f ]]; then
  pgbench -h "$IP" -U postgres -i -s 500 -F 90 -n postgres
else
  count="$(scalar 'SELECT count(*) FROM public.pgbench_accounts;')"
  [[ "$count" == 50000000 ]] || { echo "Unexpected existing pgbench row count: $count; refusing destructive reinit" >&2; exit 1; }
fi
[[ "$(scalar 'SELECT count(*) FROM public.pgbench_accounts;')" == 50000000 ]] || { echo 'Baseline row count mismatch' >&2; exit 1; }
echo 'Task 2 — Baseline performance query'
sql 'SELECT aid,bid,abalance FROM pgbench_accounts WHERE bid < 189 OR abalance > 100 LIMIT 20;'
sql 'EXPLAIN (ANALYZE,COSTS,SETTINGS,BUFFERS,TIMING,SUMMARY,WAL,VERBOSE) SELECT count(*) FROM pgbench_accounts WHERE bid < 189 OR abalance > 100;'
echo 'Task 3 — Verify preconfigured columnar flag (do not mutate existing flags)'
flag="$(scalar 'SHOW google_columnar_engine.enabled;')"
[[ "$flag" == on ]] || { echo "Columnar engine flag is $flag, expected on" >&2; exit 1; }
echo 'Task 4 — Ensure extension exists'
sql 'CREATE EXTENSION IF NOT EXISTS google_columnar_engine;'
[[ "$(scalar "SELECT count(*) FROM pg_extension WHERE extname='google_columnar_engine';")" == 1 ]] || exit 1
echo 'Task 5 — Populate column store and compare plan (checkpoint 50)'
loaded="$(scalar "SELECT count(*) FROM g_columnar_relations WHERE relation_name='pgbench_accounts' AND status='Usable';")"
if [[ "$loaded" == 0 ]]; then
  sql "SELECT google_columnar_engine_add('pgbench_accounts');"
fi
sql 'EXPLAIN (ANALYZE,COSTS,SETTINGS,BUFFERS,TIMING,SUMMARY,WAL,VERBOSE) SELECT count(*) FROM pgbench_accounts WHERE bid < 189 OR abalance > 100;'
loaded="$(scalar "SELECT count(*) FROM g_columnar_relations WHERE relation_name='pgbench_accounts' AND status='Usable';")"
[[ "$loaded" -ge 1 ]] || { echo 'Column store not usable; check memory capacity' >&2; exit 1; }
REMOTE
chmod 600 "$workdir/remote.sh"
remote_copy "$workdir/remote.sh" alloydb-client "$ZONE" "$REMOTE_DIR/remote.sh"
remote_run alloydb-client "$ZONE" "bash '$REMOTE_DIR/remote.sh' '$IP'"
remote_run alloydb-client "$ZONE" "rm -f '$REMOTE_DIR/remote.sh' && rmdir '$REMOTE_DIR'"
printf '%s\n' "${GREEN}Both checkpoints are configured; click Check my progress in Google Skills.${RESET}" 'Runtime/grader not independently verified.'
