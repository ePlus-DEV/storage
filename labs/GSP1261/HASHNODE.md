# Getting Started with Google Cloud NetApp Volumes - GSP1261

## Overview

Google Cloud NetApp Volumes offers managed file shares mounted by Linux over NFS. In this lab you provision a Premium storage pool in the default VPC, create a 100-GiB NFSv3 volume, and mount it on the pre-provisioned Linux VM. This guide is independently written from the official task sequence.

### What you'll do

- Configure Private Services Access and create `pool1` (Premium, 2,048 GiB).
- Create `volume1` with a 100-GiB NFSv3 export named `share1`.
- Mount the share on `vm1` and verify that the filesystem is accessible.

## Setup and requirements

### Before you click the Start Lab button

1. Open [Google Skills GSP1261](https://www.skills.google/focuses/124544?parent=catalog), click **Start Lab**, and note the time limit. Lab time cannot be paused.
2. Use an incognito/private browser window and **only** the temporary student account provided in the lab panel. Do not sign in with your personal Cloud account, which could incur charges.
3. Click **Open Google Cloud console**, sign in with the temporary credentials, accept the lab's initial prompts, and confirm the temporary project is selected.
4. Never publish lab usernames, passwords, or temporary project identifiers in GitHub or Hashnode.

### Activate Cloud Shell

Click **Activate Cloud Shell** in the console, authorize access, and verify the active account and project:

```bash
gcloud auth list
gcloud config get-value project
```

Discover the project, VM zone, and region without hardcoding any location:

```bash
export PROJECT_ID="$(gcloud config get-value project)"
export VM_ZONE="$(gcloud compute instances list \
  --project="$PROJECT_ID" --filter='name=vm1' \
  --format='value(zone)' | awk -F/ 'NF {print $NF}')"
export REGION="$(printf '%s' "$VM_ZONE" | sed 's/-[a-z]$//')"
printf 'Project=%s, Zone=%s, Region=%s\n' "$PROJECT_ID" "$VM_ZONE" "$REGION"
```

Verify that the lab-provisioned VM is named `vm1` and attached to the `default` VPC. If the lab explicitly specifies another NetApp region, use that lab-assigned region instead of the VM-derived hint.

## Task 1. Create a storage pool

A storage pool determines the shared service level, network, region, and capacity for its volumes.

### Configure Private Services Access

1. In the Google Cloud console search bar, open **NetApp Volumes** and enable the NetApp API.
2. Choose **Storage pools → Create**.
3. In the connection setup section, select **Set up connection**, then **Use an automatically allocated IP range**, and **Create connection**. Wait until the connection completes.

The Cloud Shell equivalent begins by enabling both APIs:

```bash
gcloud services enable netapp.googleapis.com servicenetworking.googleapis.com \
  --project="$PROJECT_ID"
```

Inspect any existing private service connection:

```bash
gcloud services vpc-peerings list --project="$PROJECT_ID" \
  --network=default --service=servicenetworking.googleapis.com
```

**Only if the connection is absent**, reserve an automatically allocated private range and connect it. Do not replace an existing range or peering.

```bash
gcloud compute addresses create eplus-gsp1261-netapp \
  --project="$PROJECT_ID" --global --purpose=VPC_PEERING \
  --prefix-length=24 --network=default

gcloud services vpc-peerings connect --project="$PROJECT_ID" \
  --network=default --service=servicenetworking.googleapis.com \
  --ranges=eplus-gsp1261-netapp
```

### Create the storage pool

Fill out the console form using the following official lab requirements:

| Setting | Required value |
|---|---|
| Storage pool name | `pool1` |
| Region | Lab-assigned region |
| Service level | Premium |
| Capacity | 2,048 GiB |
| VPC | `default` |
| Active Directory policy | None |

Click **Create**. The corresponding CLI command is:

```bash
gcloud netapp storage-pools create pool1 \
  --project="$PROJECT_ID" --location="$REGION" \
  --service-level=premium --capacity=2048 --network=name=default
```

Run the create command only when `pool1` does not already exist. Wait until the pool becomes `READY`; provisioning may take several minutes. Inspect it with:

```bash
gcloud netapp storage-pools describe pool1 \
  --project="$PROJECT_ID" --location="$REGION" \
  --format='yaml(name,state,serviceLevel,capacityGib)'
```

### Test completed task

Click **Check my progress** for **Create a storage pool** (40 points). The script and resource inspection do not themselves prove that the grader passed.

## Task 2. Create a volume

1. Open **NetApp Volumes → Volumes → Create**.
2. Select storage pool `pool1` and set the following volume properties.
3. Expand **Export rules → Add Rule**, enter the allowed client range and permissions, click **Done**, then **Create**.

| Setting | Required value |
|---|---|
| Volume name | `volume1` |
| Storage pool | `pool1` |
| Share name | `share1` |
| Capacity | 100 GiB |
| Protocol | NFSv3 |
| Allowed clients | `10.128.0.0/9` |
| Access | Read & Write |
| Root access | On |
| Block deletion when clients connected | Off |

The equivalent command is:

```bash
gcloud netapp volumes create volume1 \
  --project="$PROJECT_ID" --location="$REGION" \
  --storage-pool=pool1 --capacity=100 \
  --protocols=nfsv3 --share-name=share1 \
  --export-policy=access-type=READ_WRITE,allowed-clients=10.128.0.0/9,has-root-access=true,nfsv3=true
```

Only create the volume if it does not already exist. The broad client CIDR and root access are explicitly specified by this **training lab** and are not suitable as default production security settings. For production, narrow exports to trusted clients and restrict root privileges.

Wait for the volume to reach `READY`, then verify its configuration and discover its dynamically assigned NFS endpoint:

```bash
gcloud netapp volumes describe volume1 \
  --project="$PROJECT_ID" --location="$REGION" \
  --format='yaml(name,state,shareName,protocols,capacityGib,exportPolicy,mountOptions)'
```

### Test completed task

Click **Check my progress** for **Create a volume** (40 points). Check that the volume and its NFS export exist and are ready.

## Task 3. Mount the volume

1. In **Compute Engine → VM instances**, locate `vm1` and click **SSH**.
2. Return to **NetApp Volumes → Volumes**, open the menu for `volume1`, and choose **Mount Instructions**.
3. Record the **unique IP address** from the mount instructions. Do not copy another lab's address.
4. On the SSH session for `vm1`, install NFS utilities, create the mount directory, and mount the export.

You can discover the endpoint in Cloud Shell:

```bash
export SERVER_IP="$(gcloud netapp volumes describe volume1 \
  --project="$PROJECT_ID" --location="$REGION" \
  --format='value(mountOptions[0].ipAddress)')"
printf 'Mount endpoint: %s\n' "$SERVER_IP"
```

SSH to the VM using the discovered zone:

```bash
gcloud compute ssh vm1 --project="$PROJECT_ID" --zone="$VM_ZONE"
```

Inside `vm1`, run:

```bash
sudo apt-get update -qq
sudo apt-get install -y nfs-common
sudo mkdir -p /share1
```

Substitute the actual IP from Mount Instructions into the next command. Execute it **inside vm1**, not in Cloud Shell:

```bash
sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp \
  <VOLUME_IP>:/share1 /share1
findmnt /share1
df -h | grep share1
```

If `/share1` is already mounted, inspect the existing mount rather than mounting it again. The output should identify the NFS export and mount path; actual IPs and sizes vary by lab.

### Test completed task

Click **Check my progress** for **Mount the volume** (20 points). Successful Linux mounting and a Google Skills grader PASS are separate checks.

---

## Solution of Lab

### Quick

After the Draft PR has been reviewed and merged to `main`, execute exactly these two commands in the temporary lab's Cloud Shell. **This Quick URL will not work before the PR is merged.**

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1261/lab.sh
source lab.sh
```

The script automatically detects the temporary project, VM zone, and region; reuses existing resources; creates the pool and volume if absent; and mounts the NFS export on `vm1`. It does not delete resources. To test an unmerged PR, use the SHA-pinned command in the PR description.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Follow the complete console and Cloud Shell walkthrough in Tasks 1–3 above.

### Sources and verification

- [Google Skills — official GSP1261 lab](https://www.skills.google/focuses/124544?parent=catalog)
- [Google Cloud — Create a NetApp storage pool](https://docs.cloud.google.com/netapp/volumes/docs/configure-and-use/storage-pools/create-storage-pool)
- [Google Cloud — Create a NetApp volume](https://docs.cloud.google.com/netapp/volumes/docs/configure-and-use/volumes/create-volume)
- [Google Cloud — Configure networking and Private Services Access](https://docs.cloud.google.com/netapp/volumes/docs/plan-and-prepare/networking)
- [Google Cloud — Connect NFS clients](https://docs.cloud.google.com/netapp/volumes/docs/connect-clients/connect-nfs-clients)

**Verification:** static validated only; runtime/grader unverified. No PASS/100 score is claimed. Official Google Skills screenshots have not been embedded because their reuse rights have not been verified; consult the official lab for the original illustrations.
