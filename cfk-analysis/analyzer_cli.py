#!/usr/bin/env python3
"""
CFK Bundle Analyzer — CLI entrypoint.
Wraps CFKBundleAnalyzer + DataSanitizer + recommendations for shell use.

Usage:
  analyzer_cli.py <bundle-path> [--json] [--no-sanitize] [--severity LEVEL] [--top N]
                  [--component NAME ...] [--include-warnings] [--html-out FILE]

<bundle-path> may be a directory or a .tar / .tar.gz / .tgz / .zip archive.
Archives are extracted to a temp directory that is cleaned up on exit.

Exit codes: 0 analysis done (whatever was found, see summary), 64 invalid or empty
bundle, 1 unexpected failure.
"""

import argparse
import json
import os
import re
import shutil
import sys
import tarfile
import tempfile
import zipfile
from collections import defaultdict
from contextlib import contextmanager, redirect_stdout
from typing import Optional, Tuple

from analyzer import CFKBundleAnalyzer, COMPONENTS  # also puts tools/report-common on sys.path
from sanitizer import DataSanitizer  # tools/report-common/sanitizer.py
import environment
import recommendations
import html_report


SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3}
SEVERITY_GLYPH = {"critical": "[CRIT]", "high": "[HIGH]", "medium": "[MED ]", "low": "[LOW ]"}


class BundleError(Exception):
    """Invalid, unsafe or empty bundle (exit 64)"""


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
        try:
            if path.lower().endswith(".zip"):
                with zipfile.ZipFile(path, "r") as zf:
                    for name in zf.namelist():
                        _check_member_name(name)
                    zf.extractall(tmp)
            else:
                with tarfile.open(path, "r:*") as tf:
                    members = [m for m in tf.getmembers() if _safe_tar_member(m)]
                    if hasattr(tarfile, "data_filter"):
                        tf.extractall(tmp, members=members, filter="data")
                    else:
                        tf.extractall(tmp, members=members)
        except (tarfile.TarError, zipfile.BadZipFile, EOFError, OSError) as e:
            raise BundleError(f"Cannot extract {os.path.basename(path)}: {e}")

        # If the archive has a single top-level directory, descend into it
        entries = [e for e in os.listdir(tmp) if not e.startswith(".")]
        if len(entries) == 1 and os.path.isdir(os.path.join(tmp, entries[0])):
            yield os.path.join(tmp, entries[0])
        else:
            yield tmp
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _check_member_name(name: str):
    """Reject absolute paths and `..` components (path traversal from a crafted archive)"""
    norm = name.replace("\\", "/")
    if norm.startswith("/") or re.match(r"^[A-Za-z]:", norm) or ".." in norm.split("/"):
        raise BundleError(f"Refusing to extract unsafe archive member: {name}")


def _safe_tar_member(member: tarfile.TarInfo) -> bool:
    """Keep regular files and directories only; links and devices are skipped"""
    _check_member_name(member.name)
    return member.isfile() or member.isdir()


def filter_by_severity(issues, minimum: Optional[str]):
    if not minimum:
        return issues
    threshold = SEVERITY_ORDER.get(minimum.lower())
    if threshold is None:
        return issues
    return [i for i in issues if SEVERITY_ORDER.get(i["severity"], 99) <= threshold]


def filter_by_component(issues, components):
    if not components:
        return issues
    return [i for i in issues if i.get("component") in components]


def recount(results):
    counts = {"critical": 0, "high": 0, "medium": 0, "low": 0}
    for i in results["issues"]:
        counts[i["severity"]] = counts.get(i["severity"], 0) + 1
    results["summary"].update(counts)
    results["summary"]["total_issues"] = len(results["issues"])


def component_counts(issues):
    """[(component, issue count)] in COMPONENTS order"""
    counts = defaultdict(int)
    for i in issues:
        counts[i.get("component", "other")] += 1
    return [(c, counts[c]) for c in COMPONENTS if counts[c]]


def group_by_category(issues):
    grouped = defaultdict(list)
    for i in issues:
        grouped[i["category"]].append(i)
    return grouped


def print_environment(results, timeline_limit: int = 12):
    """Versions and images, then the latest changes (newest first)"""
    env = results.get("environment") or {}
    components = env.get("components") or {}
    if env.get("kubernetes_version") or env.get("cfk_version") or components:
        print("-" * 72)
        print("Environment")
        print("-" * 72)
        if env.get("kubernetes_version"):
            print(f"Kubernetes:       {env['kubernetes_version']}")
        if env.get("cfk_version") or env.get("operator_image_tag"):
            print(f"CFK operator:     {env.get('cfk_version', '?')} (image tag {env.get('operator_image_tag', '?')})")
        for name, info in sorted(components.items()):
            line = f"  {name:<24} {info.get('image', '?')}"
            if info.get("init_image"):
                line += f"  init {environment.image_tag(info['init_image']) or info['init_image']}"
            print(line)
        print()
    timeline = results.get("timeline") or []
    if timeline:
        print("-" * 72)
        print(f"Recent changes (newest first, {min(len(timeline), timeline_limit)} of {len(timeline)})")
        print("-" * 72)
        for change in timeline[:timeline_limit]:
            print(f"  {change['time']}  {change['kind']}/{change['name']}  {change['what']}")
        print()


