# ePlus.DEV Google Cloud Lab Script Rules

These requirements apply to all scripts under `labs/` and to future lab-solution PRs.

1. **Auto-detect project, region, and zone.** Prefer the active `gcloud` project; then discover location from the provisioned lab VM, Cloud SDK configuration, project common instance metadata, or existing lab resources. Never hardcode project IDs, region, or zone. Never ask for values that can be discovered. If all supported discovery fails, print a specific diagnostic rather than silently choosing a region.
2. **Honor the lab's exact resource names, machine sizes, network, data and grader expectations.** Do not change region to work around capacity errors.
3. **One executable Bash script per lab**, with `ePlus.DEV – Starting Execution`, copyright `Copyright (c) 2026 ePlus.DEV | Unlicense`, numbered task banners, English logs, ANSI colors where supported, and `NO_COLOR`/`FORCE_COLOR` support. Color setup must not fail under `set -euo pipefail`.
4. **Make reruns safe.** Inspect existing resources and validate their configurations; do not destroy tables, data, clusters, or instances on retries. Wait/poll for long-running provisioning and report actionable failures.
5. **Validate actual results** using `gcloud describe`, SQL queries, and state checks. Do not claim Google Skills grader success without confirmation from a real authorized lab run.
6. **PR-only delivery.** Work on a feature branch and open a Draft PR; do not push to main or merge without approval. Include the exact branch-based Cloud Shell run command in the PR description.
7. **Include `HASHNODE.md`** in the same lab folder, with a full English walkthrough, exact task instructions, SQL/CLI, troubleshooting, and clear distinction between tested and untested results.
8. **Never execute the lab with an unauthorized account or project.** The user runs Cloud Shell with their temporary lab credentials.
