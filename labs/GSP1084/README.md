# GSP1084 — Migrate to AlloyDB from PostgreSQL Using Database Migration Service

Google Cloud Skills Boost lab automation by **ePlus.DEV**.

## Lab overview

The script completes the four exercises with an existing, lab-provisioned AlloyDB cluster and two VMs. It **does not create/delete an AlloyDB cluster** or promote the target, as continuous replication must remain active for this lab.

| Task | Automation |
| --- | --- |
| 1. Verify PostgreSQL source | SSH to `pg14-source`, query the six HR tables |
| 2. Create and start a continuous migration job | Source and destination connection profiles, VPC peering, destination demotion, job validation and start |
| 3. Confirm AlloyDB data | SSH to `alloydb-client`, verify six table counts |
| 4. Test continuous replication | Insert `(5, 'Oceania')` at source and poll AlloyDB until replicated |

### Resources defined by this lab

- Source VM / profile: `pg14-source`
- Client VM: `alloydb-client`
- Existing AlloyDB cluster: `alloydb-target-cluster`
- Existing AlloyDB instance: `alloydb-target-instance`
- Migration job: `postgres-to-alloydb`
- Temporary lab PostgreSQL user/password: `postgres` / `Change3Me`

The **project, region, VM zones, source private IP, VPC and destination private IP are discovered automatically** rather than hardcoded. The script requires authenticated `gcloud`, `jq`, and SSH access from Cloud Shell to the two VMs.

## Run from Cloud Shell

Clone the repo and launch the lab script:

```bash
git clone --depth 1 https://github.com/ePlus-DEV/storage.git
cd storage
bash labs/GSP1084/lab.sh
```

For PR testing **before merge**, check out the PR's branch rather than `main`:

```bash
git clone --branch feat/gsp1084-postgres-to-alloydb-dms --single-branch --depth 1 https://github.com/ePlus-DEV/storage.git
cd storage
bash labs/GSP1084/lab.sh
```

## Expected verification

| Table | Rows before CDC update |
| --- | ---: |
| `countries` | 25 |
| `departments` | 27 |
| `employees` | 107 |
| `jobs` | 19 |
| `locations` | 23 |
| `regions` | 4 |

- The migration job should reach **RUNNING / CDC**.
- The source insert should replicate `5 | Oceania` to AlloyDB, making `regions` contain five rows.
- The script checks both initial counts and live replication. In the Skills Boost interface, click **Check my progress** for the applicable tasks.

## Notes

- Intended **only for the temporary GSP1084 lab project**; the supplied temporary database password is lab-specific.
- Rerunning is supported: the script skips already-created profiles/jobs, reuses a found destination-demotion operation, and inserts Oceania only when absent.
- Avoid running against production databases; destination demotion changes the existing AlloyDB instance's role.
- A successful static check is **not** proof that the full migration works in a live lab. Validate end-to-end with a fresh GSP1084 environment.

© 2026 ePlus.DEV
