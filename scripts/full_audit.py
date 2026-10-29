#!/usr/bin/env python3
"""Read-only repository-wide static audit. Never runs lab scripts or cloud commands."""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import quote

PATTERNS = (
    ("P0", "public-storage-admin", re.compile(r"(?i)(allusers.{0,140}roles/storage\.admin|roles/storage\.admin.{0,140}allusers)"), "Public users given Storage Admin permission."),
    ("P0", "invalid-pip-option", re.compile(r"\bpip(?:3)?\s+install\s+---[a-z-]+"), "pip install uses invalid triple-dash option."),
    ("P1", "legacy-gemini-pro", re.compile(r"(?<![\w-])gemini-pro(?![\w-])"), "Legacy Gemini Pro model name; validate supported lab replacement."),
    ("P1", "service-account-key", re.compile(r"\bgcloud\s+iam\s+service-accounts\s+keys\s+create\b"), "Creates long-lived service-account key; consider keyless auth."),
    ("P1", "public-owner-permission", re.compile(r"(?i)(allusers.{0,140}roles/(?:owner|editor)|roles/(?:owner|editor).{0,140}allusers)"), "Public users granted broad project permissions."),
    ("P1", "remote-script-execution", re.compile(r"(?:curl|wget)\s+[^|\n]+\|\s*(?:sudo\s+)?(?:ba)?sh\b"), "Downloads and executes remote script; verify source and integrity."),
    ("P2", "hardcoded-location", re.compile(r"\b(?:REGION|ZONE|LOCATION)\s*=\s*['\"]?(?:us|europe|asia|australia|northamerica|southamerica|me|africa)-(?:[a-z0-9-]+)(?:[0-9])(?:-[a-z])?['\"]?"), "Hardcoded location may not match assigned lab."),
    ("P2", "legacy-gsutil", re.compile(r"(?<![\w-])gsutil\b"), "Uses gsutil; review availability and migration."),
    ("P2", "unstable-gcloud", re.compile(r"\bgcloud\s+(?:alpha|beta)\b"), "Uses alpha/beta gcloud; review stability."),
    ("P2", "suppressed-errors", re.compile(r"(?:\|\|\s*true|\|\|\s*:)"), "Suppressed command error; confirm intentional."),
    ("P2", "insecure-curl", re.compile(r"\bcurl\s+(-[A-Za-z]*k[A-Za-z]*\b|--insecure\b)"), "TLS certificate validation disabled."),
)
ORDER = {"P0": 0, "P1": 1, "P2": 2}

def add(findings, severity, rule, path, line, message):
    findings.append({"severity": severity, "rule": rule, "path": path, "line": line, "message": message})

def run_cmd(command, root, timeout=30):
    try:
        return subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return exc

