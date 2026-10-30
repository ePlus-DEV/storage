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
  local vm="$1" zones default_zone
  default_zone="$(gcloud compute project-info describe --project="$PROJECT_ID" --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)"
  zones="$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$vm" --format='value(zone)' 2>/dev/null | awk -F/ 'NF && $NF != "" {print $NF}' | sort -u)"
  if [[ -z "$zones" ]]; then
    printf '%sERROR: Required VM %s does not exist in project %s.%s\n' "$RED" "$vm" "$PROJECT_ID" "$RESET" >&2
    printf '%s\n' "Detected default zone: ${default_zone:-unset}" "Existing VMs:" >&2
    gcloud compute instances list --project="$PROJECT_ID" --format='table(name,zone,status)' >&2 || true
    fail "Lab provisioning may be incomplete, or this is a different lab. Do not substitute startup-vm for $vm without verification."
  fi
  [[ "$zones" != *$'\n'* ]] || fail "Multiple zones found for $vm: $zones"
  [[ "$zones" =~ ^[a-z]+(-[a-z0-9]+)+[0-9]+-[a-z]$ ]] || fail "Invalid discovered zone for $vm: $zones"
  printf '%s' "$zones"
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

step 'Task 1 — Verify source database and HR tables'
SOURCE_ZONE="$(vm_zone pg14-source)"
DEST_ZONE="$(vm_zone alloydb-client)"
remote_run pg14-source "$SOURCE_ZONE" "sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d postgres -c 'SELECT count(*) FROM countries;' -c 'SELECT count(*) FROM departments;' -c 'SELECT count(*) FROM employees;' -c 'SELECT count(*) FROM jobs;' -c 'SELECT count(*) FROM locations;' -c 'SELECT count(*) FROM regions;'"
step 'Task 2 — Create PostgreSQL custom dump and upload to lab bucket (checkpoint 50)'
SOURCE_DIR="/tmp/eplus-gsp1085-$PROJECT_ID"
DEST_DIR="/tmp/eplus-gsp1085-$PROJECT_ID"
remote_run pg14-source "$SOURCE_ZONE" "mkdir -p -m 700 '$SOURCE_DIR' && sudo -u postgres pg_dump -Fc postgres > '$SOURCE_DIR/pg14_source.DMP' && test -s '$SOURCE_DIR/pg14_source.DMP'"
gcloud compute scp --quiet --project="$PROJECT_ID" --zone="$SOURCE_ZONE" "pg14-source:$SOURCE_DIR/pg14_source.DMP" "$workdir/pg14_source.DMP"
[[ -s "$workdir/pg14_source.DMP" ]] || fail 'Dump missing'
gcloud storage buckets describe "gs://$PROJECT_ID" --project="$PROJECT_ID" >/dev/null || fail 'Lab-created bucket not found'
if ! gcloud storage ls "gs://$PROJECT_ID/pg14_source.DMP" >/dev/null 2>&1; then
  gcloud storage cp "$workdir/pg14_source.DMP" "gs://$PROJECT_ID/pg14_source.DMP"
else
  printf 'Lab dump object already exists; preserving it on rerun.\n'
fi
step 'Task 3 — Restore into preprovisioned AlloyDB (checkpoint 50)'
wait_primary
IP="$(instance_ip)"
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail 'No valid AlloyDB private IP found'
remote_run alloydb-client "$DEST_ZONE" "mkdir -p -m 700 '$DEST_DIR'"
remote_copy "$workdir/pg14_source.DMP" alloydb-client "$DEST_ZONE" "$DEST_DIR/pg14_source.DMP"
cat > "$workdir/restore.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -z "${PGPASSWORD:-}" ]]; then
  [[ -r /dev/tty ]] || { echo 'Interactive SSH TTY required for the lab-provided database password' >&2; exit 2; }
  read -r -s -p 'Lab-provided postgres password: ' PGPASSWORD </dev/tty
  printf '\n' >/dev/tty
  [[ -n "$PGPASSWORD" ]] || { echo 'Password required' >&2; exit 2; }
  export PGPASSWORD
fi
IP="$1"; DUMP="$2"
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || exit 2
[[ -s "$DUMP" ]] || { echo 'Dump not found' >&2; exit 1; }
psql_cmd() { psql -X -At -v ON_ERROR_STOP=1 -h "$IP" -U postgres -d postgres -c "$1"; }
existing="$(psql_cmd "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('countries','departments','employees','jobs','locations','regions');")"
if [[ "$existing" == 0 ]]; then
  pg_restore -l "$DUMP" | awk '/ EXTENSION / {print ";" $0; next} {print}' > "${DUMP%.DMP}.toc"
  pg_restore --exit-on-error --no-owner --no-privileges -h "$IP" -U postgres -d postgres -L "${DUMP%.DMP}.toc" "$DUMP"
elif [[ "$existing" != 6 ]]; then
  echo "Partial destination ($existing/6 HR tables); refusing to overwrite" >&2; exit 1
fi
for table in countries departments employees jobs locations regions; do
  count="$(psql_cmd "SELECT count(*) FROM public.$table;")"
  [[ "$count" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid count for $table: $count" >&2; exit 1; }
  printf '%s rows: %s\n' "$table" "$count"
done
REMOTE
chmod 600 "$workdir/restore.sh"
remote_copy "$workdir/restore.sh" alloydb-client "$DEST_ZONE" "$DEST_DIR/restore.sh"
remote_run alloydb-client "$DEST_ZONE" "bash '$DEST_DIR/restore.sh' '$IP' '$DEST_DIR/pg14_source.DMP'"
remote_run pg14-source "$SOURCE_ZONE" "rm -f '$SOURCE_DIR/pg14_source.DMP' && rmdir '$SOURCE_DIR'"
remote_run alloydb-client "$DEST_ZONE" "rm -f '$DEST_DIR/restore.sh' '$DEST_DIR/pg14_source.DMP' '$DEST_DIR/pg14_source.toc' && rmdir '$DEST_DIR'"
printf '%s\n' "${GREEN}Both checkpoints are configured; click Check my progress in Google Skills.${RESET}" 'Runtime/grader not independently verified.'
