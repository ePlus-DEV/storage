# Protect your Google Cloud NetApp Volumes data with backup - GSP1313

## Overview

This lab introduces data protection for a managed NFS volume. You mount the pre-provisioned volume, create a regional backup vault, capture a manual backup, apply a daily/weekly/monthly backup schedule, and restore the backup into a second volume. This guide follows the five official tasks and paraphrases their instructions independently.

### What you'll do

- Mount the existing NetApp NFSv3 volume on vm1 and verify the share.
- Create vault1 in the same region as volume1.
- Write sample files and create backup1.
- Create policy1 with 30 daily, 8 weekly and 12 monthly retained backups and attach it to volume1.
- Restore backup1 as restore-from-volume1 in pool1.

## Setup and requirements

### Before you click the Start Lab button

Open the [official GSP1313 lab](https://www.skills.google/focuses/124383?parent=catalog) in a private browser. Use only the temporary Google Skills credentials. Do not copy usernames, passwords, or project IDs into public scripts. The timed lab provisions volume1, pool1 and VM vm1. Do not replace these resources or choose an unrelated region.

### Activate Cloud Shell

Activate Cloud Shell in the lab's console. Confirm the temporary account and project, then locate volume1. Derive the region from the volume's resource name and vm1's zone from the existing VM rather than hardcoding either location.

```bash
gcloud auth list
gcloud config get-value project
export PROJECT_ID="$(gcloud config get-value project)"
gcloud netapp volumes list
export VOLUME_PATH="$(gcloud netapp volumes list --format=json | jq -r '.[] | select(.name | endswith("/volumes/volume1")) | .name' | head -n1)"
export LOCATION="$(awk -F/ '{print $(NF-2)}' <<< "$VOLUME_PATH")"
export ZONE="$(gcloud compute instances list --filter='name=vm1' --format='value(zone)' | head -n1 | awk -F/ '{print $NF}')"
printf 'NetApp region: %s | VM zone: %s\n' "$LOCATION" "$ZONE"
```

The official lab includes screenshots of the NetApp UI and Cloud Shell. [View the original figures at Google Skills](https://www.skills.google/focuses/124383?parent=catalog). No original images are embedded here because permission to reuse them on Hashnode has not been established.

## Task 1. Mount the volume

In Google Cloud console, open NetApp Volumes → Volumes, locate volume1, and choose Mount Instructions. Open a separate Compute Engine tab and SSH into vm1. The mount IP is unique to the lab, so read it from volume1's metadata rather than copying another person's IP address.

```bash
gcloud netapp volumes describe volume1 --location="$LOCATION" --format='value(mountOptions.instructions)'
gcloud compute ssh vm1 --zone="$ZONE"
```

Inside vm1, install the NFS client, create the share directory, and use the NFSv3 mount command from the instructions panel. Replace the placeholder only with the export IP from your own volume.

```bash
sudo apt-get install -y nfs-common
sudo mkdir -p /share1
sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp <VOLUME_IP>:/share1 /share1
df -h | grep share1
exit
```

The Bash solution retrieves mountOptions.exportFull automatically, validates its format and mounts only if /share1 is not already mounted.

### Test completed task

Click **Check my progress** for **Mount the volume** (20 points).

## Task 2. Create a backup vault

In NetApp Volumes → Data protection → Backup vaults, choose Create. Name the vault vault1 and select the region of volume1. The equivalent CLI operation is:

```bash
gcloud netapp backup-vaults create vault1 --location="$LOCATION"
gcloud netapp backup-vaults describe vault1 --location="$LOCATION"
```

### Test completed task

Click **Check my progress** for **Create a backup vault** (20 points).

## Task 3. Create a manual backup

SSH into vm1 and add two folders and two sample text files to the mounted volume. These strings are exercise content, not credentials. Confirm the files are visible, then return to Cloud Shell.

```bash
gcloud compute ssh vm1 --zone="$ZONE"
```

```bash
sudo mkdir -p /share1/folder1 /share1/folder2
printf 'important\n' | sudo tee /share1/file1.txt
printf 'top secret\n' | sudo tee /share1/file2.txt
sudo ls -l /share1
exit
```

In the console, open volume1 → Backups → Create backup. Set the name to backup1, source to the volume's current state and destination to vault1. Alternatively:

```bash
gcloud netapp backup-vaults backups create backup1 \
  --location="$LOCATION" --backup-vault=vault1 --source-volume=volume1
gcloud netapp backup-vaults backups describe backup1 \
  --location="$LOCATION" --backup-vault=vault1
```

Wait until the backup is READY. The first backup copies the current used data; subsequent backups can be incremental. The published grader lists no separate checkpoint for the manual backup task.

## Task 4. Set a backup schedule

### Create a backup policy

Navigate to NetApp Volumes → Policies → Backup policies → Create. Use the policy name policy1 and the same region as volume1. Set the retention counts below.

| Retention period | Backups to keep |
|---|---:|
| Daily | 30 |
| Weekly | 8 |
| Monthly | 12 |

```bash
gcloud netapp backup-policies create policy1 \
  --location="$LOCATION" --enabled=true \
  --daily-backup-limit=30 --weekly-backup-limit=8 --monthly-backup-limit=12
gcloud netapp backup-policies describe policy1 --location="$LOCATION"
```

### Test completed task

Click **Check my progress** for **Create a backup policy** (20 points).

### Attach the backup policy to the volume

Open volume1 → Backups → Manage Backup Policy, enable scheduled backups, select policy1 and vault1, and save. The CLI equivalent uses the complete regional resource names:

```bash
export VAULT_PATH="projects/$PROJECT_ID/locations/$LOCATION/backupVaults/vault1"
export POLICY_PATH="projects/$PROJECT_ID/locations/$LOCATION/backupPolicies/policy1"
gcloud netapp volumes update volume1 --location="$LOCATION" \
  --backup-config="backup-policies=$POLICY_PATH,backup-vault=$VAULT_PATH,enable-scheduled-backups=true"
gcloud netapp volumes describe volume1 --location="$LOCATION" --format='yaml(backupConfig)'
```

### Test completed task

Click **Check my progress** for **Attach a backup schedule to a volume** (20 points).

## Task 5. Restore a backup

In NetApp Volumes → Volumes → volume1 → Backups, find backup1. Wait for it to finish creating, open its actions menu, and choose Create new volume from backup. Use the following fields:

| Field | Value |
|---|---|
| New volume name | restore-from-volume1 |
| Storage pool | pool1 |
| Share name | share1-restored |
| Source backup | backup1 in vault1 |

Read the source volume's capacity from its metadata, then create the restored NFSv3 volume with the same capacity and a new share name. The restore can take several minutes depending on the volume size.

```bash
export CAPACITY="$(gcloud netapp volumes describe volume1 --location="$LOCATION" --format='value(capacityGib)')"
gcloud netapp volumes create restore-from-volume1 \
  --location="$LOCATION" --storage-pool=pool1 --capacity="$CAPACITY" \
  --protocols=nfsv3 --share-name=share1-restored \
  --source-backup=backup1 --backup-vault=vault1
gcloud netapp volumes describe restore-from-volume1 --location="$LOCATION"
```

### Test completed task

Click **Check my progress** for **Restore a volume from a backup** (20 points). No grader PASS is claimed without running an authorized lab.

---

## Solution of Lab

### Quick

These two commands point to main. **They work only after the Draft PR has been reviewed and merged**; an unmerged branch does not make the main-branch URL available.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1313/lab.sh
source lab.sh
```

The script discovers the temporary project, NetApp region, NFS export and VM zone; performs the mount, backup, policy and restore tasks with safe existing-resource checks; and waits a bounded period for backup readiness. It supports terminal ANSI color, FORCE_COLOR=1 for tee and NO_COLOR override. Do not infer grader success from CI.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Use the manual steps for Tasks 1–5 above. A video matching the title exists publicly, but its contents have not been verified as a genuine manual walkthrough, so it is not linked here.

### Sources and verification

- [Google Skills — GSP1313 official lab](https://www.skills.google/focuses/124383?parent=catalog)
- [NetApp NFS client mount documentation](https://cloud.google.com/netapp/volumes/docs/connect-clients/connect-nfs-clients)
- [Backup vault management documentation](https://cloud.google.com/netapp/volumes/docs/protect-data/manage-backup-vault)
- [Restore a volume from a backup](https://cloud.google.com/netapp/volumes/docs/protect-data/create-volume-from-backup)
- The original lab text and figures are copyrighted by Google LLC; this guide is independently paraphrased. Script: Copyright (c) 2026 ePlus.DEV | Unlicense.
- **static validated only; runtime/grader unverified**. CI cannot verify Google Skills grading.
