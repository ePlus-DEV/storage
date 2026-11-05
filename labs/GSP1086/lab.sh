#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -Eeuo pipefail
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
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
  local vm="$1" var="${2:-}" zone
  zone="$var"
  [[ -n "$zone" ]] || zone="$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$vm" --format='value(zone)' 2>/dev/null | head -n1 | awk -F/ '{print $NF}')"
  [[ -n "$zone" ]] || ask zone "Zone of $vm"
  [[ "$zone" =~ ^[a-z]+(-[a-z0-9]+)+[0-9]+-[a-z]$ ]] || fail "Invalid zone for $vm"
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

step 'Task 1 — Inspect preprovisioned AlloyDB flag'
wait_primary
IP="$(instance_ip)"
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail 'No valid private IP found'
gcloud alloydb instances describe "$INSTANCE_ID" --project="$PROJECT_ID" --cluster="$CLUSTER_ID" --region="$REGION" --format='yaml(state,ipAddress,databaseFlags)'
ZONE="$(vm_zone alloydb-client "${ZONE:-}")"
REMOTE_DIR="/tmp/eplus-gsp1086-$PROJECT_ID"
remote_run alloydb-client "$ZONE" "mkdir -p -m 700 '$REMOTE_DIR'"
cat > "$workdir/remote.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -z "${PGPASSWORD:-}" ]]; then
  [[ -r /dev/tty ]] || { echo 'Interactive SSH TTY required for the lab-provided database password' >&2; exit 2; }
  read -r -s -p 'Lab-provided postgres password: ' PGPASSWORD </dev/tty
  printf '\n' >/dev/tty
  [[ -n "$PGPASSWORD" ]] || { echo 'Password required' >&2; exit 2; }
  export PGPASSWORD
fi
IP="$1"; MODE="$2"
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || exit 2
if [[ "$MODE" == pgaudit ]]; then
  echo 'Task 2: enable pgaudit extension'
  psql -X -v ON_ERROR_STOP=1 -h "$IP" -U postgres -d postgres -c 'CREATE EXTENSION IF NOT EXISTS pgaudit;'
  psql -X -At -v ON_ERROR_STOP=1 -h "$IP" -U postgres -d postgres -c "SELECT extname FROM pg_extension WHERE extname='pgaudit';" | grep -qx pgaudit
elif [[ "$MODE" == workload ]]; then
  echo 'Task 5: monitoring workload'
  exists="$(psql -X -At -v ON_ERROR_STOP=1 -h "$IP" -U postgres -d postgres -c "SELECT to_regclass('public.pgbench_accounts') IS NOT NULL;")"
  if [[ "$exists" == f ]]; then
    pgbench -h "$IP" -U postgres -i -s 50 -F 90 -n postgres
  else
    count="$(psql -X -At -v ON_ERROR_STOP=1 -h "$IP" -U postgres -d postgres -c 'SELECT count(*) FROM public.pgbench_accounts;')"
    [[ "$count" == 5000000 ]] || { echo "Existing pgbench data has $count rows, refusing to overwrite" >&2; exit 1; }
  fi
  psql -X -v ON_ERROR_STOP=1 -h "$IP" -U postgres -d postgres -c 'SELECT count(*) AS pgbench_accounts_count FROM public.pgbench_accounts;'
  pgbench -h "$IP" -U postgres -c 50 -j 2 -P 30 -T 180 postgres
else
  echo 'Unknown mode' >&2; exit 2
fi
REMOTE
chmod 600 "$workdir/remote.sh"
remote_copy "$workdir/remote.sh" alloydb-client "$ZONE" "$REMOTE_DIR/remote.sh"
step 'Task 2 — Enable and verify pgaudit (checkpoint 40)'
remote_run alloydb-client "$ZONE" "bash '$REMOTE_DIR/remote.sh' '$IP' pgaudit"
step 'Task 3 — Create two-node read pool (checkpoint 30)'
if ! gcloud alloydb instances describe lab-instance-rp1 --project="$PROJECT_ID" --cluster="$CLUSTER_ID" --region="$REGION" >/dev/null 2>&1; then
  gcloud alloydb instances create lab-instance-rp1 --project="$PROJECT_ID" --cluster="$CLUSTER_ID" --region="$REGION" --instance-type=READ_POOL --read-pool-node-count=2 --cpu-count=2 --quiet
fi
for ((i=1;i<=30;i++)); do
  state="$(gcloud alloydb instances describe lab-instance-rp1 --project="$PROJECT_ID" --cluster="$CLUSTER_ID" --region="$REGION" --format='value(state)' 2>/dev/null || true)"
  [[ "$state" == READY ]] && break
  ((i<30)) || fail 'Read pool did not become READY'
  sleep 20
done
gcloud alloydb instances describe lab-instance-rp1 --project="$PROJECT_ID" --cluster="$CLUSTER_ID" --region="$REGION" --format='yaml(state,readPoolConfig,machineConfig)'
step 'Task 4 — Create on-demand backup (checkpoint 30)'
if ! gcloud alloydb backups describe lab-backup --project="$PROJECT_ID" --region="$REGION" >/dev/null 2>&1; then
  gcloud alloydb backups create lab-backup --project="$PROJECT_ID" --cluster="$CLUSTER_ID" --region="$REGION" --quiet
fi
for ((i=1;i<=30;i++)); do
  state="$(gcloud alloydb backups describe lab-backup --project="$PROJECT_ID" --region="$REGION" --format='value(state)' 2>/dev/null || true)"
  [[ "$state" == READY ]] && break
  ((i<30)) || fail 'Backup did not become READY'
  sleep 20
done
step 'Task 5 — Generate pgbench monitoring load (no grader checkpoint)'
remote_run alloydb-client "$ZONE" "bash '$REMOTE_DIR/remote.sh' '$IP' workload"
remote_run alloydb-client "$ZONE" "rm -f '$REMOTE_DIR/remote.sh' && rmdir '$REMOTE_DIR'"
printf '%s\n' "${GREEN}All three graded checkpoints are configured; click Check my progress in Google Skills.${RESET}" 'Monitoring/Query insights must be inspected in the console. Runtime/grader not independently verified.'
