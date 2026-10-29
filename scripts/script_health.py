#!/usr/bin/env python3
"""Conservative, read-only health checks for Google Cloud lab Bash scripts.

This tool never executes lab scripts or calls Google Cloud. Findings indicate
what requires human review; they are not proof that a lab failed at runtime.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import quote

REPO = "ePlus-DEV/storage"
SEVERITY_ORDER = {"P0": 0, "P1": 1, "P2": 2}
RULES = {
    "public-storage-admin": ("P0", "Public principal receives Storage Admin; remove this broad IAM grant."),
    "invalid-pip-option": ("P0", "Invalid pip option; verify the installation command."),
    "empty-script": ("P0", "Empty Bash script; restore or mark as incomplete."),
    "legacy-gemini-pro": ("P1", "Legacy gemini-pro identifier; verify a currently supported lab model."),
    "service-account-key": ("P1", "Creates a long-lived service-account key; prefer keyless auth when permitted."),
    "duplicate-script": ("P1", "Identical nonempty scripts; verify that each lab implements its own tasks."),
    "gsutil": ("P2", "gsutil dependency; plan a tested migration to gcloud storage."),
    "gcloud-alpha": ("P2", "gcloud alpha command; verify command stability and lab compatibility."),
    "gcloud-beta": ("P2", "gcloud beta command; verify whether stable commands are available."),
    "missing-branding": ("P2", "No ePlus.DEV attribution in the first 80 lines; consider a consistent banner."),
    "missing-color": ("P2", "No ANSI color setup in the first 80 lines; consider optional terminal colors."),
}

@dataclass(frozen=True)
class Finding:
    severity: str
    rule: str
    path: str
    line: int
    detail: str

def scan(root: Path) -> tuple[list[Finding], int]:
    lab_root = root / "labs"
    if not lab_root.is_dir():
        raise FileNotFoundError(f"Lab directory not found: {lab_root}")
    findings: list[Finding] = []
    hashes: dict[str, list[str]] = defaultdict(list)
    scripts = sorted(p for p in lab_root.rglob("*.sh") if p.is_file())
    for file in scripts:
        path = file.relative_to(root).as_posix()
        content = file.read_text(encoding="utf-8", errors="replace")
        if not content.strip():
            findings.append(Finding("P0", "empty-script", path, 1, RULES["empty-script"][1]))
            continue
        if len(content.encode("utf-8")) >= 128:
            hashes[hashlib.sha256(content.encode("utf-8")).hexdigest()].append(path)

        # Nonblocking presentation hints: only standalone lab.sh entrypoints.
        # Limit checks to the header so command comments and URLs do not count.
        if file.name == "lab.sh":
            header = "\n".join(content.splitlines()[:80])
            if not re.search(r"eplus[.\s-]*dev", header, re.IGNORECASE):
                findings.append(Finding("P2", "missing-branding", path, 1, RULES["missing-branding"][1]))
            if not re.search(r"\\033|\\e\[|tput\s+seta[fb]|\x1b\[", header):
                findings.append(Finding("P2", "missing-color", path, 1, RULES["missing-color"][1]))

        # Avoid multiple findings for the same rule in the same file.
        observed: set[str] = set()
        for number, line in enumerate(content.splitlines(), start=1):
            trimmed = line.lstrip()
            if trimmed.startswith("#"):
                continue
            matches = (
                ("public-storage-admin", bool(re.search(
                    r"(?i)(?:allusers.*roles/storage\.admin|roles/storage\.admin.*allusers)", line))),
                ("invalid-pip-option", bool(re.search(r"\bpip(?:3)?\s+install\s+---[a-z-]+", line))),
                ("legacy-gemini-pro", bool(re.search(r"(?<![\w-])gemini-pro(?![\w-])", line))),
                ("service-account-key", bool(re.search(r"\bgcloud\s+iam\s+service-accounts\s+keys\s+create\b", line))),
                ("gsutil", bool(re.search(r"\bgsutil\b", line))),
                ("gcloud-alpha", bool(re.search(r"\bgcloud\s+alpha\b", line))),
                ("gcloud-beta", bool(re.search(r"\bgcloud\s+beta\b", line))),
            )
            for rule, matched in matches:
                if matched and rule not in observed:
                    observed.add(rule)
                    level, detail = RULES[rule]
                    findings.append(Finding(level, rule, path, number, detail))
    for group in hashes.values():
        if len(group) < 2:
            continue
        # Duplicates are evidence for review, not necessarily an error.
        for path in group:
            peers = ", ".join(p for p in group if p != path)
            findings.append(Finding("P1", "duplicate-script", path, 1, f"Same content as: {peers}"))
    findings.sort(key=lambda f: (SEVERITY_ORDER[f.severity], f.rule, f.path, f.line))
    return findings, len(scripts)

def render(findings: list[Finding], count: int, max_rows: int = 120) -> str:
    counts = Counter(f.rule for f in findings)
    out = [
        "# Lab Script Health Report",
        "",
        "> Generated automatically by the read-only script audit. A finding is not a",
        "> runtime test failure. Verify against the actual lab and official documentation.",
        "",
        f"**Bash scripts scanned:** {count}. **Findings:** {len(findings)}.",
        "",
        "## Summary",
        "",
        "| Priority | Check | Affected scripts |",
        "| --- | --- | ---: |",
    ]
    for rule, (severity, _) in sorted(RULES.items(), key=lambda item: (SEVERITY_ORDER[item[1][0]], item[0])):
        out.append(f"| {severity} | `{rule}` | {counts[rule]} |")
    out += [
        "",
        "## Findings for review",
        "",
        "| Priority | Check | Script | Recommendation |",
        "| --- | --- | --- | --- |",
    ]
    for finding in findings[:max_rows]:
        url = f"https://github.com/{REPO}/blob/main/{quote(finding.path, safe='/')}#L{finding.line}"
        location = f"[`{finding.path}:{finding.line}`]({url})"
        detail = finding.detail.replace("|", "\|").replace("\n", " ")
        out.append(f"| {finding.severity} | `{finding.rule}` | {location} | {detail} |")
    if len(findings) > max_rows:
        out += ["", f"_Displaying {max_rows} of {len(findings)} findings. Increase --max-rows to view more._"]
    if not findings:
        out += ["| - | - | No findings | - |"]
    out += [
        "",
        "## What this report does not establish",
        "",
        "- No scripts have been executed, and no cloud resources are created.",
        "- Google Cloud service availability and lab grading are not verified here.",
        "- P2 migration hints (gsutil, alpha/beta) are not automatic failures.",
        "- Maintain lab-specific behavior; do not blindly replace commands.",
        "",
        "## Review workflow",
        "",
        "Fix each verified problem in a separate scoped PR; run the corresponding lab",
        "and attach its Check my progress evidence before marking it verified.",
        "",
    ]
    return "\n".join(out)

def check_changed(root: Path, base: str, head: str) -> int:
    """Run Bash parsing and ShellCheck (errors only) on changed scripts."""
    result = subprocess.run(
        ["git", "diff", "--name-only", "-z", "--diff-filter=ACMR", base, head, "--", "labs/"],
        cwd=root, check=True, capture_output=True,
    )
    changed = sorted(set(p.decode("utf-8") for p in result.stdout.split(b"\0") if p))
    scripts = [p for p in changed if p.endswith(".sh") and (root / p).is_file()]
    if not scripts:
        print("No changed Bash scripts; syntax check skipped.")
        return 0
    failures = 0
    use_shellcheck = shutil.which("shellcheck") is not None
    if not use_shellcheck:
        print("shellcheck is unavailable; bash -n still runs for every changed script.")
    for path in scripts:
        for command in ([["bash", "-n", path]] + ([["shellcheck", "--severity=error", "--", path]] if use_shellcheck else [])):
            outcome = subprocess.run(command, cwd=root, text=True, capture_output=True)
            if outcome.returncode:
                failures += 1
                print(f"FAIL {path}: {' '.join(command)}")
                print((outcome.stdout + "\n" + outcome.stderr).strip())
            else:
                print(f"OK {path}: {command[0]}")
    return 1 if failures else 0

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--report", type=Path, help="Write deterministic Markdown audit report")
    parser.add_argument("--max-rows", type=int, default=120)
    parser.add_argument("--check-changed", action="store_true", help="Lint changed lab scripts")
    parser.add_argument("--base", help="Base commit for --check-changed")
    parser.add_argument("--head", help="Head commit for --check-changed")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.check_changed:
        if not args.base or not args.head:
            parser.error("--check-changed requires --base and --head")
        return check_changed(root, args.base, args.head)
    findings, count = scan(root)
    report = render(findings, count, max_rows=max(0, args.max_rows))
    if args.report:
        target = args.report if args.report.is_absolute() else root / args.report
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_text(encoding="utf-8") != report:
            target.write_text(report, encoding="utf-8")
        print(f"Scanned {count} scripts; {len(findings)} findings; report: {target}")
    else:
        print(report)
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"Audit failed: {exc}", file=sys.stderr)
        sys.exit(2)
