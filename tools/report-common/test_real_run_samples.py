#!/usr/bin/env python3
"""real_run_samples.sh builds the 7 reports of real runs of the website gallery from their synthetic inputs, each with the
header of every report (the 🐳 kafka-docker-playground badge) and without a local path (the gallery publishes them).

    python3 -I tools/report-common/test_real_run_samples.py
"""
import os
import re
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPORTS = ["connector-diagnose", "ci-result", "benchmark", "cve-scan", "connector-diff", "dlq", "smt-test"]


class RealRunSamples(unittest.TestCase):
    def test_every_report_built_with_the_header_and_no_local_path(self):
        with tempfile.TemporaryDirectory() as out:
            # from another folder: the script must not depend on the current directory
            subprocess.run(["bash", os.path.join(HERE, "real_run_samples.sh"), out], check=True, cwd=tempfile.gettempdir(),
                           stdout=subprocess.DEVNULL)
            for name in REPORTS:
                with self.subTest(report=name):
                    path = os.path.join(out, name + ".html")
                    self.assertTrue(os.path.exists(path), path)
                    with open(path, encoding="utf-8") as fh:
                        page = fh.read()
                    self.assertIn("lr-brand", page)
                    self.assertIsNone(re.search(r"/Users/|/home/|/private/|vscode://", page))


if __name__ == "__main__":
    unittest.main()
