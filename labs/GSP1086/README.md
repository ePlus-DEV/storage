# GSP1086 — Administering an AlloyDB Database

Official lab: https://www.skills.google/focuses/100851

Runs from the **authorized lab Cloud Shell**; do not run in a personal project. The lab provisions `lab-cluster`, `lab-instance`, and `alloydb-client`. Requires `gcloud` and interactive SSH access to the lab VM; the PostgreSQL password is prompted securely on the VM and never embedded in the script.

Coverage: inspect preconfigured `enable_pgaudit` flag; create and verify `pgaudit` extension (40 points); create two-node `lab-instance-rp1` read pool with 2 vCPU per node (30); create `lab-backup` (30); initialize 5-million-row pgbench dataset and run a 3-minute monitoring workload. Inspect Monitoring/Query Insights manually. Reruns skip existing correct data/resources.

Validation: static only, no authorized lab runtime or grader evidence. Code is original and derived from the public official task list; no third-party solution code copied. Copyright (c) 2026 ePlus.DEV | Unlicense.

Official CLI: https://docs.cloud.google.com/alloydb/docs/instance-read-pool-create and https://docs.cloud.google.com/sdk/gcloud/reference/alloydb/backups/create