def audit(root: Path, with_shellcheck=True):
    labs = root / "labs"
    if not labs.is_dir():
        raise ValueError(f"Cannot find labs directory: {labs}")
    scripts = sorted(p for p in labs.rglob("*.sh") if p.is_file())
    py_files = sorted(p for p in labs.rglob("*.py") if p.is_file())
    json_files = sorted(p for p in labs.rglob("*.json") if p.is_file())
    js_files = sorted(p for p in labs.rglob("*.js") if p.is_file())
    notebooks = sorted(p for p in labs.rglob("*.ipynb") if p.is_file())
    unparsed_files = [p for p in labs.rglob("*") if p.is_file() and p.suffix in {".tf", ".bat", ".yaml", ".yml"}]
    findings, duplicates = [], defaultdict(list)
    shellcheck_found = shutil.which("shellcheck") is not None and with_shellcheck
    stats = {"shell_scripts": len(scripts), "python_files": len(py_files),
             "json_files": len(json_files), "javascript_files": len(js_files),
             "notebook_files": len(notebooks), "unparsed_other_code_files": len(unparsed_files),
             "shellcheck_available": shellcheck_found,
             "shellcheck_error_scripts": 0, "bash_syntax_error_scripts": 0}
    for path in scripts:
        rel = path.relative_to(root).as_posix()
        raw = path.read_bytes()
        content = raw.decode("utf-8", errors="replace")
        if not content.strip():
            add(findings, "P0", "empty-script", rel, 1, "Script file is empty.")
            continue
        if len(raw) > 128:
            duplicates[hashlib.sha256(raw).hexdigest()].append(rel)
        # bash -n only parses the file; no commands are executed.
        result = run_cmd(["bash", "-n", rel], root)
        if isinstance(result, Exception) or result.returncode:
            stats["bash_syntax_error_scripts"] += 1
            error = str(result) if isinstance(result, Exception) else (result.stderr or result.stdout)
            lineno = re.search(r"line (\d+)", error)
            add(findings, "P0", "bash-syntax", rel, int(lineno.group(1)) if lineno else 1,
                error.strip().splitlines()[-1][:400] if error.strip() else "Bash syntax check failed.")
        if shellcheck_found:
            result = run_cmd(["shellcheck", "--format=json", "--severity=error", "--", rel], root)
            if isinstance(result, Exception):
                add(findings, "P1", "shellcheck-unavailable", rel, 1, str(result)[:250])
            else:
                try:
                    messages = json.loads(result.stdout or "[]")
                except json.JSONDecodeError:
                    messages = []
                    if result.returncode:
                        add(findings, "P1", "shellcheck-failed", rel, 1, (result.stderr or result.stdout).strip()[:250])
                if messages:
                    stats["shellcheck_error_scripts"] += 1
                for m in messages[:12]:
                    add(findings, "P1", f"shellcheck-SC{m.get('code', '?')}", rel,
                        m.get("line", 1), m.get("message", "ShellCheck error")[:300])
                if len(messages) > 12:
                    add(findings, "P2", "shellcheck-truncated", rel, 1,
                        f"{len(messages)} ShellCheck diagnostics; first 12 shown.")
        seen = set()
        for number, line in enumerate(content.splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for priority, rule, regex, message in PATTERNS:
                if rule not in seen and regex.search(line):
                    add(findings, priority, rule, rel, number, message)
                    seen.add(rule)
        if not content.startswith("#!"):
            add(findings, "P2", "missing-shebang", rel, 1, "No shebang on first line; direct execution may differ.")
        if rel.endswith("lab..sh"):
            add(findings, "P2", "unusual-filename", rel, 1, "File named lab..sh; verify intended public link.")
    for group in duplicates.values():
        if len(group) > 1:
            for rel in group:
                add(findings, "P1", "identical-script", rel, 1,
                    "Byte-identical to: " + ", ".join(p for p in group if p != rel))
    for path in py_files:
        rel = path.relative_to(root).as_posix()
        try:
            compile(path.read_text(encoding="utf-8"), rel, "exec")
        except (SyntaxError, UnicodeError) as exc:
            add(findings, "P0", "python-syntax", rel, getattr(exc, "lineno", 1) or 1, str(exc)[:300])
    for path in json_files:
        rel = path.relative_to(root).as_posix()
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeError) as exc:
            add(findings, "P0", "invalid-json", rel, getattr(exc, "lineno", 1) or 1, str(exc)[:300])
    for path in js_files:
        rel = path.relative_to(root).as_posix()
        if not shutil.which("node"):
            add(findings, "P2", "node-unavailable", rel, 1, "Node.js not installed; syntax check skipped.")
            continue
        result = run_cmd(["node", "--check", rel], root)
        if isinstance(result, Exception) or result.returncode:
            err = str(result) if isinstance(result, Exception) else (result.stderr or result.stdout)
            lineno = re.search(r":(\d+)\b", err)
            add(findings, "P0", "javascript-syntax", rel, int(lineno.group(1)) if lineno else 1,
                err.strip().splitlines()[-1][:300] if err.strip() else "Node syntax check failed.")
    for path in notebooks:
        rel = path.relative_to(root).as_posix()
        try:
            notebook = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(notebook, dict) or not isinstance(notebook.get("cells"), list):
                add(findings, "P0", "invalid-notebook", rel, 1, "Notebook is missing a valid cells array.")
            else:
                for cell in notebook["cells"]:
                    if cell.get("cell_type") == "code":
                        source = cell.get("source", [])
                        source = "".join(source) if isinstance(source, list) else str(source)
                        if re.search(r"(?<![\w-])gemini-pro(?![\w-])", source):
                            add(findings, "P1", "legacy-gemini-pro-notebook", rel, 1,
                                "Code cell references old Gemini Pro model; verify current lab model.")
                            break
        except (json.JSONDecodeError, UnicodeError, AttributeError) as exc:
            add(findings, "P0", "invalid-notebook", rel, getattr(exc, "lineno", 1) or 1, str(exc)[:300])

    findings.sort(key=lambda f: (ORDER[f["severity"]], f["rule"], f["path"], f["line"]))
    return {"stats": stats, "findings": findings}

