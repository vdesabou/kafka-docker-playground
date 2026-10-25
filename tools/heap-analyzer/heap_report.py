#!/usr/bin/env python3
"""
HTML report and JSON of an Eclipse MAT analysis, written by playground analyze heap-dump after analyze-heap.sh:
the heap overview, the leak suspects of MAT in plain words, what retains the heap (dominator tree by class), the
growth between two dumps (--compare), and Kafka-aware hints (producer buffers, consumer fetch buffers, records held
by the tasks, storage sink writers, CDC queues, schema caches).

Reads the files of the output directory with the parsers of digest.py (same folder):
  queries/overview.txt, queries/dominator_by_class.txt, Leak_Suspects/index.html
  queries/histogram.txt, queries/compare_histogram.txt, queries/compare_overview.txt  with --compare
"""

import argparse
import json
import os
import re
import sys
from typing import List, Optional, Tuple

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "report-common"))
import digest  # noqa: E402
import report_html as rh  # noqa: E402

TOP = 20

# what retains the heap in a Kafka / Connect JVM: (regex on the class name, title, what to do)
KAFKA_HINTS = [
    (r"org\.apache\.kafka\.clients\.producer\.internals\.(RecordAccumulator|ProducerBatch|BufferPool)",
     "📤 Producer buffers",
     "each producer holds up to buffer.memory (32 MB by default): one per source task, plus the dead letter queue and "
     "reporter producers. Lower buffer.memory / batch.size (producer.override.* on the connector), or the number of tasks"),
    (r"org\.apache\.kafka\.clients\.consumer\.internals\.(CompletedFetch|FetchBuffer|Fetcher|FetchCollector|ShareCompletedFetch)",
     "📥 Consumer fetch buffers",
     "a consumer buffers up to fetch.max.bytes (50 MB) and max.partition.fetch.bytes (1 MB) per partition: many partitions "
     "per sink task multiply it. Lower them with consumer.override.* on the connector"),
    (r"org\.apache\.kafka\.connect\.(sink\.SinkRecord|source\.SourceRecord|connector\.ConnectRecord|runtime\.WorkerSinkTask|runtime\.InternalSinkRecord)",
     "📦 Records held by the tasks",
     "the connector keeps records in memory before writing them: lower consumer.override.max.poll.records, and the batch "
     "or flush size of the connector"),
    (r"io\.confluent\.connect\.(s3|gcs|azure|hdfs\d?|storage)\.",
     "🪣 Storage sink writers",
     "one open file / multipart upload per topic partition: s3.part.size (25 MB...) x partitions per task. Lower the part "
     "size, flush.size or rotate.interval.ms, or spread the partitions over more tasks"),
    (r"io\.debezium\.|oracle\.streams\.|io\.confluent\.connect\.oracle\.|LogMiner|ChangeEventQueue",
     "🗃️ CDC queues and transactions",
     "the change event queue (max.queue.size, max.batch.size) or a large open transaction buffered by the connector"),
    (r"io\.confluent\.kafka\.schemaregistry\.client\.|org\.apache\.avro\.Schema|io\.confluent\.kafka\.schemaregistry\.",
     "🧾 Schema caches",
     "many distinct schemas (or subjects) cached by the converters or serializers: check the subject name strategy and "
     "max.schemas.per.subject"),
    (r"org\.apache\.kafka\.connect\.runtime\.isolation\.(PluginClassLoader|DelegatingClassLoader)",
     "🧩 Plugin class loaders",
     "every plugin of plugin.path is loaded in its own class loader: keep only the plugins you use"),
]


def load(out: str, compare: bool) -> dict:
    overview = digest.parse_overview(digest.read(os.path.join(out, "queries", "overview.txt")))
    suspects = digest.leak_suspects(digest.read(os.path.join(out, "Leak_Suspects", "index.html")))
    dominators = digest.parse_table(digest.read(os.path.join(out, "queries", "dominator_by_class.txt")))
    res = {"overview": overview, "suspects": [{"title": t, "text": b} for t, b in (suspects or [])],
           "suspects_available": suspects is not None,
           "dominators": [{"class": r.get("Class Name", ""), "objects": digest.number(r.get("Objects", 0)),
                           "retained": digest.number(r.get("Retained Heap", 0)), "percentage": pct(r.get("Percentage", ""))}
                          for r in dominators],
           "growth": None,
           "mat_reports": [d for d in ("Leak_Suspects", "System_Overview", "Top_Components")
                           if os.path.isfile(os.path.join(out, d, "index.html"))]}
    if compare:
        res["growth"] = growth(out)
    return res


def pct(v) -> Optional[float]:
    try:
        return float(str(v).replace("%", "").replace(",", "."))
    except ValueError:
        return None


