# Establish Hybrid Network Connectivity with NCC - GSP1318

## Overview

Network Connectivity Center (NCC) connects a workload VPC to a simulated on-premises network through HA VPN, Cloud Router BGP sessions, and a hub with two different spokes. This independently written walkthrough follows all five tasks and the four published checkpoints in their original order.

### What you'll do

- Establish two HA VPN tunnels between the routing and on-premises VPCs.
- Exchange BGP routes, advertise the workload subnet and set the on-premises MED priority.
- Create an NCC hub, one linked-VPC spoke and one linked-VPN spoke.
- Verify HTTP connectivity from the on-premises VM to the workload service.
- Clean up only the lab-created network resources after grading.

## Setup and requirements

### Before you click the Start Lab button

Open the [official Google Skills lab](https://www.skills.google/focuses/124809?parent=catalog). This lab is timed. Use an incognito/private window and the temporary account supplied by Google Skills; do not use personal credentials, save student passwords in scripts, or add account recovery information. Wait for the pre-provisioned routing, on-premises and workload VPCs and the VM named vm3-onprem.

### Activate Cloud Shell

Open Cloud Shell in the lab's Google Cloud console and authorize it. Check the active project and account. Derive the zone from the existing on-premises VM and the region from that zone; never substitute an arbitrary region.

```bash
gcloud auth list
gcloud config get-value project
export PROJECT_ID="$(gcloud config get-value project)"
export ZONE="$(gcloud compute instances list --filter='name=vm3-onprem' --format='value(zone)' | head -n1 | awk -F/ '{print $NF}')"
export REGION="${ZONE%-*}"
printf 'Project: %s | Zone: %s | Region: %s\n' "$PROJECT_ID" "$ZONE" "$REGION"
gcloud services enable networkconnectivity.googleapis.com
for net in routing-vpc on-prem-net-vpc workload-vpc; do gcloud compute networks describe "$net"; done
```

Verify that the three VPCs exist. The official guide includes topology diagrams for the Overview, hub, spokes, and data path. [View the original illustrations in Google Skills](https://www.skills.google/focuses/124809?parent=catalog); they are not copied or rehosted here because permission to embed them has not been established.

## Task 1. Set up hybrid connectivity

The lab uses two Cloud Routers (ASNs 64525 and 64526) and two HA VPN gateways. These names are part of the published exercise; region and project come from the temporary lab environment. Create the routers and gateways first:

```bash
gcloud compute routers create routing-vpc-cr --network=routing-vpc --asn=64525 --region="$REGION"
gcloud compute routers create on-prem-router --network=on-prem-net-vpc --asn=64526 --region="$REGION"
gcloud compute vpn-gateways create routing-vpc-vpn-gateway --network=routing-vpc --region="$REGION"
gcloud compute vpn-gateways create on-prem-vpn-gateway --network=on-prem-net-vpc --region="$REGION"
```

Generate a fresh VPN shared secret and use it for both ends. Never print or commit this value. If rerunning, skip existing matching tunnels; if only one tunnel exists, stop and repair the pair instead of generating a different secret.

```bash
VPN_SECRET="$(openssl rand -base64 24)"
gcloud compute vpn-tunnels create routing-vpc-tunnel --vpn-gateway=routing-vpc-vpn-gateway --peer-gcp-gateway=on-prem-vpn-gateway --router=routing-vpc-cr --region="$REGION" --interface=0 --shared-secret="$VPN_SECRET"
gcloud compute vpn-tunnels create on-prem-tunnel --vpn-gateway=on-prem-vpn-gateway --peer-gcp-gateway=routing-vpc-vpn-gateway --router=on-prem-router --region="$REGION" --interface=0 --shared-secret="$VPN_SECRET"
unset VPN_SECRET
```

### Test completed task

Use **Check my progress** for **Configure a Cloud Routers, VPN Gateway and VPN tunnel to set up hybrid connectivity** (30 points). This is a grader action in the lab UI, not a claim of PASS.

Next, add both router interfaces and BGP peers. Each side uses an address from the same /30 link-local network:

```bash
gcloud compute routers add-interface routing-vpc-cr --interface-name=if-hub-to-prem --ip-address=169.254.1.1 --mask-length=30 --vpn-tunnel=routing-vpc-tunnel --region="$REGION"
gcloud compute routers add-bgp-peer routing-vpc-cr --peer-name=bgp-hub-to-prem --peer-ip-address=169.254.1.2 --interface=if-hub-to-prem --peer-asn=64526 --region="$REGION"
gcloud compute routers add-interface on-prem-router --interface-name=if-prem-to-hub --ip-address=169.254.1.2 --mask-length=30 --vpn-tunnel=on-prem-tunnel --region="$REGION"
gcloud compute routers add-bgp-peer on-prem-router --peer-name=bgp-prem-to-hub --peer-ip-address=169.254.1.1 --interface=if-prem-to-hub --peer-asn=64525 --region="$REGION"
```

Advertise the lab's workload prefix (10.0.1.0/24), advertise on-premises subnets, and assign MED 111 to the on-premises peer. Inspect tunnel and router status; allow time for BGP convergence.

```bash
gcloud compute routers update routing-vpc-cr --advertisement-mode=custom --set-advertisement-groups=all_subnets --set-advertisement-ranges=10.0.1.0/24 --region="$REGION"
gcloud compute routers update on-prem-router --advertisement-mode=custom --set-advertisement-groups=all_subnets --region="$REGION"
gcloud compute routers update-bgp-peer on-prem-router --peer-name=bgp-prem-to-hub --advertised-route-priority=111 --region="$REGION"
gcloud compute vpn-tunnels describe routing-vpc-tunnel --region="$REGION" --format='flattened(status,detailedStatus)'
gcloud compute routers get-status routing-vpc-cr --region="$REGION"
```

### Test completed task

Use **Check my progress** for **Update the routers to set up hybrid connectivity** (35 points). If the tunnel is not established yet, investigate the HA VPN pair and wait for the BGP sessions to converge.

## Task 2. Network Connectivity Center Hub

Create a hub called mesh-hub. Inspect its default route table before attaching spokes; it is expected to contain no learned spoke routes at this stage.

```bash
gcloud network-connectivity hubs create mesh-hub
gcloud network-connectivity hubs describe mesh-hub
gcloud network-connectivity hubs route-tables list --hub=mesh-hub
gcloud network-connectivity hubs route-tables describe default --hub=mesh-hub
gcloud network-connectivity hubs route-tables routes list --hub=mesh-hub --route_table=default
```

### Test completed task

Use **Check my progress** for **Network Connectivity Center Hub** (15 points).

## Task 3. NCC with Hybrid and VPC Spokes

Attach workload-vpc as a global linked-VPC spoke. Attach only the routing-side VPN tunnel as a regional hybrid spoke. These two spoke types provide the route exchange between the simulated on-premises environment and the workload network.

```bash
gcloud network-connectivity spokes linked-vpc-network create workload-vpc-spoke --hub=mesh-hub --vpc-network=workload-vpc --global
gcloud network-connectivity spokes linked-vpn-tunnels create hybrid-spoke --hub=mesh-hub --vpn-tunnels=routing-vpc-tunnel --region="$REGION"
```

Inspect the spokes and the effective route table for the on-premises subnet 10.0.3.0/24. The route should reflect the BGP MED value of 111 from Task 1.

```bash
gcloud network-connectivity hubs list-spokes mesh-hub
gcloud network-connectivity hubs route-tables routes list --hub=mesh-hub --route_table=default
gcloud network-connectivity hubs route-tables routes list --hub=mesh-hub --route_table=default --effective-location="$REGION" --filter=10.0.3.0/24
```

### Test completed task

Use **Check my progress** for **NCC with Hybrid and VPC Spokes** (20 points). If a route is absent, allow propagation and check the BGP peers before retrying.

## Task 4. Verify the data path

Find the on-premises VM in the lab zone and SSH into it. From inside that VM, request the workload HTTP service at the lab's specified private address. This demonstrates that the route is usable, not merely configured.

```bash
gcloud compute instances list --filter='name=vm3-onprem'
gcloud compute ssh vm3-onprem --zone="$ZONE"
```

Run inside the VM, then return to Cloud Shell:

```bash
curl --verbose --max-time 15 http://10.0.1.2/
exit
```

A successful HTTP response indicates the data path works. If the connection fails, check the tunnel state, BGP route advertisement, NCC spokes and firewall. The published checkpoint list does not include a separate Task 4 grader.

## Task 5. Delete resources

**Only after all four checkpoints have been reviewed**, remove the resources created in this workflow. Do not delete the pre-provisioned VPCs or VMs. Deleting spokes before checking the grader may invalidate progress.

```bash
gcloud network-connectivity spokes delete workload-vpc-spoke --global --quiet
gcloud network-connectivity spokes delete hybrid-spoke --region="$REGION" --quiet
gcloud network-connectivity hubs delete mesh-hub --quiet
gcloud compute vpn-tunnels delete on-prem-tunnel --region="$REGION" --quiet
gcloud compute vpn-tunnels delete routing-vpc-tunnel --region="$REGION" --quiet
gcloud compute routers delete routing-vpc-cr --region="$REGION" --quiet
gcloud compute routers delete on-prem-router --region="$REGION" --quiet
```

The automated script implements this cleanup as an explicit opt-in using CLEANUP=1 and CONFIRM_CLEANUP=YES. The default run preserves resources for grading.

---

## Solution of Lab

### Quick

The canonical commands below use the main branch. **They cannot download the new script until its Draft PR has been merged.**

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1318/lab.sh
source lab.sh
```

The script detects the project, zone and region, configures the lab's HA VPN/BGP/NCC resources, checks the HTTP data path, and leaves cleanup disabled by default. It reuses safely existing resources, refuses a mismatched one-sided tunnel pair, supports terminal ANSI color and FORCE_COLOR=1 through tee, and gives NO_COLOR precedence.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Follow the complete Task 1–5 manual workflow above. The official Google Skills page is the source of the original diagrams; no unlicensed image is embedded here.

### Sources and verification

- [Google Skills GSP1318 — Establish Hybrid Network Connectivity with NCC](https://www.skills.google/focuses/124809?parent=catalog)
- [Network Connectivity Center documentation](https://cloud.google.com/network-connectivity/docs/network-connectivity-center/concepts/overview)
- [HA VPN documentation](https://cloud.google.com/network-connectivity/docs/vpn/concepts/topologies)
- This guide paraphrases the lab and does not reproduce the original copyrighted instructional prose. Script: Copyright (c) 2026 ePlus.DEV | Unlicense.
- **static validated only; runtime/grader unverified**. CI/static checks do not prove the Google Skills grader passes.
