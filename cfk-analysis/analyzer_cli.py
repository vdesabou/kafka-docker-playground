#!/usr/bin/env python3
"""
CFK Bundle Analyzer — CLI entrypoint.
Wraps CFKBundleAnalyzer + DataSanitizer + recommendations for shell use.

Usage:
  analyzer_cli.py <bundle-path> [--json] [--no-sanitize] [--severity LEVEL] [--top N]

<bundle-path> may be a directory or a .tar / .tar.gz / .tgz / .zip archive.
Archives are extracted to a temp directory that is cleaned up on exit.
"""

import argparse
import json
import os
import shutil
import sys
import tarfile
import tempfile
import zipfile
from collections import defaultdict
from contextlib import contextmanager, redirect_stdout
from typing import Optional, Tuple

from analyzer import CFKBundleAnalyzer
from sanitizer import DataSanitizer
import recommendations
import html_report


SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3}
SEVERITY_GLYPH = {"critical": "[CRIT]", "high": "[HIGH]", "medium": "[MED ]", "low": "[LOW ]"}


def is_archive(path: str) -> bool:
    p = path.lower()
    return p.endswith((".tar.gz", ".tgz", ".tar", ".zip"))


@contextmanager
def extracted_bundle(path: str):
    """Yield a directory containing the bundle contents. Cleans up if extracted."""
    if os.path.isdir(path):
        yield path
        return

    if not os.path.isfile(path):
        raise FileNotFoundError(f"Bundle path does not exist: {path}")

    if not is_archive(path):
        raise ValueError(
            f"Unsupported bundle format: {path} "
            "(expected directory, .tar, .tar.gz, .tgz, or .zip)"
        )

    tmp = tempfile.mkdtemp(prefix="cfk-bundle-")
    try:
        if path.lower().endswith(".zip"):
            with zipfile.ZipFile(path, "r") as zf:
                zf.extractall(tmp)
        else:
            with tarfile.open(path, "r:*") as tf:
                tf.extractall(tmp)

        # If the archive has a single top-level directory, descend into it
        entries = [e for e in os.listdir(tmp) if not e.startswith(".")]
        if len(entries) == 1 and os.path.isdir(os.path.join(tmp, entries[0])):
            yield os.path.join(tmp, entries[0])
        else:
            yield tmp
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def filter_by_severity(issues, minimum: Optional[str]):
    if not minimum:
        return issues
    threshold = SEVERITY_ORDER.get(minimum.lower())
    if threshold is None:
        return issues
    return [i for i in issues if SEVERITY_ORDER.get(i["severity"], 99) <= threshold]


def group_by_category(issues):
    grouped = defaultdict(list)
    for i in issues:
        grouped[i["category"]].append(i)
    return grouped


def print_text_report(results, top: int):
    summary = results["summary"]
    issues = results["issues"]

    print("=" * 72)
    print("CFK Bundle Analysis")
    print("=" * 72)
    print(f"Files analyzed:   {summary['files_analyzed']}")
    print(f"Analysis time:    {summary['analysis_time']:.2f}s")
    print(f"Total issues:     {summary['total_issues']}")
    print(f"  critical:       {summary['critical']}")
    print(f"  high:           {summary['high']}")
    print(f"  medium:         {summary['medium']}")
    print(f"  low:            {summary['low']}")
    print()

    if not issues:
        print("No issues detected. Bundle looks clean.")
        return

    grouped = group_by_category(issues)
    categories_sorted = sorted(
        grouped.keys(),
        key=lambda c: min(SEVERITY_ORDER.get(i["severity"], 99) for i in grouped[c]),
    )

    print("-" * 72)
    print("Issues by category")
    print("-" * 72)
    for cat in categories_sorted:
        items = grouped[cat]
        worst = min(SEVERITY_ORDER.get(i["severity"], 99) for i in items)
        worst_name = next(k for k, v in SEVERITY_ORDER.items() if v == worst)
        print(f"\n## {cat}  ({len(items)} issues, worst={worst_name})")

        for issue in items[:top]:
            glyph = SEVERITY_GLYPH.get(issue["severity"], "[?   ]")
            loc = issue["file"]
            if issue.get("line_number"):
                loc += f":{issue['line_number']}"
            msg = issue["message"]
            if len(msg) > 180:
                msg = msg[:177] + "..."
            print(f"  {glyph} {loc}")
            print(f"         {msg}")

        if len(items) > top:
            print(f"  ... and {len(items) - top} more in this category")

        rec = recommendations.for_category(cat)
        print(f"\n  --> {rec['summary']}")
        print("  Recommended steps:")
        for step in rec["steps"]:
            print(f"    - {step}")
        if rec.get("docs"):
            print(f"  Docs: {rec['docs']}")

    print()
    print("=" * 72)
    print("Notes")
    print("=" * 72)
    print("- This report combines pattern detection with category-level remediation.")
    print("- For JVM GC analysis on a specific component: playground debug gc-analyze")
    print("- For full diagnostics: playground debug generate-diagnostics")
    print()


def run(
    bundle_path: str,
    sanitize: bool,
    severity: Optional[str],
    top: int,
    as_json: bool,
    html_out: Optional[str] = None,
) -> int:
    with extracted_bundle(bundle_path) as bundle_dir:
        analyzer = CFKBundleAnalyzer(bundle_dir)
        # analyzer.analyze() prints decode/parse warnings via print() to stdout.
        # Send those to stderr so --json mode produces clean JSON on stdout.
        with redirect_stdout(sys.stderr):
            results = analyzer.analyze()

    if sanitize:
        results = DataSanitizer().sanitize_results(results)

    if severity:
        results["issues"] = filter_by_severity(results["issues"], severity)
        counts = {"critical": 0, "high": 0, "medium": 0, "low": 0}
        for i in results["issues"]:
            counts[i["severity"]] = counts.get(i["severity"], 0) + 1
        results["summary"].update(counts)
        results["summary"]["total_issues"] = len(results["issues"])

    if html_out:
        rendered = html_report.render(results, bundle_label=os.path.basename(bundle_path))
        os.makedirs(os.path.dirname(os.path.abspath(html_out)), exist_ok=True)
        with open(html_out, "w", encoding="utf-8") as f:
            f.write(rendered)
        print(html_out, file=sys.stderr)

    if as_json:
        for issue in results["issues"]:
            issue["recommendation"] = recommendations.for_category(issue["category"])
        json.dump(results, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
    elif not html_out:
        # Text report by default; skip if user only asked for HTML.
        print_text_report(results, top=top)

    crit = results["summary"]["critical"]
    high = results["summary"]["high"]
    if crit > 0:
        return 2
    if high > 0:
        return 1
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        prog="analyzer_cli.py",
        description="Analyze a CFK support bundle and print issues + remediation steps.",
    )
    p.add_argument("bundle", help="Path to a CFK bundle (directory or .tar.gz/.tgz/.tar/.zip)")
    p.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of text report")
    p.add_argument("--no-sanitize", action="store_true", help="Do NOT redact IPs/hostnames/secrets in output (internal bundles only)")
    p.add_argument("--severity", choices=["critical", "high", "medium", "low"], help="Minimum severity to include")
    p.add_argument("--top", type=int, default=5, help="Max issues to show per category in text mode (default: 5)")
    p.add_argument("--html-out", help="Write a self-contained HTML report to this path")
    args = p.parse_args()

    try:
        return run(
            bundle_path=args.bundle,
            sanitize=not args.no_sanitize,
            severity=args.severity,
            top=max(1, args.top),
            as_json=args.json,
            html_out=args.html_out,
        )
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 64
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 64


if __name__ == "__main__":
    sys.exit(main())
