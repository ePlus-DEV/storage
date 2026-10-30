# Migrating to AlloyDB from PostgreSQL Using PostgreSQL Tools — GSP1085

> Official Google Skills lab: https://www.skills.google/focuses/100855. Original walkthrough for the three-task lab; verify live instructions in your assigned session. Runtime and grader results have not been verified.

## Overview
Migrate the six HR tables from PostgreSQL on a Compute Engine VM to an existing AlloyDB for PostgreSQL cluster using PostgreSQL native tools: `pg_dump` in custom format and `pg_restore`. The lab provides source and client VMs, an AlloyDB cluster, and a Cloud Storage bucket.

## Setup
Start the authorized lab, open its Google Cloud console using the temporary student account, and activate Cloud Shell. Confirm the active project with `gcloud config get-value project`. Never use your personal GCP project or create replacement infrastructure.

## Task 1 — Verify the source data
Open the provisioned `pg14-source` VM through Compute Engine SSH and run `sudo -u postgres psql`. Inspect the six HR tables (`countries`, `departments`, `employees`, `jobs`, `locations`, `regions`) and their row counts. The script checks these tables remotely.

## Task 2 — Export the PostgreSQL database
On the source VM, create a custom-format PostgreSQL dump with `pg_dump -Fc`. Transfer the `pg14_source.DMP` archive to the lab's project-named Cloud Storage bucket, then use **Check my progress** for the export checkpoint. The script preserves an existing bucket object rather than overwriting it on a rerun.

## Task 3 — Import into AlloyDB
Wait for the lab-provisioned `lab-cluster` / `lab-instance` to become ready. On `alloydb-client`, retrieve the dump, prepare a `pg_restore` table of contents that skips extension entries, and restore into the target PostgreSQL database. Verify the six HR tables and use **Check my progress** for the import checkpoint. The script prompts for the lab-provided PostgreSQL password when necessary and avoids overwriting partially populated target tables.

## Solution of Lab

### Quick

The published Quick link always targets `main`; it will work **only after this PR is merged**.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1085/lab.sh
source lab.sh
```

### Manual

Follow the official task instructions: [Google Skills — GSP1085](https://www.skills.google/focuses/100855). No verified public step-by-step video is available for inclusion here.

## Verification and limitations
The PR's test command uses the latest branch commit SHA rather than `main`. A live Cloud Shell run and Google Skills grader PASS have not been independently verified. The official lab may vary by session; use the assigned lab's resources and parameters. No screenshots are included because a suitable reusable public image was not verified.

Copyright (c) 2026 ePlus.DEV | Unlicense (original content and script only).