def _link_lines(hit):
    """Public links, then the internal ones (private file of Confluent support)"""
    return ([f"{l.get('title') or l['url']}: {l['url']}" for l in hit.get("links") or []] +
            [f"🔒 {l.get('title') or l['url']}: {l['url']}" for l in hit.get("internal_links") or []])


def print_runbooks(results):
    """Known CFK issues matched in the bundle, before the issues by category: what they mean and where to read more"""
    hits = results.get("runbooks") or []
    if not hits:
        return
    print("-" * 72)
    print(f"Known CFK issues ({len(hits)} matched, see the runbooks before digging into the code)")
    print("-" * 72)
    for hit in hits:
        example = hit.get("example") or {}
        where = example.get("file", "")
        if example.get("line_number"):
            where += f":{example['line_number']}"
        print(f"  {SEVERITY_GLYPH.get(hit['severity'], '[?   ]')} {hit['title']}  "
              f"({hit['issues']} issue(s), {hit['occurrences']} occurrence(s), e.g. {where})")
        print(f"         {hit['advice']}")
        for line in _link_lines(hit):
            print(f"         -> {line}")
    if any(h.get("internal_links") for h in hits):
        print("  🔒 internal links: for Confluent support only, never in a reply to the customer")
    print()


def print_text_report(results, top: int):
    summary = results["summary"]
    issues = results["issues"]

    coverage = results.get("coverage", {})

    print("=" * 72)
    print("CFK Bundle Analysis")
    print("=" * 72)
    print(f"Files analyzed:   {summary['files_analyzed']}  "
          f"({coverage.get('pods', 0)} pods, {coverage.get('custom_resources', 0)} CFK CRs, "
          f"{coverage.get('events', 0)} events, {coverage.get('log_files', 0)} log/text files "
          f"with {coverage.get('log_lines', 0)} lines, {coverage.get('skipped_files', 0)} skipped)")
    if coverage.get("skipped_copies"):
        print(f"Skipped copies:   {', '.join(coverage['skipped_copies'])} (a copy of the bundle inside the bundle, analyzed once)")
    if coverage.get("duplicate_events"):
        print(f"Duplicate events: {coverage['duplicate_events']} rows of kubectl get events also in the YAML events, counted once")
    if coverage.get("unparsable_files"):
        print(f"Unparsable files: {len(coverage['unparsable_files'])} "
              f"(e.g. {', '.join(coverage['unparsable_files'][:3])})")
    print(f"Analysis time:    {summary['analysis_time']:.2f}s")
    print(f"Total issues:     {summary['total_issues']}")
    print(f"  critical:       {summary['critical']}")
    print(f"  high:           {summary['high']}")
    print(f"  medium:         {summary['medium']}")
    print(f"  low:            {summary['low']}")
    by_component = component_counts(issues)
    if by_component:
        print("By component:     " + ", ".join(f"{c} {n}" for c, n in by_component))
    if summary.get("components"):
        print(f"Filtered on:      --component {' '.join(summary['components'])}")
    if results.get("redaction_summary"):
        r = results["redaction_summary"]
        print(f"Sanitized:        {r['secrets']} secrets, {r['ip_addresses']} IPs, {r['hostnames']} hostnames, "
              f"{r['emails']} emails, {r['ldap_dns']} LDAP DNs (best effort, review before sharing)")
    print()
    print_environment(results)
    config = results.get("configuration") or {}
    found = [f"{kind} {', '.join(sorted(crs))}" for kind, crs in (config.get("components") or {}).items() if crs]
    if found or config.get("connectors"):
        print(f"Configuration:    {'; '.join(found) or 'no Kafka / ZooKeeper / Schema Registry / Connect / Control Center CR'}; "
              f"{len(config.get('connectors') or {})} connector config(s) (in the HTML report and --json .configuration)")
        print()

    print_runbooks(results)

    if not issues:
        print("No issues detected in the scanned files.")
        print("Only ERROR/FATAL log records, uncaught exceptions, Warning events, pod and CFK CR status are checked.")
        return

    runbooks_by_name = {h["name"]: h["title"] for h in results.get("runbooks") or []}
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
            loc = f"[{issue.get('component', 'other')}"
            if issue.get("instance"):
                loc += f"/{issue['instance']}"
            loc += f"] {issue['file']}"
            if issue.get("line_number"):
                loc += f":{issue['line_number']}"
            if issue.get("count", 1) > 1:
                loc += f"  (x{issue['count']})"
            msg = issue["message"]
            # log records are cut (the context has the rest); findings on the config / versions are short sentences
            limit = 180 if issue.get("line_number") else 500
            if len(msg) > limit:
                msg = msg[:limit - 3] + "..."
            print(f"  {glyph} {loc}")
            print(f"         {msg}")
            affected = issue.get("affected") or []
            if len(affected) > 1 or (affected and issue.get("count", 1) > 1):
                shown = ", ".join(affected[:8]) + (f" (+{len(affected) - 8} more)" if len(affected) > 8 else "")
                print(f"           Affects {len(affected)} task(s): {shown}")
            for cause in issue.get("caused_by") or []:
                cause = cause if len(cause) <= 170 else cause[:167] + "..."
                print(f"           Caused by: {cause}")
            for name in issue.get("runbooks") or []:
                print(f"           📕 Known CFK issue: {runbooks_by_name.get(name, name)}")
            if issue.get("next_steps"):
                print("           Next steps:")
                for step in issue["next_steps"]:
                    print(f"             - {step}")
                for url in issue.get("docs") or []:
                    print(f"             Docs: {url}")

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
    print("- Raw ERROR digest of every log in the bundle: playground analyze logs -f <bundle>")
    print("- For JVM GC analysis on a specific component: playground analyze gc-logs")
    print()


