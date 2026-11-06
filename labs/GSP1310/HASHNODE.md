# Resizing a Google Cloud NetApp Volumes volume - GSP1310

## Overview

Google Cloud NetApp Volumes supports changing a file volume's capacity while clients keep the NFS share mounted. This lab demonstrates how capacity affects available throughput for a Premium service-level volume: approximately 64 MiB/s at 1 TiB, 128 MiB/s at 2 TiB, and 32 MiB/s at 512 GiB under the lab's benchmark conditions.

### What you'll do

- Mount the preprovisioned NetApp volume on a Linux VM.
- Measure baseline write throughput with fio.
- Grow the volume to 2048 GiB, verify capacity, and retest.
- Shrink the volume to 512 GiB, verify capacity, and retest.

## Setup and requirements

### Before you click the Start Lab button

Open the [official GSP1310 lab](https://www.skills.google/focuses/124382?parent=catalog) in a private browser. Start the lab and sign in with **only the temporary account provided by the lab**. Never share credentials, private project IDs, or access tokens. The lab provisions volume1 and vm1. Do not create replacement resources.

### Activate Cloud Shell

Open Cloud Shell, authorize it, and confirm the selected project. Discover the VM zone and NetApp volume location rather than assuming a region:

```bash
gcloud config get-value project
gcloud compute instances list --filter='name=vm1' --format='table(name,zone,status)'
gcloud netapp volumes list --format='table(name,capacityGib,state)'
```

Use the location segment of the volume resource path in later commands.

## Task 1. Mount the volume

In the console, open NetApp Volumes, select volume1, and inspect **Mount instructions**. Record the unique NFS export (an IP address and share path). In a separate terminal, connect to vm1 using the Compute Engine SSH button, then install NFS utilities and mount the share:

```bash
sudo apt-get update -qq
sudo apt-get install -y nfs-common
sudo mkdir -p /share1
sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp '<NFS_IP>:/share1' /share1
df -h /share1
```

Replace the placeholder with the **exact export from your lab**. Do not guess the IP. If already mounted, skip the mount command and verify the existing mount. The expected initial capacity is approximately 1 TiB.

### Test completed task

Click **Check my progress** for Mount the volume (20 points).

## Task 2. Test the performance

The Premium service level's approximate maximum throughput is proportional to provisioned volume capacity. On vm1, run the official fio write benchmark against the mounted share:

```bash
sudo fio --directory=/share1 --ioengine=libaio --rw=write --bs=64k --iodepth=24 --size=50g --fallocate=none --direct=1 --runtime=9000 --time_based --ramp_time=5 --numjobs=8 --name=netappvolumes
```

The official walkthrough asks you to stop this test with Ctrl+C after observing the write throughput. At 1024 GiB, the approximate upper bound is 64 MiB/s. fio generates workload files and consumes I/O; only run it in the temporary lab share. The Quick script uses a bounded 10-second, smaller-data sample to avoid a 9000-second blocking benchmark. This Task has no separate grader checkpoint.

## Task 3. Grow the Google Cloud NetApp Volumes capacity

Open NetApp Volumes → Volumes → volume1 → Edit. Set the capacity to **2048 GiB** and save. Alternatively, from Cloud Shell, substitute the discovered volume location:

```bash
gcloud netapp volumes update volume1 --location='<VOLUME_LOCATION>' --capacity=2048
gcloud netapp volumes describe volume1 --location='<VOLUME_LOCATION>' --format='value(capacityGib)'
```

Wait for the update to finish. On vm1, verify the share shows the new size without unmounting:

```bash
df -h /share1
```

Repeat the fio benchmark from Task 2, then stop it after observing the result. A 2 TiB Premium volume has an approximate maximum of 128 MiB/s in this lab.

### Test completed task

Click **Check my progress** for Grow the volume capacity (40 points).

## Task 4. Shrink the Google Cloud NetApp Volumes capacity

Open volume1 → Edit and set the capacity to **512 GiB**. The volume must contain less data than the target size; do not shrink a production volume without checking actual usage. The lab uses a temporary volume.

```bash
gcloud netapp volumes update volume1 --location='<VOLUME_LOCATION>' --capacity=512
gcloud netapp volumes describe volume1 --location='<VOLUME_LOCATION>' --format='value(capacityGib)'
```

On vm1, verify the capacity and run the same fio benchmark again:

```bash
df -h /share1
sudo fio --directory=/share1 --ioengine=libaio --rw=write --bs=64k --iodepth=24 --size=50g --fallocate=none --direct=1 --runtime=9000 --time_based --ramp_time=5 --numjobs=8 --name=netappvolumes
```

Stop fio with Ctrl+C after observing throughput. The approximate maximum at 512 GiB is 32 MiB/s.

### Test completed task

Click **Check my progress** for Shrink the volume capacity (40 points). The three graded checkpoints total 100 points; this article does not claim grader PASS.

---

## Solution of Lab

### Quick

Once the Draft PR has merged into main, use exactly these two commands in an authorized lab Cloud Shell. The URL intentionally targets main and is unavailable before merge:

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1310/lab.sh
source lab.sh
```

The script detects the current project, volume location, VM zone, and NFS export; mounts the share; runs bounded fio samples; and performs both requested capacity changes. If the export cannot be discovered, it prompts for the export shown in the lab's Mount instructions. FORCE_COLOR=1 enables colored logs through tee; NO_COLOR takes priority.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Use the four manual Task sections above to complete the lab without a video.

## Sources and verification

- [Official Google Skills GSP1310 task instructions](https://www.skills.google/focuses/124382?parent=catalog)
- [Google Cloud NetApp Volumes update command](https://docs.cloud.google.com/sdk/gcloud/reference/netapp/volumes/update)
- [Google Cloud NetApp Volumes volume metadata](https://docs.cloud.google.com/netapp/volumes/docs/reference/rest/v1/projects.locations.volumes)

**Status:** static validated only; runtime/grader unverified. No unverified screenshots or YouTube links are embedded. This Markdown is prepared for Hashnode review; it has not been published.
