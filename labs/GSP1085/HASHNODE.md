# GSP1085 — Migrating to AlloyDB from PostgreSQL Using PostgreSQL Tools

**Official lab:** https://www.skills.google/focuses/100855  
**Arcade:** https://www.skills.google/games/7501/labs/45913  
**Manual last updated:** August 13, 2026 (official public catalog).  
**Runtime status:** script not yet verified in an authorized live lab; check both checkpoints yourself.

## Overview

This lab demonstrates a native PostgreSQL migration from a PostgreSQL 14 database running on Compute Engine to an existing AlloyDB for PostgreSQL instance. The export is a custom-format `.DMP` archive produced by `pg_dump -Fc`, transferred through Cloud Storage, and imported with `pg_restore`. Unlike Database Migration Service (DMS) labs, this exercise uses native PostgreSQL tools.

### Objectives and checkpoints

| Task | Goal | Score |
|---|---|---:|
| Task 1 — Verify Data in Source Instance for Migration | Confirm six HR tables on `pg14-source` | — |
| Task 2 — Create a database DMP file using pg_dump | Upload `pg14_source.DMP` to the project-named bucket | 50 |
| Task 3 — Import DMP file using pg_restore | Restore and verify the six tables in AlloyDB | 50 |

## Setup and requirements

Start the lab with its temporary Google Skills credentials. Open the assigned Google Cloud console and activate Cloud Shell. Do not use your personal GCP project. The lab provisions a `pg14-source` VM, an `alloydb-client` VM, an AlloyDB cluster `lab-cluster` with instance `lab-instance`, and a Cloud Storage bucket named after your project ID.

Verify the project:

```bash
gcloud config get-value project
gcloud compute instances list
gcloud alloydb clusters list
```

## Task 1. Verify Data in Source Instance for Migration

In **Compute Engine → VM instances**, SSH to `pg14-source`. Start PostgreSQL:

```bash
sudo -u postgres psql
```

At the `psql` prompt, list the six HR tables and inspect their data:

```sql
\dt
SELECT COUNT(*) AS countries_row_count FROM countries;
SELECT COUNT(*) AS departments_row_count FROM departments;
SELECT COUNT(*) AS employees_row_count FROM employees;
SELECT COUNT(*) AS jobs_row_count FROM jobs;
SELECT COUNT(*) AS locations_row_count FROM locations;
SELECT COUNT(*) AS regions_row_count FROM regions;
```

Expected counts from the official manual:

| Table | Rows |
|---|---:|
| countries | 25 |
| departments | 27 |
| employees | 107 |
| jobs | 19 |
| locations | 23 |
| regions | 4 |

Exit with `\q`.

## Task 2. Create a database DMP file using pg_dump

On the **pg14-source VM** shell, create the archive and confirm it is nonempty:

```bash
sudo -u postgres pg_dump -Fc postgres > pg14_source.DMP
ls -lh pg14_source.DMP
```

The `-Fc` option generates a custom-format PostgreSQL archive suitable for `pg_restore`. Upload the archive to the **existing** lab bucket:

```bash
PROJECT_ID="$(gcloud config get-value project)"
gcloud storage cp pg14_source.DMP "gs://${PROJECT_ID}/pg14_source.DMP"
gcloud storage ls "gs://${PROJECT_ID}/pg14_source.DMP"
```

Back in Google Skills, click **Check my progress** for **Upload database DMP file to Cloud Storage** (50 points).

## Task 3. Import DMP file using pg_restore

In **AlloyDB for PostgreSQL → Clusters**, open `lab-cluster`. Wait for `lab-instance` to show **Ready** and copy its **Private IP address**.

In **Compute Engine → VM instances**, SSH to `alloydb-client`. Replace `ALLOYDB_ADDRESS` with that private IP:

```bash
export ALLOYDB="ALLOYDB_ADDRESS"
echo "$ALLOYDB" > alloydbip.txt
```

Check that the target database initially has no HR tables:

```bash
psql -h "$ALLOYDB" -U postgres -d postgres
```

Use the PostgreSQL password shown in the assigned lab instructions. Inside `psql`, run `\dt` (an empty database should show no relations), then `\q`.

Download the archive from Cloud Storage **onto the alloydb-client VM**:

```bash
PROJECT_ID="$(gcloud config get-value project)"
gcloud storage cp "gs://${PROJECT_ID}/pg14_source.DMP" pg14_source.DMP
ls -lh pg14_source.DMP
```

Create a table-of-contents (TOC) file with extension statements commented out:

```bash
pg_restore -l pg14_source.DMP | sed -E 's/(.* EXTENSION )/; \1/g' > pg14_source_toc.toc
```

Restore the archive into AlloyDB:

```bash
pg_restore -h "$ALLOYDB" -U postgres \
  -d postgres \
  -L pg14_source_toc.toc \
  pg14_source.DMP
```

You may be prompted for the PostgreSQL password. After completion, inspect the destination:

```bash
psql -h "$ALLOYDB" -U postgres -d postgres
```

At the `psql` prompt:

```sql
\dt
SELECT COUNT(*) AS countries_row_count FROM countries;
SELECT COUNT(*) AS departments_row_count FROM departments;
SELECT COUNT(*) AS employees_row_count FROM employees;
SELECT COUNT(*) AS jobs_row_count FROM jobs;
SELECT COUNT(*) AS locations_row_count FROM locations;
SELECT COUNT(*) AS regions_row_count FROM regions;
```

The destination should have the same six tables and row counts as Task 1. Exit with `\q`. In Google Skills, click **Check my progress** for **Verify import of database DMP file** (50 points).

## Solution of Lab

### Quick

> This published Quick link intentionally points to **main**. It will work only **after the PR is merged**.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1085/lab.sh
source lab.sh
```

### Manual

Use the Task 1–3 commands above if you want to inspect every step, or when the automated script encounters a permission, SSH, or PostgreSQL connectivity issue. For a pre-merge test, use the **latest-commit SHA command in the PR description**, not the Quick link.

### Other Solution

No separate third-party solution has been independently validated. Official reference: https://www.skills.google/focuses/100855.

## Troubleshooting

- **Wrong project or missing bucket:** verify `gcloud config get-value project` and the lab-provisioned bucket; do not create a new project/bucket as a workaround.
- **AlloyDB connection refused:** verify the cluster/instance is Ready and use its **private IP** from the lab; run `psql` on the provisioned `alloydb-client` VM.
- **Authentication failed:** use the PostgreSQL credentials supplied in the current lab, not personal credentials.
- **Restore reports existing relations:** the destination may already be partially populated. Inspect before retrying; do not blindly drop tables or overwrite existing data.
- **Checkpoint does not pass:** verify the exact bucket object name `pg14_source.DMP`, the six destination tables, and row counts, then retry **Check my progress**.

## Notes

This is an original step-by-step explanation based on the publicly available Google Skills lab manual; it is not a verbatim reproduction. No external screenshots were included because suitable image assets and reuse rights were not verified. The script has not been executed against a live lab or independently confirmed to earn 100 points.

Copyright (c) 2026 ePlus.DEV | Unlicense (original guide and script).
