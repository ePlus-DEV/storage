# Migrate to Cloud SQL for PostgreSQL Using Database Migration Service - GSP918

## Overview

Migrate PostgreSQL from a Compute Engine VM to an existing Cloud SQL for PostgreSQL instance using a continuous Database Migration Service (DMS) job. This guide covers source logical replication, a DMS connection profile, VPC peering, CDC verification, and final promotion.

Official lab: https://www.skills.google/focuses/22792

### What you'll do

- Install and configure pglogical on the source PostgreSQL VM.
- Create a replication user and a DMS source connection profile.
- Connect the existing Cloud SQL destination and run a continuous VPC-peered migration.
- Verify the original data and one newly inserted CDC record.
- Promote Cloud SQL to a standalone read/write instance.

## Setup and requirements

### Before you click the Start Lab button

Open the official lab and review its timer and temporary credentials. Sign in with the lab-issued account in a private browser session. Do not use a personal billing project. Never commit the temporary passwords or project identifiers to GitHub.

The official exercise uses a source VM named `postgresql-vm`, a destination Cloud SQL instance named `postgresql-cloudsql`, and databases `postgres`, `orders`, and `gmemegen_db`. Verify that these resources exist because lab provisioning can change.

### Activate Cloud Shell

Activate Cloud Shell from the Google Cloud console, then identify the provisioned project, VM zone, region and source internal IP:

```bash
export PROJECT_ID="$(gcloud config get-value project)"
export VM_ZONE="$(gcloud compute instances list --filter='name=postgresql-vm' --format='value(zone)' | head -n1 | awk -F/ '{print $NF}')"
export REGION="${VM_ZONE%-?}"
export SOURCE_IP="$(gcloud compute instances describe postgresql-vm --zone="$VM_ZONE" --format='value(networkInterfaces[0].networkIP)')"
printf 'Project: %s | Region: %s | Source IP: %s\n' "$PROJECT_ID" "$REGION" "$SOURCE_IP"
gcloud sql instances describe postgresql-cloudsql --format='value(region,state)'
```

Verify that the Database Migration API and Service Networking API are enabled. If the lab account lacks API-enable permissions, first check whether the lab already enabled them.

## Task 1. Prepare the source database for migration

### Configure PostgreSQL and pglogical

Connect to the source VM:

```bash
gcloud compute ssh postgresql-vm --zone="$VM_ZONE"
```

On the VM, detect the PostgreSQL version and install the matching pglogical package:

```bash
PG_VERSION_NUM="$(sudo -u postgres psql -Atqc 'SHOW server_version_num')"
PG_MAJOR="$((PG_VERSION_NUM / 10000))"
sudo apt-get update
sudo apt-get install -y "postgresql-${PG_MAJOR}-pglogical"
```

Set the PostgreSQL parameters required for logical replication:

```bash
sudo -u postgres psql -c "SHOW shared_preload_libraries;"
sudo -u postgres psql -c "ALTER SYSTEM SET wal_level = 'logical';"
sudo -u postgres psql -c "ALTER SYSTEM SET max_worker_processes = '10';"
sudo -u postgres psql -c "ALTER SYSTEM SET max_replication_slots = '10';"
sudo -u postgres psql -c "ALTER SYSTEM SET max_wal_senders = '10';"
sudo -u postgres psql -c "ALTER SYSTEM SET listen_addresses = '*';"
```

Add `pglogical` to `shared_preload_libraries` while preserving any existing libraries. If there are no other entries, run:

```bash
sudo -u postgres psql -c "ALTER SYSTEM SET shared_preload_libraries = 'pglogical';"
sudo systemctl restart "postgresql@${PG_MAJOR}-main"
```

Restrict remote PostgreSQL access using the DMS peering CIDR after it is allocated in Task 2. Do not leave an unrestricted `0.0.0.0/0` rule in a production system.

### Create the replication user and grant privileges

Open PostgreSQL as the local administrator:

```bash
sudo -u postgres psql -d postgres
```

In psql, create the dedicated user and grant replication permission:

```sql
CREATE ROLE migration_admin WITH LOGIN REPLICATION;
ALTER DATABASE orders OWNER TO migration_admin;
```

Use the psql meta-command `\password migration_admin` to set a password interactively, without placing it in a script or shell history. Retain that password for the DMS source profile.

In each of the `postgres`, `orders`, and `gmemegen_db` databases, run:

```sql
CREATE EXTENSION IF NOT EXISTS pglogical;
GRANT ALL ON SCHEMA pglogical TO migration_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA pglogical TO migration_admin;
GRANT ALL ON SCHEMA public TO migration_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO migration_admin;
```

Use psql `\c orders` to switch to the orders database. Transfer ownership of its five application tables:

```sql
ALTER TABLE public.distribution_centers OWNER TO migration_admin;
ALTER TABLE public.inventory_items OWNER TO migration_admin;
ALTER TABLE public.order_items OWNER TO migration_admin;
ALTER TABLE public.products OWNER TO migration_admin;
ALTER TABLE public.users OWNER TO migration_admin;
```

Verify `SHOW wal_level;` returns `logical` and that `pglogical` exists in all three databases. Exit psql and the SSH session.

### Test completed task

Checkpoint 1: **Prepare the source database for migration** (20 points). Click **Check my progress** in the official lab.

## Task 2. Create and start a continuous migration job

### Define the source connection profile

Back in Cloud Shell, create a profile with the source VM's internal IP. The CLI prompts for the replication user's password:

