#!/usr/bin/env python3
"""
Text digest of an Eclipse MAT analysis, printed by playground analyze heap-dump.

Reads what analyze-heap.sh left in the output directory:
  queries/overview.txt            heap_dump_overview query
  queries/dominator_by_class.txt  dominator_tree -groupBy BY_CLASS query (retained sizes)
  Leak_Suspects/index.html        leak suspects report
  queries/histogram.txt, queries/compare_histogram.txt, queries/compare_overview.txt  with --compare
"""

import argparse
import html
import os
import re
import sys

TOP = 15


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def parse_table(text):
    """Parse a MAT txt table ('col | col | ...') into a list of dicts"""
    if not text:
        return []
    lines = text.splitlines()
    header = None
    rows = []
    for line in lines:
        if set(line.strip()) <= {"-"}:
            continue
        cells = [c.strip() for c in line.split("|")]
        if header is None:
            header = cells
            continue
        if len(cells) != len(header) or cells[0].startswith("Total:"):
            continue
        rows.append(dict(zip(header, cells)))
    return rows


def number(value):
    try:
        return int(str(value).replace(",", ""))
    except ValueError:
        return 0


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1024 or unit == "GB":
            return f"{n:,.0f} {unit}" if unit == "B" else f"{n:,.1f} {unit}"
        n /= 1024.0


def parse_overview(text):
    """heap_dump_overview: 'Property | Value' rows, the JVM version spans several lines"""
    props = {}
    if not text:
        return props
    for line in text.splitlines():
        # continuation lines of the multi-line JVM version have no '|' and are ignored
        if "|" in line:
            k, _, v = line.partition("|")
            props[k.strip()] = v.strip()
    return props


def leak_suspects(index_html):
    """Problem Suspect paragraphs of the MAT leak suspects report, as plain text"""
    if not index_html:
        return None
    text = re.sub(r"<script.*?</script>|<style.*?</style>", " ", index_html, flags=re.S)
    text = html.unescape(re.sub(r"<[^>]+>", " ", text))
    text = re.sub(r"\s+", " ", text)
    suspects = []
    for m in re.finditer(r"(Problem Suspect \d+|Hint \d+)\s+(.*?)(?=\s+Keywords\s|\s+Details\s+»|\s+Problem Suspect \d+|\s+Hint \d+|\s+Table Of Contents|$)", text):
        suspects.append((m.group(1), m.group(2).strip()))
    return suspects


def print_table(rows, columns, limit=TOP):
    widths = [max(len(c), *(len(r.get(c, "")) for r in rows[:limit])) for c in columns]
    widths[0] = min(widths[0], 90)
    print("  " + "  ".join(c.ljust(w) if i == 0 else c.rjust(w) for i, (c, w) in enumerate(zip(columns, widths))))
    for r in rows[:limit]:
        cells = []
        for i, (c, w) in enumerate(zip(columns, widths)):
            v = r.get(c, "")
            if i == 0:
                v = v if len(v) <= w else v[: w - 1] + "…"
                cells.append(v.ljust(w))
            else:
                cells.append(v.rjust(w))
        print("  " + "  ".join(cells))


def compare(output_dir, heap_file, compare_file):
    before = {r["Class Name"]: r for r in parse_table(read(os.path.join(output_dir, "queries", "histogram.txt")))}
    after = {r["Class Name"]: r for r in parse_table(read(os.path.join(output_dir, "queries", "compare_histogram.txt")))}
    if not before or not after:
        print("⚠️  Comparison skipped: a histogram is missing (see mat.log)")
        return
    ov_before = parse_overview(read(os.path.join(output_dir, "queries", "overview.txt")))
    ov_after = parse_overview(read(os.path.join(output_dir, "queries", "compare_overview.txt")))

    print(f"📈 Growth from {heap_file} to {compare_file}")
    print(f"  used heap: {ov_before.get('Used heap dump', '?')} -> {ov_after.get('Used heap dump', '?')}, "
          f"objects: {ov_before.get('Number of objects', '?')} -> {ov_after.get('Number of objects', '?')}")
    rows = []
    for name in set(before) | set(after):
        b, a = before.get(name, {}), after.get(name, {})
        d_obj = number(a.get("Objects", 0)) - number(b.get("Objects", 0))
        d_size = number(a.get("Shallow Heap", 0)) - number(b.get("Shallow Heap", 0))
        # ignore noise: a few lambdas / method handles created between the two dumps
        if d_size >= 10 * 1024 or d_obj >= 100:
            rows.append({
                "Class Name": name,
                "Objects before": b.get("Objects", "0"),
                "Objects after": a.get("Objects", "0"),
                "Δ objects": f"{d_obj:+,}",
                "Δ shallow heap": f"{d_size:+,}",
                "_d_size": d_size,
            })
    rows.sort(key=lambda r: r["_d_size"], reverse=True)
    if not rows:
        print("  no class grew by more than 100 objects or 10 KB between the two dumps")
    else:
        print_table(rows, ["Class Name", "Objects before", "Objects after", "Δ objects", "Δ shallow heap"])
        print("  A class that keeps growing across several dumps taken under the same load is the leak candidate:")
        print("  open its paths to GC roots in the Leak_Suspects report or in the MAT GUI.")
    print()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output-dir", required=True)
    p.add_argument("--heap-file", required=True)
    p.add_argument("--compare-file")
    args = p.parse_args()
    out = args.output_dir

    overview = parse_overview(read(os.path.join(out, "queries", "overview.txt")))
    jvm = overview.get("JVM version", "")
    print("=" * 100)
    print(f"🔬 Heap dump {args.heap_file}")
    print("=" * 100)
    print(f"  used heap: {overview.get('Used heap dump', '?')}, objects: {overview.get('Number of objects', '?')}, "
          f"classes: {overview.get('Number of classes', '?')}, class loaders: {overview.get('Number of class loaders', '?')}, "
          f"GC roots: {overview.get('Number of GC roots', '?')}")
    if jvm:
        print(f"  JVM: {jvm}, taken {overview.get('Date', '?')} {overview.get('Time', '')}".rstrip())
    print()

    suspects = leak_suspects(read(os.path.join(out, "Leak_Suspects", "index.html")))
    if suspects is not None:
        print("🕵️  Leak suspects (Eclipse MAT)")
        if not suspects:
            print("  MAT found no leak suspect: no single object or class accumulates a large part of the heap.")
        for title, body in suspects:
            print(f"  ▶ {title}")
            print("    " + body)
        print()

    dominators = parse_table(read(os.path.join(out, "queries", "dominator_by_class.txt")))
    if dominators:
        print(f"🏋️  Top {TOP} retained heap by class (dominator tree: memory freed if these objects were collected)")
        print_table(dominators, ["Class Name", "Objects", "Retained Heap", "Percentage"])
        print()
    else:
        print("⚠️  Retained sizes not available (see mat.log)")
        print()

    if args.compare_file:
        compare(out, args.heap_file, args.compare_file)

    reports = [d for d in ("Leak_Suspects", "System_Overview", "Top_Components") if os.path.isfile(os.path.join(out, d, "index.html"))]
    if reports:
        print("📊 HTML reports: " + ", ".join(f"{d}/index.html" for d in reports))
    print("🔎 For paths to GC roots, OQL or a second look, open the .hprof in the Eclipse MAT GUI: https://eclipse.dev/mat/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
