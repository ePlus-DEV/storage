# GSP1085 — Migrating to AlloyDB from PostgreSQL Using PostgreSQL Tools

Official lab: https://www.skills.google/focuses/100855 (manual updated 2026-08-13).

Run only in the authorized lab Cloud Shell. The lab provides `pg14-source`, `alloydb-client`, `lab-cluster`, `lab-instance` and a Cloud Storage bucket named after the project ID. No infrastructure is created outside the lab. The PostgreSQL password is prompted on the client VM; no secrets are embedded.

Covers three tasks and two checkpoints: verify six HR tables on source; generate `pg_dump -Fc` and upload `pg14_source.DMP` to the lab bucket (50 points); download the dump and restore with `pg_restore` after excluding extension entries, then verify six tables (50 points). Does not overwrite existing HR tables or lab dump objects. Uses SSH/SCP and temporary scoped files, with cleanup.

Validation: static only, no authorized lab runtime/grader evidence. Original script derived from public official task list; no third-party solution code copied. Copyright (c) 2026 ePlus.DEV | Unlicense.
