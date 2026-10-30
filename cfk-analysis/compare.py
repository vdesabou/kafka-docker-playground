#!/usr/bin/env python3
"""
Comparison of CFK support bundles, from the JSON of their analysis (analyzer_cli.py --json / --json-out).

playground analyze logs runs it when it finds several CFK bundles: they are sorted by the time they were collected
(their newest timestamp) and each one is compared with the previous one:

- same cluster or not (the CRs they have in common)
- versions: Kubernetes, CFK operator, image of each component
- the changes of the CRs between the two collections (timeline of the newer bundle after the older one was collected)
- issues fixed, new and still there (with their occurrences), known CFK issues, KRaft migration phase
- a verdict

Issues are matched on category, component, instance and message, with the digits, timestamps and placeholders of the
sanitizer (<HOST-1>, <IP-2>… numbered per bundle) folded.

Usage: compare.py <analysis.json> <analysis.json> [...] [--json] [--html-out FILE]
"""

import argparse
import json
import os
import re
import sys
from typing import Dict, List

sys.dont_write_bytecode = True
for _path in (os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "report-common"), "/tmp/report-common"):
    if os.path.isfile(os.path.join(_path, "report_html.py")):
        sys.path.insert(0, _path)
        break
import report_html as rh  # noqa: E402

SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3}
SEVERITY_EMOJI = {"critical": "🔴", "high": "🟠", "medium": "🟡", "low": "🟢"}
_PLACEHOLDER_RE = re.compile(r"<([A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*)-\d+>")
_TS_RE = re.compile(r"\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d(?:[.,]\d+)?Z?|\b\d\d:\d\d:\d\d(?:[.,]\d+)?")


def issue_key(issue: Dict) -> tuple:
    message = _PLACEHOLDER_RE.sub(r"<\1>", issue.get("message", ""))
    message = _TS_RE.sub("<TS>", message)
    message = re.sub(r"\d+", "N", message)
    message = re.sub(r"\s+", " ", message).strip()[:160]
    return issue.get("category", ""), issue.get("component", ""), issue.get("instance", ""), message


def _label(bundle: Dict, index: int) -> str:
    """Short name of a bundle: its folder in the archive, or the archive name (playground labels are path:folder)"""
    label = str(bundle.get("label") or f"bundle {index + 1}").rstrip("/")
    last = label.rsplit("/", 1)[-1]
    return last.rsplit(":", 1)[-1] or last


def _short(issue: Dict, limit: int = 220) -> str:
    message = issue.get("message", "")
    return message if len(message) <= limit else message[:limit - 3] + "..."


