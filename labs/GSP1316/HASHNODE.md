# Establish Site to Site Connectivity with HA-VPN using NCC - GSP1316

## Overview

Network Connectivity Center (NCC) provides a hub-and-spoke control plane for routing between two simulated branch offices. This lab starts with two virtual machines, firewall rules, VPC networks, Cloud Routers and HA VPN tunnels already provisioned. You create an NCC hub, attach two regional VPN spokes with site-to-site transfer enabled, test traffic in both directions, and optionally clean up after grading.

### What you'll do

- Discover the two office regions and the existing routing-side HA VPN tunnel pairs.
- Create an NCC hub and one VPN spoke per office.
- Enable site-to-site data transfer for each spoke and check the 100-point grader.
- Ping each office VM from the other using their actual internal IPs.
- Remove the new spokes and hub only after checkpoint review.

## Setup and requirements

### Before you click the Start Lab button

Start [the official GSP1316 lab](https://www.skills.google/focuses/124818?parent=catalog) when you have enough time. Use a private browser and the temporary student account shown in the lab panel, not your own account. Do not share student credentials or save secrets in GitHub. The lab provisions the VPCs, firewall rules, HA VPN and two office VMs; this guide does not recreate them.

### Activate Cloud Shell

Activate Cloud Shell from the lab's Google Cloud console and authorize the temporary account. Check the active project, enable the Network Connectivity API, and discover both office regions from the pre-provisioned VMs.

```bash
gcloud auth list
gcloud config get-value project
export PROJECT_ID="$(gcloud config get-value project)"
gcloud services enable networkconnectivity.googleapis.com
export ZONE1="$(gcloud compute instances list --filter='name=onprem-office1-vm' --format='value(zone)' | head -n1 | awk -F/ '{print $NF}')"
export ZONE2="$(gcloud compute instances list --filter='name=onprem-office2-vm' --format='value(zone)' | head -n1 | awk -F/ '{print $NF}')"
export REGION1="${ZONE1%-*}"
export REGION2="${ZONE2%-*}"
printf 'Office1: %s; Office2: %s\n' "$REGION1" "$REGION2"
```

## Verify existing Google Cloud resources

The official lab provisions the VPCs, office VMs, HA VPN gateways, Cloud Routers and firewall rules. Inspect rather than recreate them. Each office needs two **routing-vpc-side** tunnels in its own region; do not attach the on-premises-side tunnels to NCC.

```bash
gcloud compute networks describe routing-vpc
gcloud compute instances list --filter='name~onprem-office'
gcloud compute vpn-tunnels list
gcloud compute routers list
gcloud compute vpn-gateways list
```

Inspect the VPN tunnel details and their attached Cloud Router network before selecting each pair. The automated script discovers tunnel names by region and checks the associated Cloud Router belongs to routing-vpc. If it cannot identify exactly two in a region, it stops instead of guessing. [View the original site-to-site network diagram in Google Skills](https://www.skills.google/focuses/124818?parent=catalog); its reuse rights have not been verified, so it is not rehosted here.

## Configure data transfer connectivity

NCC's site-to-site mode allows two regional VPN spokes attached to the same hub to exchange dynamic routes. Each spoke must reference both redundant tunnels for its office.

## Task 1. Create a hub

In the console, open Network Connectivity Center, select Create hub, enter a descriptive hub name, and confirm the temporary lab project. The command-line equivalent below uses site-to-site-hub. Create it only if it does not already exist.

```bash
export HUB_NAME=site-to-site-hub
gcloud network-connectivity hubs create "$HUB_NAME"
gcloud network-connectivity hubs describe "$HUB_NAME"
```

The official UI proceeds to the spoke configuration from the hub creation wizard. A hub alone does not satisfy the grader; both spokes must also be attached.

## Task 2. Define spokes

### Spoke for office 1

In the NCC console choose Add a spoke, type VPN tunnel, name office-1-spoke, choose the region discovered for onprem-office1-vm, enable **Site-to-site data transfer**, select the routing-vpc network and attach the two routing-side VPN tunnels from that region. You can perform the equivalent operation using gcloud after confirming the tunnel names.

```bash
export OFFICE1_TUNNEL_A='<verified-routing-side-tunnel-1>'
export OFFICE1_TUNNEL_B='<verified-routing-side-tunnel-2>'
gcloud network-connectivity spokes linked-vpn-tunnels create office-1-spoke \
  --hub="$HUB_NAME" --region="$REGION1" \
  --vpn-tunnels="$OFFICE1_TUNNEL_A,$OFFICE1_TUNNEL_B" \
  --site-to-site-data-transfer
```

### Spoke for office 2

Repeat the same procedure for the second office, using the region of onprem-office2-vm and its two **different** routing-side VPN tunnels. Do not assume both offices are in the same region.

```bash
export OFFICE2_TUNNEL_A='<verified-routing-side-tunnel-1>'
export OFFICE2_TUNNEL_B='<verified-routing-side-tunnel-2>'
gcloud network-connectivity spokes linked-vpn-tunnels create office-2-spoke \
  --hub="$HUB_NAME" --region="$REGION2" \
  --vpn-tunnels="$OFFICE2_TUNNEL_A,$OFFICE2_TUNNEL_B" \
  --site-to-site-data-transfer
gcloud network-connectivity hubs list-spokes "$HUB_NAME"
```

Replace the four angle-bracket placeholders only with tunnel names discovered in your **own authorized lab**. The Bash solution resolves them automatically and stops on ambiguous results. Verify that the spokes are active and attached to the intended hub.

### Test completed task

Click **Check my progress** for **Create a Hub and Spokes** (100 points). No grader result is claimed by this guide.

## Task 3. Verify the configuration

Determine the private IP address of each office VM. Then connect to the first VM and ping the second VM's internal IP; repeat in the opposite direction. The network should already contain the firewall rules and VPN infrastructure provided by the lab.

```bash
export IP1="$(gcloud compute instances describe onprem-office1-vm --zone="$ZONE1" --format='value(networkInterfaces[0].networkIP)')"
export IP2="$(gcloud compute instances describe onprem-office2-vm --zone="$ZONE2" --format='value(networkInterfaces[0].networkIP)')"
gcloud compute ssh onprem-office1-vm --zone="$ZONE1" --command="ping -c 5 $IP2"
gcloud compute ssh onprem-office2-vm --zone="$ZONE2" --command="ping -c 5 $IP1"
```

Successful ICMP replies in both directions demonstrate reachability through the VPN/NCC topology. If either direction fails, inspect BGP tunnel status, NCC spoke attachment, routing and firewall rules. The official lab lists one graded checkpoint for the hub and spokes; this traffic test is a separate manual verification task.

## Task 4. Delete resources

After confirming the 100-point checkpoint and connectivity, delete only the two NCC spokes and hub created for this lab. The original VPCs, gateways, routers and VMs are pre-provisioned and must not be removed by this cleanup.

```bash
gcloud network-connectivity spokes delete office-1-spoke --region="$REGION1" --quiet
gcloud network-connectivity spokes delete office-2-spoke --region="$REGION2" --quiet
gcloud network-connectivity hubs delete "$HUB_NAME" --quiet
```

The script intentionally skips cleanup unless CLEANUP=1 and CONFIRM_CLEANUP=YES are set after grading. This avoids destroying resources before the checkpoint is checked.

---

## Solution of Lab

### Quick

The two canonical commands below reference main. **The script is not available at this URL until the Draft PR is merged.**

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1316/lab.sh
source lab.sh
```

The script discovers project, office zones/regions, both pairs of routing-side HA VPN tunnels, and the office VMs' internal IP addresses. It refuses ambiguous tunnel discovery, reuses existing hub/spokes where safe, enables site-to-site transfer, performs two-way ping checks, and keeps cleanup opt-in. TTY colors are on by default; FORCE_COLOR=1 enables color in piped output, while NO_COLOR disables it.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Use the full manual workflow above. The original Google Skills diagram is linked rather than copied because its public embedding rights were not established.

### Sources and verification

- [Google Skills — GSP1316 official lab](https://www.skills.google/focuses/124818?parent=catalog)
- [Google Cloud — Connect two sites by using VPN spokes](https://cloud.google.com/network-connectivity/docs/network-connectivity-center/tutorials/connecting-two-offices-with-vpns)
- [gcloud linked-vpn-tunnels create reference](https://cloud.google.com/sdk/gcloud/reference/network-connectivity/spokes/linked-vpn-tunnels/create)
- Original lab content is copyrighted by Google LLC; this guide is independently paraphrased. Script: Copyright (c) 2026 ePlus.DEV | Unlicense.
- **static validated only; runtime/grader unverified**. CI is not proof of a grader PASS.
