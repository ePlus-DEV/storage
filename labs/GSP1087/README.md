# GSP1087 — Accelerating Analytical Queries using the AlloyDB Columnar Engine

Official lab: https://www.skills.google/focuses/100850 (manual updated 2026-08-03).

Run only in the authorized lab Cloud Shell. It expects preprovisioned `lab-cluster`, `lab-instance`, and `alloydb-client`. The database password is entered interactively on the VM, never hardcoded.

Covers five official tasks: create 50-million-row `pgbench` baseline (checkpoint 50); baseline query and EXPLAIN; verify preconfigured `google_columnar_engine.enabled=on` without overwriting flags; ensure extension; add `pgbench_accounts` to column store and compare plan (checkpoint 50). Reruns do not drop populated tables. Expect several minutes for 50M rows.

Validation: static only; no authorized runtime or grader evidence. Original script based on public Google Skills instructions and Google Cloud columnar-engine documentation; no third-party code copied. Copyright (c) 2026 ePlus.DEV | Unlicense.

Docs: https://docs.cloud.google.com/alloydb/docs/columnar-engine/manage-content-manually
