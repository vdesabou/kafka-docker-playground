#!/usr/bin/env python3
"""
HTML report of playground connector diff: the keys of a connector config side by side with another config (a
customer's file, another connector, or the defaults of the plugin), with the documentation and default value of each
key from the configuration reference of the connector (config-<class>.txt), and what the important differences mean.

Inputs, written by scripts/cli/src/commands/connector/diff.sh:
  --diff        diff.json: [{key, status, a, b}], status among same, different, only_a, only_b, masked
                (with --defaults: same, different, required, no_default, masked)
  --reference   config-<class>.txt of the connector (optional): documentation, type, default of each key
"""

import argparse
import json
import os
import re
import sys
from typing import Dict, List, Optional, Tuple

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
import report_html as rh  # noqa: E402

# keys whose difference changes the behaviour a lot: (regex on the key, severity, what it means)
KEY_HINTS = [
    (r"^(key|value|header)\.converter$", "HIGH", "🔀 another converter: the records are read (sink) or written (source) in another format"),
    (r"^(key|value)\.converter\.", "MEDIUM", "🔀 another converter setting (schema registry url, schemas.enable, subject strategy...)"),
    (r"^connector\.class$", "CRITICAL", "🧩 another connector class: the two configs are not for the same connector"),
    (r"^errors\.", "HIGH", "🧯 another error handling: errors.tolerance / dead letter queue decide whether a bad record fails the task or is skipped"),
    (r"^transforms($|\.)|^predicates($|\.)", "MEDIUM", "🔁 another transform chain: test both with playground connector smt test"),
    (r"^(topics|topics\.regex|topic\.prefix|topic\.creation\.)", "MEDIUM", "📬 other topics: not the same data"),
    (r"^tasks\.max$", "LOW", "⚙️ another parallelism"),
    (r"^(consumer|producer|admin)\.override\.", "MEDIUM", "🎛️ another client override of the worker settings"),
    (r"(batch|flush|poll|linger|buffer|max\.size|interval)", "LOW", "⏱️ another batching / flushing setting: changes throughput and latency"),
    (r"(ssl|sasl|auth|security|password|credential|token)", "MEDIUM", "🔐 another security setting"),
]

STATUS_LABELS = {"different": "different", "only_a": "only left", "only_b": "only right", "masked": "masked", "same": "same",
                 "required": "no default", "no_default": "not a parameter"}


def parse_reference(path: Optional[str]) -> Dict[str, dict]:
    """config-<class>.txt: '🔘 <key>', its documentation, then '\t - Type: ...' lines"""
    ref: Dict[str, dict] = {}
    if not path:
        return ref
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return ref
    group, key, cur = "", None, None
    i = 0
    while i < len(lines):
        line = lines[i]
        if line == "==========================" and i + 2 < len(lines) and lines[i + 2] == "==========================":
            group = lines[i + 1]
            i += 3
            continue
        if line.startswith("🔘 "):
            key = line[2:].strip()
            cur = {"group": group, "doc": [], "type": "", "default": None, "importance": ""}
            ref[key] = cur
        elif cur is not None:
            m = re.match(r"^\s*- (Type|Default|Importance|Required): ?(.*)$", line)
            if m:
                field = m.group(1).lower()
                if field != "required":
                    cur[field] = m.group(2)
            elif line.strip():
                cur["doc"].append(line.strip())
        i += 1
    for v in ref.values():
        v["doc"] = " ".join(v["doc"])
    return ref


def findings(rows: List[dict], defaults: bool, label_b: str) -> List[dict]:
    res = []
    changed = [r for r in rows if r["status"] in ("different", "only_a", "only_b")]
    for pattern, severity, text in KEY_HINTS:
        rx = re.compile(pattern)
        keys = [r["key"] for r in changed if rx.search(r["key"])]
        if keys and not defaults:
            res.append({"severity": severity, "text": f"{text}: {', '.join(keys[:8])}{' …' if len(keys) > 8 else ''}"})
    masked = [r["key"] for r in rows if r["status"] == "masked"]
    if masked:
        res.append({"severity": "INFO", "text": f"🔒 {len(masked)} key(s) masked by the REST API are not compared: {', '.join(masked[:8])}"})
    if defaults:
        same = [r["key"] for r in rows if r["status"] == "same"]
        if same:
            res.append({"severity": "LOW", "text": f"💤 {len(same)} key(s) are set to their default value and could be removed: {', '.join(same[:8])}"
                                                   f"{' …' if len(same) > 8 else ''}"})
        unknown = [r["key"] for r in rows if r["status"] == "no_default"]
        if unknown:
            res.append({"severity": "INFO", "text": f"🧩 {len(unknown)} key(s) are not parameters of the plugin (worker override, transform, "
                                                    f"converter or predicate, or a typo): {', '.join(unknown[:8])}"})
    return rh.sort_findings(res)


def verdict(rows: List[dict], defaults: bool, a: str, b: str) -> Tuple[str, str]:
    if defaults:
        n = sum(1 for r in rows if r["status"] in ("different", "required"))
        return "ok", f"🔀 {a}: {n} parameter(s) differ from their default value."
    n = sum(1 for r in rows if r["status"] in ("different", "only_a", "only_b"))
    if not n:
        return "ok", f"✅ No difference between {a} and {b}."
    return "warn", f"🔀 {n} key(s) differ between {a} and {b}."


