# Lab Script Health Automation

This automation is **PR-first**. It audits scripts and opens a **draft pull request
for human review**. It never auto-merges, rewrites lab solutions, or starts
Google Cloud resources.

## Behavior

- **Every pull request touching labs or audit tooling:** run unit tests, then
  `bash -n` and ShellCheck error-level checks on **changed `.sh` files only**.
  Existing unrelated lab issues will not block new PRs.
- **Every Monday at 09:19 (Asia/Ho_Chi_Minh):** scan all Bash scripts in
  `labs/`, regenerate `docs/script-health-report.md`, and create/update
  the single draft PR on branch `automation/script-health-report`.
- **Manual trigger:** GitHub Actions > Lab Script Health > Run workflow.
- **No report diff:** no new PR or commit. The report is deterministic;
  it does not include run timestamps.
- **No scripts are executed during audit.** Any change to a lab's commands
  requires a separate, scoped PR and testing in the actual temporary lab.

## Scans included

| Priority | Check | Interpretation |
| --- | --- | --- |
| P0 | Public Storage Admin grant | Unsafe broad IAM; review immediately |
| P0 | Invalid `pip install ---...` option | Confirmed typo |
| P0 | Empty Bash script | Missing executable lab content |
| P1 | Legacy `gemini-pro` model | Verify supported replacement for the lab |
| P1 | Service-account JSON key creation | Check whether keyless auth is possible |
| P1 | Duplicate nonempty script contents | Check for accidental copying |
| P2 | `gsutil` dependency | Plan tested migration to `gcloud storage` |
| P2 | `gcloud alpha/beta` commands | Check if stable command is available |

This is **static evidence only**, not a claim that every flagged script
fails today. The generated report shows at most 120 examples; counts cover
all findings.

## Run locally

```bash
python3 -m unittest discover -s scripts -p 'test_script_health.py' -v
python3 scripts/script_health.py --root . --report docs/script-health-report.md
python3 scripts/script_health.py --root . --max-rows 200
```

## GitHub repository settings

The scheduled job needs `contents: write` and `pull-requests: write`
from its scoped `GITHUB_TOKEN`. Under **Settings > Actions > General >
Workflow permissions**, ensure **Allow GitHub Actions to create and
approve pull requests** is enabled. The workflow itself never approves PRs.

A PR created by `GITHUB_TOKEN` normally does **not** trigger other
`pull_request` workflows. The scheduled job runs its own audit/unit tests
before creating/updating the report PR. Subsequent human PRs changing
individual lab scripts receive read-only syntax checks.

## Review policy

1. Check the report in the draft PR.
2. Confirm suspected deprecations using Google Cloud documentation and the
   current Skills Boost lab instructions.
3. Create a focused fix PR per lab or related lab family.
4. Validate in a disposable lab project and attach evidence of success.
5. Merge only after human review. Do not let this workflow auto-merge fixes.

The existing GitHub Pages deployment workflow is unchanged.
