# Migrate to AlloyDB from PostgreSQL Using Database Migration Service - GSP1084

## Overview

This lab migrates a PostgreSQL database running on a Compute Engine VM into a pre-provisioned AlloyDB for PostgreSQL instance. Database Migration Service (DMS) performs an initial copy and then uses change data capture (CDC) to replicate subsequent changes. VPC peering connects the source and destination. This guide is independently written, following the four-task version of the [official lab](https://www.skills.google/focuses/100854); other public editions split the connection-profile step into its own task.

### What you'll do

- Inspect the source PostgreSQL database and verify six HR tables.
- Configure the PostgreSQL source connection profile and launch a continuous DMS migration to an existing AlloyDB cluster.
- Compare the source and destination data.
- Insert a new region at the source and verify that CDC replicates it.

## Setup and requirements

### Before you click the Start Lab button

Use an incognito/private browser session and the **temporary student account provided by the lab**. Do not use personal billing credentials or publish any lab passwords. The lab timer cannot be paused. Start the lab, open the Google Cloud console, and ensure the temporary project is active.

### Activate Cloud Shell

Open Cloud Shell from the Google Cloud console and confirm the selected project:

```bash
gcloud auth list
export PROJECT_ID="$(gcloud config get-value project)"
printf 'Project: %s\n' "$PROJECT_ID"
gcloud compute instances list --project="$PROJECT_ID"
gcloud alloydb clusters list --project="$PROJECT_ID"
```

The commands below refer to the resources provisioned for this lab: source VM `pg14-source`, client VM `alloydb-client`, target cluster `alloydb-target-cluster`, and target instance `alloydb-target-instance`. Read the live instructions if your lab has different resource names.

## Task 1. Verify the data in the source instance for migration

1. Navigate to **Compute Engine → VM instances** and open an SSH session to `pg14-source`.
2. Start the PostgreSQL shell and inspect the HR schema.

```bash
sudo -u postgres psql
```

```sql
\dt
SELECT 'countries' AS table_name, COUNT(*) FROM countries
UNION ALL SELECT 'departments', COUNT(*) FROM departments
UNION ALL SELECT 'employees', COUNT(*) FROM employees
UNION ALL SELECT 'jobs', COUNT(*) FROM jobs
UNION ALL SELECT 'locations', COUNT(*) FROM locations
UNION ALL SELECT 'regions', COUNT(*) FROM regions
ORDER BY table_name;
```

For the documented lab dataset, the expected initial counts are:

| Table | Expected rows |
| --- | ---: |
| countries | 25 |
| departments | 27 |
| employees | 107 |
| jobs | 19 |
| locations | 23 |
| regions | 4 |

These are **documented reference values**, not output observed during this session.

```plaintext
\q
```

Exit the VM terminal when finished.

## Task 2. Create and start a continuous migration job

### Identify the source endpoint

In **Compute Engine → VM instances**, note the **internal IP** of `pg14-source`. Do not use the external IP.

### Create the source connection profile

1. Navigate to **Database Migration → Connection profiles** (or select **Create a connection profile** in the migration wizard).
2. Choose a **PostgreSQL source** profile and name it `pg14-source`.
3. Enter the source VM's **internal IP**, port `5432`, and the **temporary database credentials supplied by the current lab instructions**.
4. Save the profile.

### Test completed task

If your lab edition has a separate connection-profile checkpoint, use **Check my progress** after creating the profile. Do not assume that merely saving the form passes the checkpoint.

### Create the migration job

1. Go to **Database Migration → Migration jobs → Create migration job**.
2. Name the job `postgres-to-alloydb`, select **PostgreSQL** as source and **AlloyDB for PostgreSQL** as destination, choose **Continuous**, and select the region of the existing target cluster.
3. Select the previously created `pg14-source` source profile.
4. For the destination, select **Existing cluster** and choose `alloydb-target-cluster`. Confirm the cluster selection when prompted.
5. Choose **VPC peering** as the connectivity method.
6. Select **All databases** for migration.
7. Run **Test job** and address any connectivity/precondition errors. When the test succeeds, select **Create & start job**; merely creating the job without starting it is insufficient.

**Important:** The existing AlloyDB target may need a destination demotion operation as part of DMS preparation. Do not manually delete or promote the target while continuous migration is needed. Follow the current wizard and lab's instructions.

### Check migration status

Use the job details page to monitor its status. Wait for **Running**, with phase **CDC**, after the initial load. The initial copy may take several minutes.

```bash
gcloud database-migration migration-jobs describe postgres-to-alloydb \
  --project="$PROJECT_ID" \
  --region="YOUR_DISCOVERED_REGION" \
  --format='yaml(state,phase)'
```

Replace the placeholder with the region you observed in the console; it is **not** a prescribed hardcoded region.

### Test completed task

Use the official migration-job progress checker after the job reaches the required state.

## Task 3. Confirm data load in the AlloyDB for PostgreSQL instance

1. Open **AlloyDB for PostgreSQL → Clusters**, select `alloydb-target-cluster`, and inspect its **Connectivity** information.
2. Copy the target **private IP** without the `:5432` port suffix.
3. Open an SSH terminal to `alloydb-client` in **Compute Engine → VM instances**.
4. Connect using `psql`, supplying the temporary database password securely at the password prompt:

```bash
psql -h "YOUR_ALLOYDB_PRIVATE_IP" -p 5432 -U postgres -d postgres -W
```

5. Run the same row-count query used in Task 1:

```sql
SELECT 'countries' AS table_name, COUNT(*) FROM countries
UNION ALL SELECT 'departments', COUNT(*) FROM departments
UNION ALL SELECT 'employees', COUNT(*) FROM employees
UNION ALL SELECT 'jobs', COUNT(*) FROM jobs
UNION ALL SELECT 'locations', COUNT(*) FROM locations
UNION ALL SELECT 'regions', COUNT(*) FROM regions
ORDER BY table_name;
```

The six counts should match the source's initial dataset. Keep this client session available for the CDC check.

### Test completed task

Use the lab's **Check my progress** control if provided for the initial data-load checkpoint.

## Task 4. Propagate a live update to the AlloyDB instance

### Insert a row at the source

Reconnect to `pg14-source` via SSH and open `psql`:

```bash
sudo -u postgres psql
```

Insert the region if it is not already present:

```sql
INSERT INTO regions (region_id, region_name)
SELECT 5, 'Oceania'
WHERE NOT EXISTS (SELECT 1 FROM regions WHERE region_id = 5);

SELECT region_id, region_name
FROM regions
ORDER BY region_id;
```

The source should now include `5 | Oceania`, with five region records in total.

### Verify the change at the destination

Return to the `alloydb-client` PostgreSQL session and query the destination:

```sql
SELECT region_id, region_name
FROM regions
ORDER BY region_id;
```

If replication has not caught up, wait briefly and retry. The target should eventually include the new `Oceania` row. **Do not promote the destination** while the exercise expects ongoing CDC.

### Test completed task

Use **Check my progress** for the live-update checkpoint. A successful query is not proof that the external grader has passed.

---

## Solution of Lab

### Quick

The script is available on **PR #11's feature branch**, not on `main` until merged:

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/feat/gsp1084-postgres-to-alloydb-dms/labs/GSP1084/lab.sh
source lab.sh
```

The script attempts to discover project, region, VM zones, source and destination IPs, create/verify the DMS configuration, wait for CDC, and verify replication. It must only be run in a lab environment where you have permission.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

## Sources and verification

- [Google Skills official GSP1084 lab](https://www.skills.google/focuses/100854)
- [Google Cloud — Migrate to AlloyDB for PostgreSQL using Database Migration Service](https://docs.cloud.google.com/alloydb/docs/migrate-with-dms)
- [PR #11 — ePlus.DEV GSP1084 script](https://github.com/ePlus-DEV/storage/pull/11)

**Status:** This is a task-by-task original-language Markdown adaptation of the publicly accessible instructions, **not a verbatim reproduction** of the copyrighted lab page. The supplied screenshot is too low-resolution to reliably extract its embedded figures; no images are represented as extracted or verified. **static validated only; runtime/grader unverified** for the PR script according to its existing PR description; this documentation edit does not add new runtime evidence. Not published on Hashnode.

Copyright (c) 2026 ePlus.DEV | Unlicense
