# Protect your Google Cloud NetApp Volumes data with snapshots - GSP1312

## Overview

A NetApp Volumes snapshot preserves a point-in-time view of a filesystem. This lab uses a preprovisioned NFS volume and Linux VM to create a manual snapshot, restore an individual file, configure recurring snapshots, and revert the entire volume. Reversion is destructive to changes made after the snapshot; use **only the temporary lab resources**.

### What you'll do

- Mount the supplied NFS volume on vm1.
- Create sample files and a snapshot named snapshot1.
- Restore a deleted file from the snapshot directory.
- Configure hourly, daily, weekly, and monthly snapshot retention.
- Revert the lab volume to snapshot1 and verify recovery.

## Setup and requirements

### Before you click the Start Lab button

Open the [official NetApp snapshot lab](https://www.skills.google/focuses/124381?parent=catalog) in a private browser. Use **only the temporary credentials provided by the lab**; never paste a student password or personal project ID into public code. The lab provisions vm1 and volume1. Do not create duplicate resources or run the destructive revert on a production volume.

**Version note:** The public Google Skills page has inconsistent legacy checkpoint labels and sometimes displays a placeholder lab code. The five Task headings and procedures are consistent with the official indexed GSP1312 page, but checkpoint counts/labels must be confirmed in the active lab panel. No grader score is claimed.

### Activate Cloud Shell

Open Cloud Shell and verify the project, VM zone, and NetApp volume location:

```bash
gcloud config get-value project
gcloud compute instances list --filter='name=vm1' --format='table(name,zone,status)'
gcloud netapp volumes list --format='table(name,state,capacityGib)'
```

The volume's resource path includes its location. In the console, open NetApp Volumes → Volumes → volume1 → Mount instructions to obtain the unique NFS export IP and share path. Never invent an IP or region.

## Task 1. Mount the volume

Connect to vm1 using the Compute Engine SSH button or gcloud compute ssh with the detected zone. Install the NFS client utilities, create a mount point, and use the export path shown by your lab:

```bash
sudo apt-get update -qq
sudo apt-get install -y nfs-common
sudo mkdir -p /share1
sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp '<NFS_IP>:/share1' /share1
df -h /share1
```

If the share is already mounted, do not mount it twice. The volume should initially show approximately 1 TiB.

### Test completed task

Click **Check my progress** for the mount objective when that checkpoint is available in your active lab.

## Task 2. Create a manual snapshot

On vm1, create two directories and two small files:

```bash
sudo mkdir -p /share1/folder1 /share1/folder2
printf 'important\n' | sudo tee /share1/file1.txt
printf 'top secret\n' | sudo tee /share1/file2.txt
sudo ls -la /share1
```

In the NetApp Volumes console, select volume1 → Create snapshot, name it snapshot1, and wait until it is ready. Alternatively, use the verified CLI commands with the volume location from the earlier discovery:

```bash
gcloud netapp volumes snapshots create snapshot1 --volume=volume1 --location='<VOLUME_LOCATION>'
gcloud netapp volumes snapshots describe snapshot1 --volume=volume1 --location='<VOLUME_LOCATION>' --format='value(state)'
```

Confirm the snapshot appears in the volume's Snapshots tab and reaches READY. Do not delete an existing snapshot of the same name merely to rerun the lab.

## Task 3. Restore a file from a snapshot

In volume1 → Edit → Snapshot configuration, ensure the snapshot directory is visible. The CLI equivalent is:

```bash
gcloud netapp volumes update volume1 --location='<VOLUME_LOCATION>' --snapshot-directory=true
```

On vm1, remove only the first sample file, inspect the snapshot directory, and restore it:

```bash
sudo rm -f /share1/file1.txt
sudo ls -la /share1
sudo ls -la /share1/.snapshot
sudo ls -la /share1/.snapshot/snapshot1
sudo cp /share1/.snapshot/snapshot1/file1.txt /share1/file1.txt
sudo ls -la /share1
```

The restored file should contain the original sample text. This is a file-level recovery and does not revert the whole volume.

## Task 4. Schedule the snapshots of a volume

Open volume1 → Edit → Snapshot configuration. Enable scheduled snapshots and enter the following settings:

| Schedule | Retain | Time |
|---|---:|---|
| Hourly | 24 | Minute 0 |
| Daily | 7 | 00:00 |
| Weekly | 8 | Sunday 00:00 |
| Monthly | 3 | Day 1 at 00:00 |

Save the volume. For CLI automation, the script uses the documented NetApp Volumes REST PATCH method with updateMask=snapshotPolicy, including enabled=true and all four schedules. It uses the current lab account's short-lived OAuth token and does not store credentials in the repository.

```bash
gcloud netapp volumes describe volume1 --location='<VOLUME_LOCATION>' --format='yaml(snapshotPolicy)'
```

Confirm the policy is enabled and the retention counts match the table.

### Test completed task

Click **Check my progress** for the scheduled snapshot/volume update objective when available. The public checkpoint panel has inconsistent labels; use the current lab UI as the source of truth.

## Task 5. Restore the entire volume from a snapshot

**Warning:** Reverting replaces the current volume contents with snapshot1's point-in-time state. This cannot be undone for changes made after that snapshot. Use only volume1 in the temporary lab.

On vm1, delete the four sample items and verify they are absent:

```bash
sudo rm -f /share1/file1.txt /share1/file2.txt
sudo rm -rf /share1/folder1 /share1/folder2
sudo ls -la /share1
```

In NetApp Volumes → volume1 → Snapshots, locate snapshot1 and select Revert. Review the warning and confirm by entering volume1. The CLI alternative is:

```bash
gcloud netapp volumes revert volume1 --location='<VOLUME_LOCATION>' --snapshot=snapshot1
```

After the operation completes, inspect the mounted share:

```bash
sudo ls -la /share1
sudo test -f /share1/file1.txt
sudo test -f /share1/file2.txt
```

The original files and directories should return. Verify the relevant completion objective in the active lab panel; no grader result has been verified.

---

## Solution of Lab

### Quick

After the Draft PR is merged into main, run exactly these two commands in an authorized lab Cloud Shell. The URL intentionally targets main and is unavailable until merge.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1312/lab.sh
source lab.sh
```

The script discovers the project, VM zone, volume location, and NFS export; creates snapshot1, restores a file, configures the four schedules, and reverts the temporary volume. It performs bounded retries and enables FORCE_COLOR through tee while respecting NO_COLOR. The revert step is intentionally destructive to the lab volume's post-snapshot changes.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Follow all five manual Task sections above to complete the lab without a video.

## Sources and verification

- [Google Skills official NetApp snapshot lab](https://www.skills.google/focuses/124381?parent=catalog)
- [NetApp Volumes snapshot REST resource and states](https://docs.cloud.google.com/netapp/volumes/docs/reference/rest/v1/projects.locations.volumes.snapshots)
- [NetApp Volumes snapshot policy schema](https://docs.cloud.google.com/netapp/volumes/docs/reference/rest/v1/projects.locations.volumes)
- [NetApp Volumes PATCH API](https://docs.cloud.google.com/netapp/volumes/docs/reference/rest/v1/projects.locations.volumes/patch)
- [NetApp Volumes revert command](https://docs.cloud.google.com/sdk/gcloud/reference/netapp/volumes/revert)

**Status:** static validated only; runtime/grader unverified. The public page's legacy checkpoint labels need active-lab confirmation. No unverified screenshots or YouTube links are embedded. This is a Hashnode-ready draft, not a published article.
