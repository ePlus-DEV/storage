---
title: "GSP395: Create and Manage AlloyDB Instances — Challenge Lab Solution"
subtitle: "Automate an AlloyDB cluster, HR tables, read pool, and backup with Google Cloud CLI"
tags: googlecloud, alloydb, cloudskillsboost, postgresql, devops
coverImage: ""
---

# GSP395 — Create and Manage AlloyDB Instances: Challenge Lab

> **Lab:** [Google Skills challenge lab](https://www.skills.google/games/7501/labs/45914)  
> **Solution:** [ePlus.DEV / GSP395](https://github.com/ePlus-DEV/storage/tree/main/labs/GSP395)  
> **Status:** Draft solution; Google Skills scoring has **not** been independently verified.

## Overview

In this challenge, you act as a database administrator provisioning an AlloyDB for PostgreSQL environment for an HR Operations team. The grader checks five tasks: a cluster and primary instance, the HR table schemas, seed data, a two-node read pool, and an on-demand backup.

**Important:** Use only the temporary Google Skills student account and project assigned to the lab. The lab timer cannot be paused.

## Required resources

| Resource | Required configuration |
| --- | --- |
| Cluster | `lab-cluster` |
| PostgreSQL password | `Change3Me` (temporary lab password only) |
| Network | `peering-network` |
| Primary instance | `lab-instance`, 2 vCPU |
| Client VM | Preprovisioned `alloydb-client` |
| Read pool | `lab-instance-rp1`, 2 nodes, 2 vCPU per node |
| Backup | `lab-backup` |
| Region | **GCP Region from the lab launch page** |

Do not substitute a different region: the grader expects the one assigned to your lab.

## Quick solution — Cloud Shell

While this solution is still under review, run the **draft PR branch** instead of `main`:

```bash
REPO="ePlus-DEV/storage"
BRANCH="scout/new-gsp395-alloydb-challenge-20261030"

SHA="$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" | awk '{print $1}')"
test -n "$SHA" || { echo "Branch not found"; exit 1; }

curl -fL --retry 3 \
  "https://raw.githubusercontent.com/$REPO/$SHA/labs/GSP395/lab.sh" \
  -o lab-gsp395.sh

bash -n lab-gsp395.sh || exit 1
set -o pipefail
FORCE_COLOR=1 bash lab-gsp395.sh 2>&1 | tee "gsp395-${SHA:0:12}.log"
```

The script detects the active project, reads the configured region (or asks for the region on the launch page), finds the `alloydb-client` VM zone, creates resources if absent, and inserts seed data without duplicating existing primary keys.

> **Checkpoint reminder:** Running a script is not the same as passing the grader. Click **Check my progress** after each relevant task.

## Task 1 — Create the cluster and primary instance

Set the correct project and region from your lab session:

```bash
PROJECT_ID="$(gcloud config get-value project)"
read -r -p "GCP Region from lab launch page: " REGION

gcloud alloydb clusters create lab-cluster \
  --password=Change3Me \
  --network=peering-network \
  --region="$REGION" \
  --project="$PROJECT_ID"

gcloud alloydb instances create lab-instance \
  --instance-type=PRIMARY \
  --cpu-count=2 \
  --cluster=lab-cluster \
  --region="$REGION" \
  --project="$PROJECT_ID"
```

If these resources already exist, inspect them instead of recreating them:

```bash
gcloud alloydb clusters describe lab-cluster \
  --region="$REGION" --project="$PROJECT_ID"

gcloud alloydb instances describe lab-instance \
  --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID"
```

Wait until the primary instance is ready. Obtain its private IP from the instance description, then click **Check my progress** for Task 1.

## Task 2 — Create HR tables

On the preprovisioned `alloydb-client` VM, store the primary instance private IP:

```bash
export ALLOYDB="YOUR_PRIMARY_PRIVATE_IP"
echo "$ALLOYDB" > ~/alloydbip.txt
psql -h "$ALLOYDB" -U postgres -d postgres
```

Enter the lab-provided PostgreSQL password when prompted. In `psql`, execute:

```sql
CREATE TABLE IF NOT EXISTS regions (
  region_id bigint NOT NULL PRIMARY KEY,
  region_name varchar(25)
);

CREATE TABLE IF NOT EXISTS countries (
  country_id char(2) NOT NULL PRIMARY KEY,
  country_name varchar(40),
  region_id bigint
);

CREATE TABLE IF NOT EXISTS departments (
  department_id smallint NOT NULL PRIMARY KEY,
  department_name varchar(30),
  manager_id integer,
  location_id smallint
);
```

The challenge specifies exactly these three tables and their primary keys.

## Task 3 — Load the required datasets

Run the following SQL using `psql` on `alloydb-client`:

```sql
INSERT INTO regions VALUES
  (1, 'Europe'),
  (2, 'Americas'),
  (3, 'Asia'),
  (4, 'Middle East and Africa')
ON CONFLICT (region_id) DO NOTHING;

INSERT INTO countries VALUES
  ('IT', 'Italy', 1),
  ('JP', 'Japan', 3),
  ('US', 'United States of America', 2),
  ('CA', 'Canada', 2),
  ('CN', 'China', 3),
  ('IN', 'India', 3),
  ('AU', 'Australia', 3),
  ('ZW', 'Zimbabwe', 4),
  ('SG', 'Singapore', 3)
ON CONFLICT (country_id) DO NOTHING;

INSERT INTO departments VALUES
  (10, 'Administration', 200, 1700),
  (20, 'Marketing', 201, 1800),
  (30, 'Purchasing', 114, 1700),
  (40, 'Human Resources', 203, 2400),
  (50, 'Shipping', 121, 1500),
  (60, 'IT', 103, 1400)
ON CONFLICT (department_id) DO NOTHING;

SELECT 'regions' AS table_name, count(*) FROM regions
UNION ALL
SELECT 'countries', count(*) FROM countries
UNION ALL
SELECT 'departments', count(*) FROM departments;
```

Expected row counts:

| Table | Rows |
| --- | ---: |
| `regions` | 4 |
| `countries` | 9 |
| `departments` | 6 |

Click **Check my progress** for the table creation and data loading objective.

## Task 4 — Create a read pool

```bash
gcloud alloydb instances create lab-instance-rp1 \
  --instance-type=READ_POOL \
  --cpu-count=2 \
  --read-pool-node-count=2 \
  --cluster=lab-cluster \
  --region="$REGION" \
  --project="$PROJECT_ID"
```

Check the instance state:

```bash
gcloud alloydb instances describe lab-instance-rp1 \
  --cluster=lab-cluster --region="$REGION" --project="$PROJECT_ID"
```

Wait until it is ready, then click **Check my progress**.

## Task 5 — Create an on-demand backup

```bash
gcloud alloydb backups create lab-backup \
  --cluster=lab-cluster \
  --region="$REGION" \
  --project="$PROJECT_ID"
```

Verify the backup:

```bash
gcloud alloydb backups describe lab-backup \
  --region="$REGION" --project="$PROJECT_ID" \
  --format="yaml(name,state)"
```

Wait for the backup to complete, then click **Check my progress**.

## Troubleshooting

### Script exits before displaying the banner

Earlier drafts of the script had a Bash startup issue involving ANSI color initialization and `set -e`. Use the latest PR branch revision. Diagnose with:

```bash
bash -n lab-gsp395.sh
bash -x lab-gsp395.sh
echo "Exit code: $?"
```

### Region not configured

The region must match the **GCP Region** shown on the Google Skills launch page. Do not infer it from the VM zone or replace it with a region that happens to have capacity.

### Instance creation fails due to insufficient resources

If AlloyDB reports insufficient capacity, retry after a short delay or follow the lab's official guidance. Do not silently change the region: doing so may cause grader failures.

### SQL connection fails

Confirm that the primary instance is ready, the VM is `alloydb-client`, the IP is the private IP of `lab-instance`, and you are using the temporary lab PostgreSQL password.

### Existing tables

The automated script uses `CREATE TABLE IF NOT EXISTS` and `ON CONFLICT DO NOTHING` to make reruns safer. This does **not** repair an incorrectly defined existing schema. Inspect table definitions with `\d regions`, `\d countries`, and `\d departments` if the grader does not pass.

## Final checklist

- [ ] Cluster `lab-cluster` and primary `lab-instance` created in the assigned region
- [ ] Three HR tables created with the specified columns and primary keys
- [ ] Exactly 4 regions, 9 countries, and 6 departments loaded
- [ ] Two-node read pool `lab-instance-rp1` created
- [ ] Backup `lab-backup` completed
- [ ] Every Google Skills checkpoint reports success

---

*Published as a practical lab walkthrough by ePlus.DEV. This document is based on the challenge requirements and draft automation; it does not claim a verified 100% score.*
