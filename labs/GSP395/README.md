# GSP395 — Create and Manage AlloyDB Instances: Challenge Lab

**Official lab:** https://www.skills.google/games/7501/labs/45914  
**Script:** [lab.sh](./lab.sh)  
**Full step-by-step Hashnode walkthrough:** [HASHNODE.md](./HASHNODE.md)  
**Automation rules:** [../AGENTS.md](../AGENTS.md)

## Lab objectives

1. Create `lab-cluster` with network `peering-network` and PRIMARY instance `lab-instance` (2 vCPU).
2. Create `regions`, `countries`, `departments` with the specified primary keys and column types.
3. Load respectively 4, 9, and 6 HR dataset rows using `psql` on `alloydb-client`.
4. Create `lab-instance-rp1` as a two-node READ_POOL with 2 vCPU.
5. Create on-demand backup `lab-backup`.

## Run the unmerged PR in Cloud Shell

```bash
set -o pipefail
REPO="ePlus-DEV/storage"
BRANCH="scout/new-gsp395-alloydb-challenge-20261030"
SHA="$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" | awk '{print $1}')"
test -n "$SHA" || { echo "PR branch not found"; exit 1; }
curl -fL --retry 3 "https://raw.githubusercontent.com/$REPO/$SHA/labs/GSP395/lab.sh" -o lab-gsp395-test.sh
bash -n lab-gsp395-test.sh || exit 1
FORCE_COLOR=1 bash lab-gsp395-test.sh 2>&1 | tee "gsp395-${SHA:0:12}.log"
```

The script discovers the lab project ID, region, and `alloydb-client` zone automatically. Do not change the Google Skills lab region to work around capacity errors.

## Solution of Lab

### Quick

This download targets `main`, so **use it only after PR #45 has been merged**.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP395/lab.sh
source lab.sh
```

### Manual

See the complete **Tasks 1–5** in [HASHNODE.md](./HASHNODE.md), including SQL schema, seed records, CLI commands, verification and troubleshooting.

### Other Solution

[Official lab instructions](https://www.skills.google/games/7501/labs/45914). No external third-party solution verified.

## Validation

Static source review and Bash syntax are not equivalent to grader success. After execution, use **Check my progress** for each task and review any mismatched resource configuration. The authorized GSP395 runtime and Google Skills grading remain unverified.

Copyright (c) 2026 ePlus.DEV | Unlicense.