def value_html(key: str, v) -> str:
    if v is None:
        return "<span class='muted'>—</span>"
    # the REST API of a self-managed worker returns the passwords in clear
    return f"<span class='mono'>{rh.e(rh.mask_secret(key, v)) if v != '' else '<i>empty</i>'}</span>"


def key_html(key: str, ref: Dict[str, dict]) -> str:
    r = ref.get(key)
    if not r:
        return f"<span class='mono'><b>{rh.e(key)}</b></span>"
    tip = (r["doc"][:600] + (" …" if len(r["doc"]) > 600 else "")) if r["doc"] else ""
    meta = " · ".join(x for x in (r["type"], f"default {r['default']}" if r["default"] is not None else "", r["importance"]) if x)
    return (f"<span class='mono'><b>{rh.e(key)}</b></span><br><span class='legend'>{rh.e(meta)}</span>"
            + (f"<details><summary class='legend'>doc</summary><p class='legend'>{rh.e(tip)}</p></details>" if tip else ""))


def html_report(rows: List[dict], a: str, b: str, defaults: bool, connector_class: str, ref: Dict[str, dict], ref_name: str) -> str:
    count = {k: sum(1 for r in rows if r["status"] == k) for k in STATUS_LABELS}
    if defaults:
        cards = [rh.kpi("✏️ Not default", count["different"], "set to another value", "warn" if count["different"] else "ok"),
                 rh.kpi("📌 No default", count["required"], "required parameters"),
                 rh.kpi("💤 At default", count["same"], "could be removed", "warn" if count["same"] else "ok"),
                 rh.kpi("🧩 Not a parameter", count["no_default"], "override, transform..."),
                 rh.kpi("🔒 Masked", count["masked"], "not compared")]
    else:
        cards = [rh.kpi("✏️ Different", count["different"], "same key, other value", "warn" if count["different"] else "ok"),
                 rh.kpi("➖ Only left", count["only_a"], a, "warn" if count["only_a"] else "ok"),
                 rh.kpi("➕ Only right", count["only_b"], b, "warn" if count["only_b"] else "ok"),
                 rh.kpi("🟰 Same", count["same"], "identical keys"),
                 rh.kpi("🔒 Masked", count["masked"], "not compared")]
    order = ["different", "required", "only_a", "only_b", "no_default", "masked", "same"]
    shown = [r for r in sorted(rows, key=lambda r: (order.index(r["status"]), r["key"])) if r["status"] != "same"]
    same = [r for r in rows if r["status"] == "same"]
    right = "Default" if defaults else rh.e(b)

    def row(r):
        cls = {"different": "warn", "only_a": "failed", "only_b": "running", "masked": "paused", "required": "mine",
               "no_default": "paused"}.get(r["status"], "")
        a_cls = " class='diff-a'" if r["status"] in ("different", "only_a") and not defaults else ""
        b_cls = " class='diff-b'" if r["status"] in ("different", "only_b") and not defaults else ""
        return (f"<tr><td>{key_html(r['key'], ref)}</td><td>{rh.badge(STATUS_LABELS[r['status']], cls)}</td>"
                f"<td{a_cls}>{value_html(r['key'], r.get('a'))}</td><td{b_cls}>{value_html(r['key'], r.get('b'))}</td></tr>")

    head = f"<tr><th>Key</th><th>Status</th><th>{rh.e(a)}</th><th>{right}</th></tr>"
    body = [rh.verdict_html(*verdict(rows, defaults, a, b)), rh.kpis_html(cards), rh.findings_html(findings(rows, defaults, b))]
    if shown:
        body.append(rh.card("🔀 Keys that differ" if not defaults else "🔀 Parameters not at their default value",
                            f"<table>{head}{''.join(row(r) for r in shown)}</table>"))
    if same:
        body.append(f"<div class='table-card'><details><summary><b>🟰 {len(same)} identical key(s)</b></summary>"
                    f"<table>{head}{''.join(row(r) for r in sorted(same, key=lambda r: r['key']))}</table></details></div>")
    meta = [f"🔗 {rh.e(a)}", f"vs {rh.e('defaults of the plugin' if defaults else b)}"]
    if connector_class:
        meta.append(f"<span class='mono'>{rh.e(connector_class)}</span>")
    ref_note = (f"Documentation and defaults from {rh.e(ref_name)}." if ref else
                "No configuration reference found for this connector class: no documentation.")
    return rh.page(f"Connector config diff — {a} vs {b}", "🔀 Connector Config Diff", meta, "".join(body),
                   f"🛠️ Generated by playground connector diff (self-contained, no external resource). {ref_note} "
                   "Values masked by the REST API ([hidden], ****) are never compared, secrets are masked in this report.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--diff", required=True, help="diff.json")
    ap.add_argument("--a", required=True, help="label of the connector")
    ap.add_argument("--b", required=True, help="label of what it is compared with")
    ap.add_argument("--defaults", action="store_true", help="the comparison is with the defaults of the plugin")
    ap.add_argument("--connector-class", default="")
    ap.add_argument("--reference", help="config-<class>.txt of the connector")
    ap.add_argument("--html-out", required=True)
    args = ap.parse_args()
    with open(args.diff, encoding="utf-8") as fh:
        rows = json.load(fh)
    ref = parse_reference(args.reference)
    with open(args.html_out, "w", encoding="utf-8") as fh:
        fh.write(html_report(rows, args.a, args.b, args.defaults, args.connector_class, ref,
                             os.path.basename(args.reference) if args.reference else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