def compare_pair(older: Dict, newer: Dict) -> Dict:
    env_a, env_b = older.get("environment") or {}, newer.get("environment") or {}
    comp_a, comp_b = env_a.get("components") or {}, env_b.get("components") or {}
    common = sorted(set(comp_a) & set(comp_b))
    ns_a, ns_b = set(env_a.get("namespaces") or []), set(env_b.get("namespaces") or [])
    other_namespace = bool(ns_a and ns_b and not ns_a & ns_b)
    versions = []
    for key, title in (("kubernetes_version", "Kubernetes"), ("cfk_version", "CFK operator")):
        if env_a.get(key) and env_b.get(key) and env_a[key] != env_b[key]:
            versions.append({"what": title, "before": env_a[key], "after": env_b[key]})
    for name in sorted(set(comp_a) | set(comp_b)):
        before, after = (comp_a.get(name) or {}).get("image"), (comp_b.get(name) or {}).get("image")
        if before != after:
            versions.append({"what": name, "before": before or "(not in the bundle)", "after": after or "(not in the bundle)"})

    collected = older.get("collected") or ""
    changes = [c for c in newer.get("timeline") or []
               if c.get("kind") != "Pod" and str(c.get("time", "")).replace("T", " ").replace("Z", "")[:19] > collected]

    issues_a = {issue_key(i): i for i in older.get("issues") or []}
    issues_b = {issue_key(i): i for i in newer.get("issues") or []}
    order = lambda i: (SEVERITY_ORDER.get(i.get("severity"), 9), -i.get("count", 1))
    fixed = sorted((issues_a[k] for k in issues_a.keys() - issues_b.keys()), key=order)
    new = sorted((issues_b[k] for k in issues_b.keys() - issues_a.keys()), key=order)
    still = sorted(({"before": issues_a[k].get("count", 1), "after": issues_b[k].get("count", 1), **issues_b[k]}
                    for k in issues_a.keys() & issues_b.keys()), key=order)

    runbooks_a = {r["title"] for r in older.get("runbooks") or []}
    runbooks_b = {r["title"] for r in newer.get("runbooks") or []}
    migration = [(i.get("phase"), i.get("sub_phase")) for b in (older, newer)
                 for i in b.get("issues") or [] if i.get("category") == "KRaft Migration" and i.get("phase")]

    serious = lambda items: [i for i in items if i.get("severity") in ("critical", "high")]
    if not common or other_namespace:
        verdict = ("different clusters: " + (f"namespace {', '.join(sorted(ns_a))} vs {', '.join(sorted(ns_b))}"
                                             if other_namespace else "no CR in common") + ", the issues are not comparable")
    elif serious(new) and serious(fixed):
        verdict = (f"changed: {len(serious(fixed))} critical / high issue(s) gone, {len(serious(new))} new: the problem "
                   "moved, look at the changes between the two bundles")
    elif serious(new):
        verdict = f"worse: {len(serious(new))} new critical / high issue(s)"
    elif serious(fixed):
        verdict = f"better: {len(serious(fixed))} critical / high issue(s) gone, none new"
    elif serious(still):
        verdict = f"no change: the {len(serious(still))} critical / high issue(s) are still there"
    else:
        verdict = "no critical / high issue in either bundle"
    return {
        "before": older.get("label"), "after": newer.get("label"),
        "collected_before": older.get("collected"), "collected_after": newer.get("collected"),
        "same_cluster": bool(common) and not other_namespace, "common_components": common,
        "namespaces_before": sorted(ns_a), "namespaces_after": sorted(ns_b),
        "summary_before": {k: (older.get("summary") or {}).get(k, 0) for k in ("total_issues", "critical", "high", "medium", "low")},
        "summary_after": {k: (newer.get("summary") or {}).get(k, 0) for k in ("total_issues", "critical", "high", "medium", "low")},
        "versions": versions, "changes_between": changes,
        "fixed": fixed, "new": new, "still": still,
        "known_issues_gone": sorted(runbooks_a - runbooks_b), "known_issues_new": sorted(runbooks_b - runbooks_a),
        "kraft_migration": [f"{p}/{s}" for p, s in migration],
        "verdict": verdict,
    }


def compare(bundles: List[Dict]) -> List[Dict]:
    for index, bundle in enumerate(bundles):
        bundle["label"] = _label(bundle, index)
    ordered = sorted(bundles, key=lambda b: b.get("collected") or "")
    return [compare_pair(a, b) for a, b in zip(ordered, ordered[1:])]


def print_text(pairs: List[Dict], top: int = 8):
    for pair in pairs:
        print("=" * 72)
        print(f"🔁 Comparison: {pair['before']}  ->  {pair['after']}")
        print(f"   collected about {pair['collected_before']} and {pair['collected_after']}")
        print("=" * 72)
        print(f"Verdict:          {pair['verdict']}")
        sb, sa = pair["summary_before"], pair["summary_after"]
        print(f"Issues:           {sb['total_issues']} -> {sa['total_issues']}  (critical {sb['critical']} -> {sa['critical']}, "
              f"high {sb['high']} -> {sa['high']})")
        if not pair["same_cluster"]:
            print("⚠️  not the same cluster / namespace: the differences below are not changes of one cluster")
        for v in pair["versions"][:top]:
            print(f"Version:          {v['what']}: {v['before']} -> {v['after']}")
        if pair["kraft_migration"]:
            print(f"KRaft migration:  {' -> '.join(pair['kraft_migration'])}")
        for title in pair["known_issues_gone"]:
            print(f"📕 gone:          {title}")
        for title in pair["known_issues_new"]:
            print(f"📕 new:           {title}")
        if pair["changes_between"]:
            print(f"\nChanges between the two bundles ({len(pair['changes_between'])}):")
            for c in pair["changes_between"][:top]:
                print(f"  {c['time']}  {c['kind']}/{c['name']}  {c['what']}")
        for title, items in (("✅ Fixed (in the older bundle only)", pair["fixed"]),
                             ("🆕 New (in the newer bundle only)", pair["new"])):
            if items:
                print(f"\n{title}: {len(items)}")
                for i in items[:top]:
                    print(f"  [{i.get('severity', '?'):<8}] [{i.get('category')}] {_short(i, 160)}")
                if len(items) > top:
                    print(f"  ... and {len(items) - top} more (HTML report, --json .comparison)")
        if pair["still"]:
            print(f"\n⏳ Still there: {len(pair['still'])}")
            for i in pair["still"][:top]:
                print(f"  [{i.get('severity', '?'):<8}] x{i['before']} -> x{i['after']}  [{i.get('category')}] {_short(i, 140)}")
        print()


