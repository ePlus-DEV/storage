#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP1313 — Protect your Google Cloud NetApp Volumes data with backup
# static validated only; runtime/grader unverified
set -Eeuo pipefail
if [[ -n "${NO_COLOR:-}" ]]; then C='' G='' Y='' R='';
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[0m'
else C='' G='' Y='' R=''; fi
info(){ printf '%s[INFO]%s %s\n' "$C" "$R" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$Y" "$R" "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
printf '%sePlus.DEV – Starting Execution%s\n' "$C" "$R"
printf 'Copyright (c) 2026 ePlus.DEV | Unlicense\n'
for c in gcloud jq; do command -v "$c" >/dev/null || die "Missing $c"; done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Use the temporary Google Skills lab project.'
VOLUME_PATH="$(gcloud netapp volumes list --project="$PROJECT_ID" --format=json | jq -r '.[] | select(.name | endswith("/volumes/volume1")) | .name' | head -n1)"
[[ "$VOLUME_PATH" == */volumes/volume1 ]] || die 'Pre-provisioned NetApp volume1 not found.'
LOCATION="${LOCATION:-$(awk -F/ '{print $(NF-2)}' <<< "$VOLUME_PATH")}"
[[ "$LOCATION" =~ ^[a-z]+-[a-z0-9]+[0-9]$ ]] || die 'Cannot discover NetApp region.'
VOLUME_JSON="$(gcloud netapp volumes describe volume1 --project="$PROJECT_ID" --location="$LOCATION" --format=json)"
POOL="$(jq -r '.storagePool | split("/")[-1]' <<< "$VOLUME_JSON")"
[[ "$POOL" == pool1 ]] || die "Expected lab storage pool pool1, got $POOL."
CAPACITY="$(jq -r '.capacityGib' <<< "$VOLUME_JSON")"
[[ "$CAPACITY" =~ ^[0-9]+$ ]] || die 'Missing source volume capacity.'
EXPORT_FULL="$(jq -r '[.mountOptions[]? | select(.protocol == "NFSV3") | .exportFull] | first // empty' <<< "$VOLUME_JSON")"
[[ "$EXPORT_FULL" =~ ^[0-9.]+:/[A-Za-z0-9/_-]+$ ]] || die 'Missing safe NFSv3 export path; review Mount Instructions.'
ZONE="${ZONE:-$(gcloud compute instances list --project="$PROJECT_ID" --filter='name=vm1' --format='value(zone)' | head -n1 | awk -F/ '{print $NF}')}"
[[ "$ZONE" =~ ^[a-z]+-[a-z0-9]+[0-9]-[a-z]$ ]] || die 'Cannot discover vm1 zone.'
info "Project=$PROJECT_ID NetApp region=$LOCATION VM zone=$ZONE"
retry(){ local max="$1" delay="$2" i; shift 2; for ((i=1;i<=max;i++)); do
  if "$@"; then return 0; fi
  if ((i<max)); then warn "Retry $i/$max"; sleep "$delay"; fi
done; return 1; }
vault_exists(){ gcloud netapp backup-vaults describe vault1 --project="$PROJECT_ID" --location="$LOCATION" >/dev/null 2>&1; }
backup_exists(){ gcloud netapp backup-vaults backups describe backup1 --backup-vault=vault1 --project="$PROJECT_ID" --location="$LOCATION" >/dev/null 2>&1; }
policy_exists(){ gcloud netapp backup-policies describe policy1 --project="$PROJECT_ID" --location="$LOCATION" >/dev/null 2>&1; }
restore_exists(){ gcloud netapp volumes describe restore-from-volume1 --project="$PROJECT_ID" --location="$LOCATION" >/dev/null 2>&1; }
backup_ready(){ [[ "$(gcloud netapp backup-vaults backups describe backup1 --backup-vault=vault1 --project="$PROJECT_ID" --location="$LOCATION" --format='value(state)' 2>/dev/null)" == READY ]]; }

info 'Task 1: mount the pre-provisioned NetApp NFSv3 volume on vm1'
# The export is read from NetApp API, not guessed. The command is rerun-safe.
gcloud compute ssh vm1 --project="$PROJECT_ID" --zone="$ZONE" --quiet --command="sudo apt-get install -y nfs-common && sudo mkdir -p /share1 && (mountpoint -q /share1 || sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp '$EXPORT_FULL' /share1) && df -h | grep share1" || die 'NFS mount failed; inspect the lab mount instructions.'
info 'Task 1 checkpoint: Mount the volume'

info 'Task 2: create a regional backup vault'
if ! vault_exists; then
  gcloud netapp backup-vaults create vault1 --project="$PROJECT_ID" --location="$LOCATION" --quiet
fi
retry 10 10 vault_exists || die 'Backup vault not ready after bounded retries.'
info 'Task 2 checkpoint: Create a backup vault'

info 'Task 3: write test data and create a manual backup'
gcloud compute ssh vm1 --project="$PROJECT_ID" --zone="$ZONE" --quiet --command="sudo mkdir -p /share1/folder1 /share1/folder2 && printf 'important\n' | sudo tee /share1/file1.txt >/dev/null && printf 'top secret\n' | sudo tee /share1/file2.txt >/dev/null && sudo ls /share1" || die 'Could not populate mounted volume.'
if ! backup_exists; then
  gcloud netapp backup-vaults backups create backup1 --project="$PROJECT_ID" --location="$LOCATION" --backup-vault=vault1 --source-volume=volume1 --quiet
fi
retry 20 30 backup_ready || die 'Backup1 is not READY after bounded retries; inspect the backup status before proceeding.'
info 'Task 3 checkpoint: Create a manual backup'

info 'Task 4: create and attach a scheduled backup policy'
if ! policy_exists; then
  gcloud netapp backup-policies create policy1 --project="$PROJECT_ID" --location="$LOCATION" --enabled=true --daily-backup-limit=30 --weekly-backup-limit=8 --monthly-backup-limit=12 --quiet
fi
VAULT_PATH="projects/$PROJECT_ID/locations/$LOCATION/backupVaults/vault1"
POLICY_PATH="projects/$PROJECT_ID/locations/$LOCATION/backupPolicies/policy1"
gcloud netapp volumes update volume1 --project="$PROJECT_ID" --location="$LOCATION" --backup-config="backup-policies=$POLICY_PATH,backup-vault=$VAULT_PATH,enable-scheduled-backups=true" --quiet
info 'Task 4 checkpoints: Create a backup policy; Attach a policy to the volume'

info 'Task 5: restore backup1 to a new volume'
if ! restore_exists; then
  gcloud netapp volumes create restore-from-volume1 --project="$PROJECT_ID" --location="$LOCATION" --storage-pool=pool1 --capacity="$CAPACITY" --protocols=nfsv3 --share-name=share1-restored --source-backup=backup1 --backup-vault=vault1 --quiet
fi
gcloud netapp volumes describe restore-from-volume1 --project="$PROJECT_ID" --location="$LOCATION" --format='value(state)'
info 'Task 5 checkpoint: Restore a volume from a backup'
printf '%s[OK]%s Finished. static validated only; runtime/grader unverified\n' "$G" "$R"