```bash
gcloud database-migration connection-profiles create postgresql postgres-vm \
  --region="$REGION" --role=SOURCE \
  --host="$SOURCE_IP" --port=5432 --username=migration_admin \
  --prompt-for-password --no-async
```

For a rerun, inspect an existing profile rather than creating a duplicate:

```bash
gcloud database-migration connection-profiles describe postgres-vm --region="$REGION"
```

### Define the destination

Use the lab-provided **existing** Cloud SQL instance, not an arbitrary new instance. Create a destination connection profile:

```bash
gcloud database-migration connection-profiles create postgresql gsp918-cloudsql-destination \
  --region="$REGION" --role=DESTINATION \
  --cloudsql-instance=postgresql-cloudsql --username=postgres \
  --prompt-for-password --no-async
```

Enter the Cloud SQL postgres password from the authorized lab when prompted. The standard existing-instance migration flow demotes this destination; do not run these steps against production data.

### Configure VPC peering and the continuous job

Create the job for all databases with the default VPC:

```bash
gcloud database-migration migration-jobs create vm-to-cloudsql \
  --region="$REGION" --type=CONTINUOUS \
  --source=postgres-vm --destination=gsp918-cloudsql-destination \
  --all-databases \
  --peer-vpc="projects/$PROJECT_ID/global/networks/default" --no-async
```

Find the actual allocated DMS peering CIDR in **VPC Network → VPC network peering → Effective routes**. On the source VM, add `host all all CIDR md5` and `host replication all CIDR md5` entries to the PostgreSQL `pg_hba.conf` file, replacing `CIDR` with the actual allocated range. Reload PostgreSQL. Ensure the VM firewall permits TCP/5432 from that CIDR, scoped to the source VM. Never reuse an example CIDR from a different lab.

Demote the existing destination, verify connectivity and start the migration:

```bash
gcloud database-migration migration-jobs demote-destination vm-to-cloudsql --region="$REGION"
gcloud database-migration migration-jobs verify vm-to-cloudsql --region="$REGION"
gcloud database-migration migration-jobs start vm-to-cloudsql --region="$REGION"
gcloud database-migration migration-jobs describe vm-to-cloudsql \
  --region="$REGION" --format='yaml(state,phase)'
```

Wait for the job phase to become `CDC`. Job creation alone does not confirm successful replication.

### Test completed task

Checkpoint 2: **Create a Database Migration Service connection profile** (20 points).

Checkpoint 3: **Create and start a continuous migration job** (20 points).

## Task 3. Confirm the data in Cloud SQL for PostgreSQL

### Verify the initial database copy

Check that `postgres`, `orders`, and `gmemegen_db` exist on Cloud SQL:

```bash
gcloud sql databases list --instance=postgresql-cloudsql
gcloud sql connect postgresql-cloudsql --user=postgres --database=orders --quiet
```

After entering the Cloud SQL password, inspect the destination's distribution centers:

```sql
SELECT id, name FROM public.distribution_centers ORDER BY id;
```

### Verify continuous data capture

On the **source** VM, connect to `orders` as the local PostgreSQL administrator and insert the Miami test row only if absent:

```sql
INSERT INTO public.distribution_centers(longitude, latitude, name, id)
SELECT -80.1918, 25.7617, 'Miami FL', 11
WHERE NOT EXISTS (SELECT 1 FROM public.distribution_centers WHERE id = 11);
```

After the DMS job is in CDC, query the **destination** Cloud SQL `orders` database:

```sql
SELECT id, name FROM public.distribution_centers WHERE id = 11;
```

The expected result is ID `11` with name `Miami FL`. If the row has not appeared, inspect replication lag and DMS job errors before promoting.

### Test completed task

Checkpoint 4: **Confirm the data in Cloud SQL for PostgreSQL** (20 points).

## Task 4. Promote Cloud SQL to be a stand-alone instance for reading and writing data

Only promote after the CDC row is confirmed and source writes are stopped:

```bash
gcloud database-migration migration-jobs promote vm-to-cloudsql --region="$REGION"
gcloud database-migration migration-jobs describe vm-to-cloudsql \
  --region="$REGION" --format='yaml(state,phase)'
```

Wait until the migration job is `COMPLETED`. Confirm that `postgresql-cloudsql` is now a standalone read/write instance.

### Test completed task

Checkpoint 5: **Promote Cloud SQL to be a stand-alone instance for reading and writing data** (20 points).

---

## Solution of Lab

### Quick

This Quick is intentionally pinned to `main` and becomes available **only after the PR is merged**.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP918/lab.sh
source lab.sh
```

The script detects the authorized project, VM zone and region, prompts for passwords, prepares PostgreSQL, creates DMS profiles and the job, restricts network access, verifies CDC, and promotes Cloud SQL. Review all prompts. The script does not hardcode lab credentials.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này. Use the manual Task 1–4 instructions above.

## Sources and verification status

- [Google Skills GSP918 official lab](https://www.skills.google/focuses/22792) — four tasks and five checkpoints, manual updated September 28, 2026.
- [DMS migration to an existing Cloud SQL destination](https://docs.cloud.google.com/database-migration/docs/postgres/create-migration-job-existing-instance)
- [gcloud migration job creation](https://docs.cloud.google.com/sdk/gcloud/reference/database-migration/migration-jobs/create)
- [gcloud PostgreSQL connection profiles](https://docs.cloud.google.com/sdk/gcloud/reference/database-migration/connection-profiles/create/postgresql)

**Verification:** Static validated only; runtime/grader unverified. This is a Hashnode-ready draft, not a published post. The official screenshots are not republished because image reuse permissions have not been confirmed.
