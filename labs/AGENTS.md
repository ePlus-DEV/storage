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

## Canonical solution and documentation format (reference: PR #38)

Treat [PR #38](https://github.com/ePlus-DEV/storage/pull/38), especially its `labs/GSP1087/README.md`, `HASHNODE.md`, and PR description, as the structural reference for **new lab solutions**. Always deliver a full solution, not just an executable script:

- Each `labs/GSPxxxx/` contains **`lab.sh`, `README.md`, and `HASHNODE.md`** in the same PR.
- **README.md:** official lab URL, overview and objectives, exact environment expectations, runnable script command, concise validation, limitations, and links to the full guide.
- **HASHNODE.md:** official lab URL, objectives and prerequisites, complete **Task 1–N** walkthrough with real commands, expected results and checkpoints, a **Solution of Lab** section with exactly the subheadings **Quick**, **Manual**, **Other Solution**, troubleshooting, validation, attribution/copyright.
- **Quick** may point to `main` **only after merge**. Before merging, both PR description and documentation must provide a tested-in-principle **draft branch / resolved SHA** download example. Never represent an unmerged `main` URL as runnable.
- **PR description:** direct links to script, README and Hashnode guide; copy-ready Cloud Shell command using the PR branch, `git ls-remote` SHA resolution, `curl -fL`, `FORCE_COLOR=1`, and optional `tee`; checkpoint/evidence table; known limitations and unverified grader status.
- **Execution:** use real ANSI escapes with `FORCE_COLOR=1`, ensure color initialization is safe under `set -Eeuo pipefail`, and independently check SSH/remote color behavior. **Automatically discover** project, region and VM zone; do not prompt for discoverable settings or hardcode regions/zones.
- Match the **structure**, not the lab-specific SQL or names, from PR #38. Do not copy GSP1087's pgbench/columnar logic into an unrelated challenge lab. Do not assert grader completion without user-provided scoring evidence.

## Published Hashnode article reference (canonical visual/editorial format)

Use the **actual published Markdown export** as the formatting reference, not merely PR #38: [hoangsvit/eplus.dev — GSP1087 final Hashnode export on main](https://github.com/hoangsvit/eplus.dev/blob/main/cmvuhqeh5000102nx42tofj4v.md).

- Match the published article's **YAML frontmatter names**: `title`, `seoTitle`, `seoDescription`, `slug` and `tags`. Do not invent a Hashnode `cuid`, `datePublished`, `cover` or `ogImage`: those are created by Hashnode at publication, or added only if real values are provided.
- Start the body with **Official lab**, **Source/Status** as appropriate; use **Overview**, **Objectives**, **Setup and requirements**, **Task 1..N**, horizontal rule, **Solution of Lab** (exact `Quick`, `Manual`, `Other Solution` subheadings), **Troubleshooting**, **Verification** and copyright.
- Use concise executable fenced `bash` and `sql` examples, explain expected results and grader checkpoints. Avoid a redundant H1 when the publishing platform already renders the article title.
- In unmerged PRs, `Quick` pointing at `main` must be marked **after merge only**; offer a branch/SHA-based Cloud Shell command separately for testing.
- Keep the source article's editorial **format** while adapting lab-specific requirements; never copy its GSP1087 SQL into GSP395 or imply verified scores without evidence.

### Final published article updates (main branch)

The **main branch export supersedes the earlier fixed commit**. Its `Solution of Lab → Manual` contains **Hashnode native video embeds**, e.g. `%[https://www.youtube.com/watch?v=...]`, instead of a prose instruction saying to follow the tasks above. For new articles, **include valid, verified, lab-specific YouTube embeds only when actual URLs are available**. Never copy the GSP1087 video URLs to an unrelated lab, and never fabricate videos. If none exists, keep a meaningful written manual walkthrough or explicitly indicate that no verified video is available.

Preserve Hashnode's authored body structure and metadata when using the published Markdown as a template. Publication-generated metadata (`cuid`, `datePublished`, `cover`, `ogImage`) must be used only for the particular published article, never reused for a new article.