def growth(out: str) -> Optional[dict]:
    before = {r["Class Name"]: r for r in digest.parse_table(digest.read(os.path.join(out, "queries", "histogram.txt")))}
    after = {r["Class Name"]: r for r in digest.parse_table(digest.read(os.path.join(out, "queries", "compare_histogram.txt")))}
    if not before or not after:
        return None
    ov_after = digest.parse_overview(digest.read(os.path.join(out, "queries", "compare_overview.txt")))
    rows = []
    for name in set(before) | set(after):
        b, a = before.get(name, {}), after.get(name, {})
        d_obj = digest.number(a.get("Objects", 0)) - digest.number(b.get("Objects", 0))
        d_size = digest.number(a.get("Shallow Heap", 0)) - digest.number(b.get("Shallow Heap", 0))
        # same noise filter as the text digest: a few lambdas / method handles created between the two dumps
        if d_size >= 10 * 1024 or d_obj >= 100:
            rows.append({"class": name, "objects_before": digest.number(b.get("Objects", 0)),
                         "objects_after": digest.number(a.get("Objects", 0)), "delta_objects": d_obj, "delta_shallow": d_size})
    # the class name breaks the ties: the order of a set changes from one run to the next
    rows.sort(key=lambda r: (-r["delta_shallow"], r["class"]))
    return {"overview_after": ov_after, "classes": rows}


def kafka_hints(res: dict) -> List[dict]:
    out = []
    classes = [(d["class"], d["percentage"] or 0, d["retained"]) for d in res["dominators"][:40]]
    grown = [g["class"] for g in (res["growth"] or {}).get("classes", [])[:20]]
    for pattern, title, advice in KAFKA_HINTS:
        rx = re.compile(pattern)
        hits = [(c, p, r) for c, p, r in classes if rx.search(c)]
        share = sum(p for _, p, _ in hits)
        growing = [c for c in grown if rx.search(c)]
        if share >= 5 or growing:
            sev = "HIGH" if share >= 25 or growing else "MEDIUM"
            what = f"{share:.0f}% of the heap" if share else "growing between the two dumps"
            names = ", ".join(c.split(".")[-1] for c, _, _ in hits[:3]) or ", ".join(c.split(".")[-1] for c in growing[:3])
            out.append({"severity": sev, "text": f"{title} retain {what} ({names}): {advice}"})
    byte_arrays = next((d for d in res["dominators"] if d["class"] == "byte[]"), None)
    if byte_arrays and (byte_arrays["percentage"] or 0) >= 30 and not out:
        out.append({"severity": "MEDIUM", "text": f"🧱 byte[] retain {byte_arrays['percentage']:.0f}% of the heap on their own: payloads "
                                                  "(records, batches, files) buffered somewhere. Open the dominator tree in MAT to see who holds them"})
    return out


def findings(res: dict) -> List[dict]:
    f = []
    for s in res["suspects"]:
        sev = "HIGH" if s["title"].startswith("Problem Suspect") else "INFO"
        f.append({"severity": sev, "text": f"🕵️ {s['title']}: {s['text'][:500]}{'…' if len(s['text']) > 500 else ''}"})
    if res["suspects_available"] and not res["suspects"]:
        f.append({"severity": "OK", "text": "✅ MAT found no leak suspect: no single object or class accumulates a large part of the heap"})
    f.extend(kafka_hints(res))
    g = res["growth"]
    if g and g["classes"]:
        top = g["classes"][0]
        f.append({"severity": "HIGH", "text": f"📈 {top['class']} grew the most between the two dumps: {top['delta_objects']:+,} objects, "
                                              f"{rh.fmt_bytes(top['delta_shallow'])} more shallow heap. A class that keeps growing across "
                                              "dumps taken under the same load is the leak candidate: open its paths to GC roots in MAT"})
    elif g is not None:
        f.append({"severity": "OK", "text": "✅ No class grew by more than 100 objects or 10 KB between the two dumps"})
    return rh.sort_findings(f)


def verdict(res: dict, items: List[dict]) -> Tuple[str, str]:
    high = [x for x in items if x["severity"] in ("CRITICAL", "HIGH")]
    used = res["overview"].get("Used heap dump", "?")
    if high:
        return "danger", f"🚨 {len(high)} high finding(s) in {used} of heap: start with {high[0]['text'].split(':')[0]}."
    if any(x["severity"] == "MEDIUM" for x in items):
        return "warn", f"⚠️ {used} of heap, something to look at, nothing high."
    return "ok", f"✅ {used} of heap, no leak suspect."