def render_html(pairs: List[Dict]) -> str:
    body = []
    for pair in pairs:
        sb, sa = pair["summary_before"], pair["summary_after"]
        cls = "danger" if pair["verdict"].startswith(("worse", "changed", "different")) else \
            "ok" if pair["verdict"].startswith(("better", "no critical")) else "warn"
        body.append(rh.verdict_html(cls, f"🔁 {pair['before']} → {pair['after']}: {pair['verdict']}"))
        body.append(rh.kpis_html([
            rh.kpi("Issues", f"{sb['total_issues']} → {sa['total_issues']}", "before → after"),
            rh.kpi("Critical / high", f"{sb['critical'] + sb['high']} → {sa['critical'] + sa['high']}", "before → after"),
            rh.kpi("Fixed", len(pair["fixed"]), "issues gone"),
            rh.kpi("New", len(pair["new"]), "issues"),
        ]))
        facts = [["Collected (about)", rh.e(pair["collected_before"]), rh.e(pair["collected_after"])]]
        facts += [[rh.e(v["what"]), f"<code>{rh.e(v['before'])}</code>", f"<code>{rh.e(v['after'])}</code>"] for v in pair["versions"]]
        if pair["kraft_migration"]:
            facts.append(["KRaft migration", rh.e(pair["kraft_migration"][0]), rh.e(pair["kraft_migration"][-1])])
        body.append(rh.card("🧭 Before / after", rh.table(["", rh.e(pair["before"]), rh.e(pair["after"])], facts)))
        if pair["known_issues_gone"] or pair["known_issues_new"]:
            rows = [["✅ gone", rh.e(t)] for t in pair["known_issues_gone"]] + [["🆕 new", rh.e(t)] for t in pair["known_issues_new"]]
            body.append(rh.card("📕 Known CFK issues", rh.table(["", "Known issue"], rows)))
        if pair["changes_between"]:
            rows = [[rh.e(c["time"]), rh.e(f"{c['kind']}/{c['name']}"), rh.e(c["what"])] for c in pair["changes_between"]]
            body.append(rh.card(f"🕒 Changes between the two bundles ({len(rows)})", rh.table(["Time", "Object", "Change"], rows)))
        for title, items in (("✅ Fixed: in the older bundle only", pair["fixed"]), ("🆕 New: in the newer bundle only", pair["new"])):
            if items:
                rows = [[f"{SEVERITY_EMOJI.get(i.get('severity'), '')} {rh.e(i.get('severity'))}", rh.e(i.get("category")),
                         f"<span class='mono'>{rh.e(_short(i, 400))}</span>"] for i in items]
                body.append(rh.card(f"{title} ({len(items)})", rh.table(["Severity", "Category", "Issue"], rows)))
        if pair["still"]:
            rows = [[f"{SEVERITY_EMOJI.get(i.get('severity'), '')} {rh.e(i.get('severity'))}", f"×{i['before']} → ×{i['after']}",
                     rh.e(i.get("category")), f"<span class='mono'>{rh.e(_short(i, 400))}</span>"] for i in pair["still"]]
            body.append(rh.card(f"⏳ Still there ({len(rows)})", rh.table(["Severity", "Occurrences", "Category", "Issue"], rows)))
    meta = [rh.e(f"{len(pairs) + 1} CFK support bundles, each compared with the previous one (sorted by collection time)")]
    return rh.page("CFK bundle comparison", "🔁 CFK bundle comparison", meta, "".join(body),
                   "Generated by <strong>playground analyze logs</strong> · sanitized like the analysis of each bundle")


def main() -> int:
    p = argparse.ArgumentParser(prog="compare.py", description="Compare the analyses of CFK support bundles")
    p.add_argument("analyses", nargs="+", help="JSON of analyzer_cli.py --json / --json-out, one per bundle")
    p.add_argument("--json", action="store_true", help="Print the comparison as JSON")
    p.add_argument("--html-out", help="Write the HTML report to this file")
    args = p.parse_args()
    bundles = []
    for path in args.analyses:
        with open(path, encoding="utf-8") as f:
            bundles.append(json.load(f))
    if len(bundles) < 2:
        print("Error: at least two analyses are needed", file=sys.stderr)
        return 64
    pairs = compare(bundles)
    if args.html_out:
        with open(args.html_out, "w", encoding="utf-8") as f:
            f.write(render_html(pairs))
    if args.json:
        json.dump(pairs, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
    else:
        print_text(pairs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
