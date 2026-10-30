# Exploring Memorystore for Redis Cluster - GSP1254

## Overview

This guide covers the verified high-level checkpoints for **Exploring Memorystore for Redis Cluster (GSP1254)**. The Google Skills lab page currently requires sign-in, so the full task prose, RedisSim arguments and grader details cannot be independently re-read in this session. The walkthrough below is an **in-progress, original-language guide**, not a claim of a completed grader-tested solution.

### What you'll do

- Connect to the provided Redis client VM and inspect Redis tooling.
- Enable AOF persistence with an every-second append sync.
- Scale the Memorystore Redis Cluster to 10 shards.
- Inspect cluster settings and use the official **Check my progress** controls.

## Setup and requirements

### Before you click the Start Lab button

Open the [official Google Skills lab](https://www.skills.google/focuses/97566). Start the lab and sign in using **only the temporary credentials shown in your own lab panel**. Never paste credentials, tokens, or temporary project IDs into public issues or posts. Confirm the exact resource names and RedisSim invocation in the live instructions before executing commands.

### Activate Cloud Shell

Open Cloud Shell from the lab console. Verify that the temporary lab project is selected:

```bash
gcloud auth list
gcloud config get-value project
```

Discover the lab's actual resources instead of hardcoding a region or zone:

```bash
export PROJECT_ID="$(gcloud config get-value project)"
gcloud redis clusters list --project="$PROJECT_ID"
gcloud compute instances list --project="$PROJECT_ID"
```

Set these values using the resources shown by the commands above:

```bash
export CLUSTER="redis-cluster"   # Change if your lab uses another cluster name
export VM="redis-client"         # Change if your lab uses another VM name
read -rp "Cluster region: " REGION
read -rp "Redis client VM zone: " ZONE
```

## Task 1. Interact with the Redis Cluster

This checkpoint involves using the provided client VM, Redis commands and a RedisSim workload. Its **precise workload flags and required concurrency must be confirmed in the official lab**; the commands below are discovery steps, not a substitute for the full checkpoint.

```bash
gcloud compute ssh "$VM" \
  --project="$PROJECT_ID" \
  --zone="$ZONE"
```

On the VM:

```bash
command -v redis-cli
command -v RedisSim || true
```

Follow the current lab instructions to obtain the cluster endpoint, perform the required Redis operations, and launch the RedisSim workload with the prescribed client count. Do not assume that a successful SSH connection completes the checkpoint.

### Test completed task

Use the Task 1 **Check my progress** control after the Redis commands and workload have been completed. **No grader PASS is claimed here.**

## Task 2. Enable AOF persistence

Return to Cloud Shell if needed. Configure AOF persistence and request an every-second append sync:

```bash
gcloud redis clusters update "$CLUSTER" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --persistence-mode=aof \
  --aof-append-fsync=everysec \
  --quiet
```

Inspect the result:

```bash
gcloud redis clusters describe "$CLUSTER" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format='yaml(persistenceConfig)'
```

### Test completed task

Wait for the operation to complete and use the official Task 2 progress checker. The exact output depends on the resource state and is **not represented here as verified output**.

## Task 3. Scale the cluster to 10 shards

The official checkpoint requires a cluster with 10 shards. Ensure the required RedisSim workload is running according to the live lab instructions before scaling if the checkpoint requires simultaneous load.

```bash
gcloud redis clusters update "$CLUSTER" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --shard-count=10 \
  --quiet
```

Inspect the cluster configuration:

```bash
gcloud redis clusters describe "$CLUSTER" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format='yaml(shardCount,persistenceConfig)'
```

### Test completed task

Verify the shard count, follow any remaining workload instructions in the official lab, and use the Task 3 progress checker. **No grader PASS is claimed.**

---

## Solution of Lab

### Quick

The current PR contains a **partial WIP script**. It does **not** fully automate Task 1 or the concurrent RedisSim workload, and must not be presented as a complete one-command solution.

```bash
curl -fLO https://raw.githubusercontent.com/ePlus-DEV/storage/feat/gsp1254-redis-cluster-draft/labs/GSP1254/lab.sh
bash -n lab.sh
# Review the script and official lab instructions before running:
# bash lab.sh
```

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

---

## Sources and verification

- [Google Skills — GSP1254](https://www.skills.google/focuses/97566)
- [Google Cloud Memorystore for Redis Cluster documentation](https://cloud.google.com/memorystore/docs/cluster)
- [Draft PR #39 — source script and review](https://github.com/ePlus-DEV/storage/pull/39)

**Verification status:** Script syntax was reported as checked for an earlier local prototype, but the committed PR revision has not been independently validated with ShellCheck in this session. **Static validation incomplete; runtime/grader unverified.** Task 1 and the full RedisSim workload are pending. This Markdown is prepared for editorial review, **not published to Hashnode**.

Copyright (c) 2026 ePlus.DEV | Unlicense
