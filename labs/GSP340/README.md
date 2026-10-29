# Build a Data Warehouse with BigQuery: Challenge Lab (GSP340)

- Lab overview and the **four-task variant** implemented here: <https://eplus.dev/build-a-data-warehouse-with-bigquery-challenge-lab-gsp340>
- Official lab: <https://www.cloudskillsboost.google/course_templates/624/labs/548384> (may require sign-in)
- License: repository root [Unlicense](../../LICENSE). The ePlus.DEV console attribution is informational.

## Important: randomized challenge variants

GSP340 can assign **different tasks and values** in different lab sessions. The defaults in `lab.sh` target the variant described in the overview above:

| Task | Expected operation | Default |
| --- | --- | --- |
| 1 | Create a date-partitioned Oxford tracker table, excluding GBR/BRA/CAN/USA | `covid.oxford_policy_tracker`, **1080** partition-expiration days |
| 2 | Update the six averaged mobility fields in a lab-provisioned table | `covid_data.consolidate_covid_tracker_data` |
| 3 | Query countries missing population or area, preserving duplicate country names when both are missing | `covid_data.oxford_policy_tracker_worldwide` |
| 4 | Copy the ECDC public table into the lab dataset | `covid_data.pop_data_2019` |

**Before running, compare all four tasks on your current Skills Boost page.** If your lab asks for a different table, task, or schema, this script is not a validated solution for that variant. Do not blindly run it. Another publicly documented variant uses **2175** days and different tasks/tables; this is not interchangeable.

## Run from Cloud Shell in the temporary lab project

```bash
curl -fsSLO https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/GSP340/lab.sh
less lab.sh  # review the operations and confirm the four tasks match
bash lab.sh
```

The script reads the project from `PROJECT_ID`, `DEVSHELL_PROJECT_ID`, or the active `gcloud` configuration. It reads the BigQuery location from the pre-provisioned `covid_data` dataset. It does not create the pre-provisioned lab dataset or tables; it waits for them to become available (up to six attempts, 10 seconds apart).

For a variant with a **different partition-expiration period but the same four tasks**, set the value explicitly, for example:

```bash
EXPIRY_DAYS=2175 bash lab.sh
```

You may also override `DS_COVID`, `DS_MAIN`, `TBL_TRACKER`, `TBL_CONSOLIDATED`, `TBL_WORLDWIDE`, and `TBL_POP` **only when the task text explicitly specifies those names**. The script changes BigQuery data and uses `CREATE OR REPLACE TABLE` for Task 1 and Task 4; run only in the disposable lab project.

**Partition expiration caveat:** BigQuery expires partitions based on the partition's date, not on the date the table was created. Old COVID-19 partitions may expire immediately with the lab's requested expiration period. Keep the value exactly as specified by the grader; do not silently extend it.

## Validation and sources

- Local static checks: `bash -n` and mock BigQuery command/SQL-shape assertions. The PR's **Lab Script Health** check runs ShellCheck (error severity) and syntax checks on changed scripts.
- **Static validated only; runtime/grader unverified.** No temporary Google Skills project was available to run the queries or click **Check my progress**.
- SQL syntax references: [BigQuery DDL](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language) and [BigQuery UPDATE/DML](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax).
- Independently reviewed community approaches (not copied): [ravi-arnan/gsp_lab_solutions](https://github.com/ravi-arnan/gsp_lab_solutions/blob/main/docs/gsp340.md) and [prateekrajput08/Arcade-Google-Cloud-Labs](https://github.com/prateekrajput08/Arcade-Google-Cloud-Labs/tree/main/Build%20a%20Data%20Warehouse%20with%20BigQuery%3A%20Challenge%20Lab). The first source explicitly notes randomized variants; its runbook and script currently describe different task variants, so neither should be treated as a universal solution.
