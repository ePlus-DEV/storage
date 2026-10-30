# Enable Native Exchange Messaging and Clustering with Aeron - GSP1314

## Overview

This lab demonstrates a replicated Aeron Cluster for an auction workload. Three preprovisioned Compute Engine VMs run Aeron members, elect a leader, process bids, recover from leader failure, and synchronize a restarted member. This guide is independently written from the public official task list.

### What you'll do

- Start the three Aeron members and confirm leader election.
- Send 20 sample auction bids.
- Inspect Aeron statistics, membership, and process IDs.
- Stop the elected leader, observe failover, then rejoin it while processing 300 bids.

## Setup and requirements

### Before you click the Start Lab button

Open the [official GSP1314 lab](https://www.cloudskillsboost.google/focuses/124773?parent=catalog). Start it in a private browser and use **only** the temporary student account supplied in the lab panel. Never publish passwords, usernames, project IDs, or access tokens. Wait for the three supplied VMs named aeron-cluster-node1, aeron-cluster-node2, and aeron-cluster-node3 to be running. The Aeron sample software is already installed; do not create new VMs.

### Activate Cloud Shell

Open and authorize Cloud Shell, then identify the active project, zones, and internal IPs:

```bash
gcloud config get-value project
gcloud compute instances list --format='table(name,zone,status,networkInterfaces[0].networkIP)'
for n in 1 2 3; do
  VM="aeron-cluster-node$n"
  ZONE="$(gcloud compute instances list --filter="name=$VM" --format='value(zone.basename())' | head -n 1)"
  IP="$(gcloud compute instances describe "$VM" --zone="$ZONE" --format='value(networkInterfaces[0].networkIP)')"
  printf '%s | %s | %s\n' "$VM" "$ZONE" "$IP"
done
```

Record the private addresses in node1,node2,node3 order. The script automatically discovers project and zone instead of hardcoding them.

## Task 1. Start the Aeron Cluster

Open SSH terminals to all three VMs. Map node1 to member 0, node2 to member 1, and node3 to member 2. On each VM, set THIS_HOST to that VM's internal IP, and HOST_NAMES to the comma-separated IPs of all three VMs in order. For node1, use:

```bash
export THIS_HOST='<NODE1_PRIVATE_IP>'
export HOST_NAMES='<NODE1_PRIVATE_IP>,<NODE2_PRIVATE_IP>,<NODE3_PRIVATE_IP>'
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
cd "$HOME/aeron/aeron-samples/scripts/cluster"
if ! grep -q 'java.base/sun.nio.ch=ALL-UNNAMED' script-common; then
  sed -i '/^ADD_OPENS=/ s|"$| --add-opens java.base/sun.nio.ch=ALL-UNNAMED"|' script-common
fi
./basic-auction-cluster 0
```

Repeat on node2 with THIS_HOST set to its IP and the final argument changed to 1; repeat on node3 with argument 2. Leave the three terminals running. Confirm that leader election and follower readiness appear in the logs.

### Test completed task

Click **Check my progress** for Start the Aeron Cluster (30 points). The script cannot confirm grader success.

## Task 2. Start the Sample Auction Client

Open another SSH terminal on node1, keeping its cluster member running. Set the same IP variables and send 20 bids from client ID 101:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export THIS_HOST='<NODE1_PRIVATE_IP>'
export HOST_NAMES='<NODE1_PRIVATE_IP>,<NODE2_PRIVATE_IP>,<NODE3_PRIVATE_IP>'
cd "$HOME/aeron/aeron-samples/scripts/cluster"
./basic-auction-client 101 20
```

Review the client output and cluster logs for the sent bids and updated auction state. Actual values and timestamps may vary.

### Test completed task

Click **Check my progress** for Start the Auction Client (30 points).

## Task 3. Run Administrative Tools For the Cluster

From node1, run the Aeron statistics command:

```bash
cd "$HOME/aeron/aeron-samples/scripts"
./aeron-stat watch=false
```

Inspect the cluster status, leader member ID, and PID:

```bash
cd "$HOME/aeron/aeron-samples/scripts/cluster"
JAR="$(find "$HOME/aeron/aeron-all/build/libs" -maxdepth 1 -name 'aeron-all-*.jar' -print -quit)"
java -cp "$JAR" io.aeron.cluster.ClusterTool node0/cluster list-members
java -cp "$JAR" io.aeron.cluster.ClusterTool node0/cluster describe
java -cp "$JAR" io.aeron.cluster.ClusterTool node0/cluster pid
```

Read the leaderMemberId value; do not assume member 0 is always the leader. This inspection has no separate grader checkpoint.

## Task 4. Simulate Failover of the Cluster

Identify the current leader from Task 3. On that member's VM, query its PID using the appropriate node0/cluster, node1/cluster, or node2/cluster path:

```bash
cd "$HOME/aeron/aeron-samples/scripts/cluster"
JAR="$(find "$HOME/aeron/aeron-all/build/libs" -maxdepth 1 -name 'aeron-all-*.jar' -print -quit)"
java -cp "$JAR" io.aeron.cluster.ClusterTool node0/cluster pid
```

The example targets member 0; replace it with the observed leader. Verify the returned PID belongs to the Aeron cluster, then stop only that process:

```bash
ps -p '<AERON_PID>' -o pid,args
kill -9 '<AERON_PID>'
```

From a surviving VM, inspect list-members again and wait until another member is elected. Do not stop the VMs or unrelated processes.

### Test completed task

Click **Check my progress** for Simulate Failover by Stopping the Leader Node (30 points).

## Task 5. Restart the Previous Leader Node

On a surviving node, verify the new leader and launch a 300-bid client session, using the correct private IP for THIS_HOST:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export THIS_HOST='<CURRENT_NODE_PRIVATE_IP>'
export HOST_NAMES='<NODE1_PRIVATE_IP>,<NODE2_PRIVATE_IP>,<NODE3_PRIVATE_IP>'
cd "$HOME/aeron/aeron-samples/scripts/cluster"
./basic-auction-client 101 300
```

While the bids are being sent, return to the stopped member's VM. Restart its original cluster member ID:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export THIS_HOST='<PREVIOUS_LEADER_PRIVATE_IP>'
export HOST_NAMES='<NODE1_PRIVATE_IP>,<NODE2_PRIVATE_IP>,<NODE3_PRIVATE_IP>'
cd "$HOME/aeron/aeron-samples/scripts/cluster"
./basic-auction-cluster '<PREVIOUS_LEADER_MEMBER_NUMBER>'
```

Check membership and recovery logs for catch-up activity. If the client finishes before recovery is observable, repeat the batch as the official lab permits.

### Test completed task

Click **Check my progress** for Start the Previous Leader Node (10 points). The checkpoints total 100 points, but this guide does not claim grader PASS.

---

## Solution of Lab

### Quick

After the Draft PR is merged into main, run exactly these two commands in an authorized lab Cloud Shell. The URL deliberately points to main and cannot retrieve the new script before merge.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1314/lab.sh
source lab.sh
```

The script detects the project, VM zones, and private IPs; starts the cluster; submits bids; inspects membership; performs the required failover; and attempts to restore the previous leader. FORCE_COLOR=1 enables colors through tee, while NO_COLOR disables them. Task 4 intentionally stops the elected leader's lab process.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

The five manual Task sections above are the full walkthrough; a video is not necessary.

## Sources and verification

- [Official GSP1314 instructions, five Tasks, and four checkpoints](https://www.cloudskillsboost.google/focuses/124773?parent=catalog)
- [Aeron open-source project](https://github.com/real-logic/aeron)
- [Compute Engine SSH CLI documentation](https://cloud.google.com/sdk/gcloud/reference/compute/ssh)

**Status:** static validated only; runtime/grader unverified. Google Skills screenshots are not embedded because permission to reuse the original images has not been verified. This file is ready for Hashnode review, not published.
