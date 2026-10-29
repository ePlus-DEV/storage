#!/usr/bin/env python3
"""Unit tests for the read-only lab script audit."""
import tempfile
import unittest
from pathlib import Path

from script_health import scan, render


class ScriptHealthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "labs").mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def add(self, name: str, content: str) -> None:
        target = self.root / "labs" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def test_finds_known_high_priority_problems(self):
        self.add("danger/lab.sh", "#!/bin/bash\ngcloud storage buckets add-iam-policy-binding gs://x --member=allUsers --role=roles/storage.admin\n")
        self.add("pip/lab.sh", "#!/bin/bash\npip install ---upgrade protobuf\n")
        self.add("empty/lab.sh", "")
        results, total = scan(self.root)
        self.assertEqual(total, 3)
        by_rule = {entry.rule for entry in results}
        self.assertTrue({"public-storage-admin", "invalid-pip-option", "empty-script"} <= by_rule)

    def test_finds_deprecated_and_review_only_patterns(self):
        self.add("old/lab.sh", "#!/bin/bash\nMODEL_ID=\"gemini-pro\"\ngsutil ls\ngcloud alpha services api-keys list\n")
        self.add("auth/lab.sh", "#!/bin/bash\ngcloud iam service-accounts keys create key.json --iam-account=x\n")
        results, _ = scan(self.root)
        rules = {entry.rule for entry in results}
        self.assertTrue({"legacy-gemini-pro", "gsutil", "gcloud-alpha", "service-account-key"} <= rules)

    def test_ignores_comments_and_prevents_repeated_rule_matches(self):
        self.add("sample/lab.sh", "#!/bin/bash\n# gsutil ls\n# MODEL_ID=gemini-pro\ngsutil ls\ngsutil cp a b\n")
        results, _ = scan(self.root)
        self.assertEqual([entry.rule for entry in results], ["gsutil"])

    def test_identical_nonempty_script_detection(self):
        body = "#!/bin/bash\n" + ("echo same\n" * 20)
        self.add("sa/lab.sh", body)
        self.add("vpc/lab.sh", body)
        results, _ = scan(self.root)
        self.assertEqual(sum(entry.rule == "duplicate-script" for entry in results), 2)

    def test_report_is_deterministic(self):
        self.add("example/lab.sh", "#!/bin/bash\ngsutil ls\n")
        findings, count = scan(self.root)
        report = render(findings, count)
        self.assertEqual(report, render(findings, count))
        self.assertIn("Bash scripts scanned:** 1", report)
        self.assertIn("labs/example/lab.sh:2", report)
        self.assertIn("\n## Findings for review\n", report)


if __name__ == "__main__":
    unittest.main()