def make_report(result: dict) -> str:
    stats, findings = result["stats"], result["findings"]
    count = Counter(f["rule"] for f in findings)
    priorities = Counter(f["severity"] for f in findings)
    files = {f["path"] for f in findings}
    rows = [
        "# Full Repository Lab Script Audit", "",
        "> Static audit only: no lab commands were executed.",
        "> P0 syntax/empty/invalid JSON are confirmed statically.",
        "> ShellCheck and API/security hints need manual context review.", "",
        f"- Bash scripts scanned: **{stats['shell_scripts']}**",
        f"- Python files parsed: **{stats['python_files']}**",
        f"- JSON files parsed: **{stats['json_files']}**",
        f"- JavaScript files checked: **{stats['javascript_files']}**",
        f"- Notebooks validated as JSON: **{stats['notebook_files']}**",
        f"- Other code files not syntax-checked (Terraform/YAML/BAT): **{stats['unparsed_other_code_files']}**",
        f"- ShellCheck available: **{stats['shellcheck_available']}**",
        f"- Bash syntax failures: **{stats['bash_syntax_error_scripts']}**",
        f"- Scripts with ShellCheck error diagnostics: **{stats['shellcheck_error_scripts']}**",
        f"- Findings P0 / P1 / P2: **{priorities['P0']} / {priorities['P1']} / {priorities['P2']}**",
        f"- Files with findings: **{len(files)}**", "",
        "## Issues by category", "",
        "| Severity | Rule | Findings |", "| --- | --- | ---: |",
    ]
    first = {}
    for f in findings:
        first.setdefault(f["rule"], f["severity"])
    for rule in sorted(count, key=lambda r: (ORDER[first[r]], r)):
        rows.append(f"| {first[rule]} | {rule} | {count[rule]} |")
    rows += ["", "## P0 and P1 findings", "", "| Priority | Rule | Location | Message |",
             "| --- | --- | --- | --- |"]
    high = [f for f in findings if f["severity"] != "P2"]
    for f in high[:300]:
        url = "https://github.com/ePlus-DEV/storage/blob/main/" + quote(f["path"], safe="/") + "#L" + str(f["line"])
        label = f["path"] + ":" + str(f["line"])
        message = f["message"].replace("|", r"\|").replace("\n", " ")
        rows.append(f"| {f['severity']} | {f['rule']} | [{label}]({url}) | {message} |")
    if len(high) > 300:
        rows.append(f"\nShowing first 300 of {len(high)} P0/P1 findings; see JSON artifact for all.")
    rows += ["", "## Limitations", "",
        "- No proof of Google Skills Boost grading or live API/model compatibility.",
        "- Notebook cell Python/SQL/magic runtime semantics are not executed; only notebook JSON structure is validated.",
        "- Terraform, YAML, and BAT scripts are inventoried but not syntax-checked in this version.",
        "- Some ShellCheck diagnostics can be false positives due to embedded scripts and heredocs.",
        "- P2 maintenance hints are not confirmed runtime errors.",
        "- Do not execute lab provisioning, destructive operations, or IAM changes in this workflow.",
        "- Keep existing changed-file PR validation as the merge gate.", ""]
    return "\n".join(rows)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, default=Path("."))
    p.add_argument("--out-dir", type=Path, default=Path("audit-output"))
    p.add_argument("--skip-shellcheck", action="store_true")
    a = p.parse_args()
    root = a.root.resolve()
    result = audit(root, with_shellcheck=not a.skip_shellcheck)
    out = a.out_dir if a.out_dir.is_absolute() else root / a.out_dir
    out.mkdir(parents=True, exist_ok=True)
    (out / "full-lab-audit.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out / "full-lab-audit.md").write_text(make_report(result), encoding="utf-8")
    stats = result["stats"]
    count = Counter(f["rule"] for f in result["findings"])
    print("FULL_AUDIT_STATS=" + json.dumps(stats, sort_keys=True))
    print("FULL_AUDIT_RULE_COUNTS=" + json.dumps(dict(count.most_common()), sort_keys=True))
    for f in [x for x in result["findings"] if x["severity"] == "P0"][:80]:
        print("CONFIRMED_OR_CRITICAL=" + json.dumps(f, ensure_ascii=False))
    print(f"Generated reports at {out}. This static scan does not execute lab commands.")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"Full audit FAILED: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(2)