def run(
    bundle_path: str,
    sanitize: bool,
    severity: Optional[str],
    top: int,
    as_json: bool,
    html_out: Optional[str] = None,
    include_warnings: bool = False,
    components: Optional[list] = None,
) -> int:
    with extracted_bundle(bundle_path) as bundle_dir:
        analyzer = CFKBundleAnalyzer(bundle_dir, include_warnings=include_warnings)
        # analyzer.analyze() prints decode/parse warnings via print() to stdout.
        # Send those to stderr so --json mode produces clean JSON on stdout.
        with redirect_stdout(sys.stderr):
            results = analyzer.analyze()

    coverage = results["coverage"]
    if results["summary"]["files_analyzed"] == 0:
        raise BundleError(
            f"No log, event or YAML file could be analyzed in {os.path.basename(bundle_path)} "
            f"({coverage['skipped_files']} files skipped). Is it a CFK support bundle?"
        )
    if not coverage["layout"] and coverage["pods"] == 0 and coverage["custom_resources"] == 0:
        print("warning: no cluster-resources/ or operator/ folder, no Pod nor CFK custom resource found: "
              "this does not look like a CFK support bundle (kubectl confluent support-bundle), "
              "only log patterns were checked.", file=sys.stderr)

    if sanitize:
        results = DataSanitizer().sanitize_results(results)

    if severity or components:
        results["issues"] = filter_by_component(filter_by_severity(results["issues"], severity), components)
        recount(results)
    if components:
        results["summary"]["components"] = components
    # after the sanitizer: it would redact the hostnames of the links
    results["runbooks"] = analyzer.runbooks.summarize(results["issues"])

    if html_out:
        rendered = html_report.render(results, bundle_label=os.path.basename(bundle_path))
        os.makedirs(os.path.dirname(os.path.abspath(html_out)), exist_ok=True)
        with open(html_out, "w", encoding="utf-8") as f:
            f.write(rendered)

    if as_json:
        for issue in results["issues"]:
            issue["recommendation"] = recommendations.for_category(issue["category"])
        # type: playground analyze logs emits this JSON for a CFK support bundle, and its own ("logs") otherwise
        json.dump(dict({"type": "cfk-bundle"}, **results), sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
    else:
        # the text digest is printed with the HTML report too: it is what a terminal / an agent reads
        print_text_report(results, top=top)
        print_verdict(results)

    return 0


def print_verdict(results):
    s = results["summary"]
    if s.get("components"):
        print(f"Component filter: {', '.join(s['components'])}")
    if s["critical"]:
        print(f"CRITICAL: {s['critical']} critical and {s['high']} high-severity issues, act on the recommendations above.")
    elif s["high"]:
        print(f"WARNING: {s['high']} high-severity issues, review the recommendations above.")
    elif s["total_issues"]:
        print(f"OK: no critical or high-severity issues ({s['total_issues']} medium/low).")
    else:
        print("OK: no issues found.")


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
    p.add_argument("--component", action="append", choices=COMPONENTS,
                   help="Only keep the issues of this component (repeatable)")
    p.add_argument("--include-warnings", action="store_true", help="Also report WARN log records that match no known category")
    args = p.parse_args()

    try:
        return run(
            bundle_path=args.bundle,
            sanitize=not args.no_sanitize,
            severity=args.severity,
            top=max(1, args.top),
            as_json=args.json,
            html_out=args.html_out,
            include_warnings=args.include_warnings,
            components=args.component,
        )
    except (FileNotFoundError, ValueError, BundleError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 64


if __name__ == "__main__":
    sys.exit(main())