def html_report(res: dict, heap_file: str, compare_file: str) -> str:
    ov = res["overview"]
    items = findings(res)
    cards = [rh.kpi("🧠 Used heap", ov.get("Used heap dump", "?"), ov.get("JVM version", "")[:40]),
             rh.kpi("🔢 Objects", ov.get("Number of objects", "?"), "live objects"),
             rh.kpi("🏷️ Classes", ov.get("Number of classes", "?"), f"{ov.get('Number of class loaders', '?')} class loaders"),
             rh.kpi("🌱 GC roots", ov.get("Number of GC roots", "?"), "")]
    if res["dominators"]:
        top = res["dominators"][0]
        cards.append(rh.kpi("🏋️ Biggest retainer", f"{top['percentage'] or 0:.0f}%", top["class"][-48:],
                            "danger" if (top["percentage"] or 0) >= 50 else "warn" if (top["percentage"] or 0) >= 25 else "ok"))
    cards.append(rh.kpi("🕵️ Leak suspects", len([s for s in res["suspects"] if s["title"].startswith("Problem")]), "from Eclipse MAT",
                        "danger" if any(s["title"].startswith("Problem") for s in res["suspects"]) else "ok"))
    g = res["growth"]
    if g:
        cards.append(rh.kpi("📈 Growing classes", len(g["classes"]),
                            f"{ov.get('Used heap dump', '?')} → {g['overview_after'].get('Used heap dump', '?')}", "warn" if g["classes"] else "ok"))
    bars = [(d["class"].split(".")[-1] or d["class"], d["retained"], f"{d['class']}: {rh.fmt_bytes(d['retained'])} ({d['percentage']}%)")
            for d in res["dominators"][:15]]
    gbars = [(x["class"].split(".")[-1], x["delta_shallow"], f"{x['class']}: {x['delta_objects']:+,} objects") for x in (g or {}).get("classes", [])[:12]]
    body = [rh.verdict_html(*verdict(res, items)), rh.kpis_html(cards), rh.findings_html(items),
            rh.charts_grid([("🏋️ Retained heap by class (dominator tree)", rh.svg_hbars(bars, rh.fmt_bytes)),
                            ("📈 Growth between the two dumps (shallow heap)", rh.svg_hbars(gbars, rh.fmt_bytes))])]
    if res["suspects"]:
        body.append(rh.card("🕵️ Leak suspects (Eclipse MAT)", "".join(
            f"<details open><summary><b>{rh.e(s['title'])}</b></summary><p class='rec-text' style='margin:6px 0 10px'>{rh.e(s['text'])}</p></details>"
            for s in res["suspects"])))
    if res["dominators"]:
        rows = [(f"<span class='mono'>{rh.e(d['class'])}</span>", f"{d['objects']:,}", rh.e(rh.fmt_bytes(d["retained"])),
                 f"{d['percentage']}%" if d["percentage"] is not None else "") for d in res["dominators"][:TOP]]
        body.append(rh.card(f"🏋️ Top {TOP} retained heap by class",
                            rh.table(["Class", "Objects", "Retained heap", "% of heap"], rows, num=(1, 2, 3))
                            + "<p class='legend' style='margin-top:10px'>Retained heap: the memory freed if all the objects of the class were collected.</p>"))
    if g and g["classes"]:
        rows = [(f"<span class='mono'>{rh.e(x['class'])}</span>", f"{x['objects_before']:,}", f"{x['objects_after']:,}",
                 f"{x['delta_objects']:+,}", rh.e(rh.fmt_bytes(x["delta_shallow"]))) for x in g["classes"][:TOP]]
        body.append(rh.card(f"📈 Growth from {rh.e(heap_file)} to {rh.e(compare_file)}",
                            rh.table(["Class", "Objects before", "Objects after", "Δ objects", "Δ shallow heap"], rows, num=(1, 2, 3, 4))))
    links = " · ".join(f"<a href='{d}/index.html'>{d.replace('_', ' ')}</a>" for d in res["mat_reports"])
    body.append(rh.card("🔎 Going further", (f"<p class='rec-text'>Reports of Eclipse MAT, in the same folder: {links}</p>" if links else "")
                        + "<p class='rec-text' style='margin-top:6px'>For the paths to GC roots, OQL or a second look, open the "
                          ".hprof in the Eclipse MAT GUI (https://eclipse.dev/mat/).</p>"))
    meta = [f"&#128196; {rh.e(heap_file)}" + (f" → {rh.e(compare_file)}" if compare_file else "")]
    if ov.get("Date"):
        meta.append(f"🕐 taken {rh.e(ov.get('Date', ''))} {rh.e(ov.get('Time', ''))}")
    return rh.page(f"Heap dump report — {heap_file}", "🔬 Heap Dump Analysis", meta, "".join(body),
                   "🛠️ Generated by playground analyze heap-dump from the Eclipse MAT analysis (self-contained, no external resource).")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--output-dir", required=True, help="output directory of analyze-heap.sh")
    ap.add_argument("--heap-file", required=True, help="name of the heap dump, for the report")
    ap.add_argument("--compare-file", default="", help="name of the second heap dump (--compare)")
    ap.add_argument("--json", action="store_true", help="print the analysis as JSON")
    ap.add_argument("--html-out", metavar="PATH", help="write a self-contained HTML report")
    args = ap.parse_args()
    res = load(args.output_dir, bool(args.compare_file))
    if not res["overview"] and not res["dominators"]:
        print(f"❌ no MAT result in {args.output_dir} (see mat.log)", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(dict(res, heap_file=args.heap_file, compare_file=args.compare_file or None, findings=findings(res)),
                         indent=2, ensure_ascii=False))
    if args.html_out:
        with open(args.html_out, "w", encoding="utf-8") as fh:
            fh.write(html_report(res, args.heap_file, args.compare_file))
    return 0


if __name__ == "__main__":
    sys.exit(main())
