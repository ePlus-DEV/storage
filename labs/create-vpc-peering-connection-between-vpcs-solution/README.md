# Create VPC Peering Connection between VPCs (Solution)

- [Published challenge scenario](https://eplus.dev/create-vpc-peering-connection-between-vpcs-solution-1)
- [Google Cloud official peering commands](https://docs.cloud.google.com/sdk/gcloud/reference/compute/networks/peerings)
- [Google Cloud official peering list flags](https://docs.cloud.google.com/sdk/gcloud/reference/compute/networks/peerings/list)
- License: [Unlicense](../../LICENSE).

The lab requires peering `workspace-vpc` with `private-vpc` in **both directions**. The script checks existing networks and peerings, creates only missing lab-named resources, refuses to overwrite a peering pointing to another network, and waits up to 30 seconds for both connections to become `ACTIVE`. It never opens an interactive SSH session (the prior script blocked at `gcloud compute ssh workspace-vm`).

```bash
PROJECT_ID=your-temporary-lab-project bash lab.sh
```

Only override `WORKSPACE_VPC` and `PRIVATE_VPC` when your lab instructions specify different names. Peering needs non-overlapping subnet ranges; this script does not modify existing subnets or firewall rules.

**Static validated only; runtime/grader unverified.** The Google Skills focus URL and current October game membership are not independently confirmed. Run only in the disposable lab project.
