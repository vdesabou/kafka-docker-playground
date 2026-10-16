#!/usr/bin/env python3
"""HTML report of a 'playground connector smt test' run.

Self-contained file, light and dark themes. One or several result json written by SmtTester (--json-out): one per CP
version with --cp-version. Shows the chain, then for each step what changed (value with the added / changed / removed
fields highlighted, schema diff, topic / key / headers), the predicates, the dropped record or the error; and with
several versions, a comparison of the steps.

    smt_report.py --result <result json> [--result <result json>]... --output <report.html> [--title <text>]
"""
import argparse
import html
import json
import sys

STATUS = {
    "applied": ("✅", "applied", "good"),
    "unchanged": ("➖", "no change", "neutral"),
    "skipped": ("⏭️", "skipped by predicate", "neutral"),
    "dropped": ("🗑️", "record dropped", "warning"),
    "error": ("❌", "failed", "critical"),
    "input": ("🧾", "input", "neutral"),
}


def esc(value):
    return html.escape(str(value), quote=True)


def parse(value):
    """values are json text (rendered by the JsonConverter): parsed when possible"""
    if value is None:
        return None
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return value


def step_status(step, previous_record):
    if step.get("index") == 0:
        return "input"
    if step.get("error"):
        return "error"
    if step.get("dropped"):
        return "dropped"
    if step.get("skipped"):
        return "skipped"
    record = step.get("record") or {}
    if previous_record is not None and all(record.get(k) == previous_record.get(k) for k in ("topic", "key", "value", "value_schema", "headers", "partition", "timestamp")):
        return "unchanged"
    return "applied"


def render_json(after, before, indent=0, removed=None):
    """pretty json of <after> as html, with the keys added or changed against <before> highlighted, and the keys of
    <before> that are gone shown struck through"""
    pad = "  " * indent
    if isinstance(after, dict):
        before_dict = before if isinstance(before, dict) else None
        lines = ["{"]
        keys = list(after.keys())
        gone = [k for k in (before_dict or {}) if k not in after] if before_dict is not None else []
        items = []
        for k in keys:
            v = after[k]
            if before_dict is None:
                cls = ""
                child = render_json(v, None, indent + 1)
            elif k not in before_dict:
                cls = "added"
                child = render_json(v, None, indent + 1)
            elif before_dict[k] != v:
                if isinstance(v, (dict, list)) and isinstance(before_dict[k], type(v)):
                    cls = ""
                    child = render_json(v, before_dict[k], indent + 1)
                else:
                    cls = "changed"
                    child = render_json(v, None, indent + 1)
            else:
                cls = ""
                child = render_json(v, None, indent + 1)
            title = ""
            if cls == "changed":
                title = ' title="was: %s"' % esc(json.dumps(before_dict[k], ensure_ascii=False))
            items.append('%s  <span class="%s"%s><span class="k">"%s"</span>: %s</span>' % (pad, cls, title, esc(k), child))
        for k in gone:
            items.append('%s  <span class="removed"><span class="k">"%s"</span>: %s</span>' % (pad, esc(k), render_json(before_dict[k], None, indent + 1)))
        if not items:
            return "{}"
        lines.append(",\n".join(items))
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(after, list):
        if not after:
            return "[]"
        inner = ",\n".join(pad + "  " + render_json(v, (before[i] if isinstance(before, list) and i < len(before) else None), indent + 1) for i, v in enumerate(after))
        return "[\n" + inner + "\n" + pad + "]"
    return '<span class="v">%s</span>' % esc(json.dumps(after, ensure_ascii=False))


def schema_rows(before, after):
    """field level schema diff of two snapshots (value_fields)"""
    bf = (before or {}).get("value_fields") or {}
    af = (after or {}).get("value_fields") or {}
    rows = []
    for name, type_ in af.items():
        if name not in bf:
            rows.append(("added", name, "", type_))
        elif bf[name] != type_:
            rows.append(("changed", name, bf[name], type_))
    for name, type_ in bf.items():
        if name not in af:
            rows.append(("removed", name, type_, ""))
    return rows


def header_list(record):
    """headers of a snapshot: a list of {key, value, schema} (a {key: value} object in older results)"""
    headers = (record or {}).get("headers") or []
    if isinstance(headers, dict):
        return [{"key": k, "value": json.dumps(v), "schema": "STRING"} for k, v in headers.items()]
    return headers


def header_rows(before, after):
    """header changes by key: the n-th header of a key against the n-th one of the previous snapshot"""
    def by_key(headers):
        grouped = {}
        for h in headers:
            grouped.setdefault(h.get("key"), []).append(h)
        return grouped
    b, a = by_key(header_list(before)), by_key(header_list(after))
    rows = []
    for key, items in a.items():
        old = b.get(key, [])
        for i, h in enumerate(items):
            if i >= len(old):
                rows.append(("added", key, "", "", h.get("value"), h.get("schema")))
            elif old[i] != h:
                rows.append(("changed", key, old[i].get("value"), old[i].get("schema"), h.get("value"), h.get("schema")))
    for key, items in b.items():
        for h in items[len(a.get(key, [])):]:
            rows.append(("removed", key, h.get("value"), h.get("schema"), "", ""))
    return rows


def part(icon, label, body, note=""):
    """one labelled block of a record: topic, key, headers, value"""
    return '<div class="part"><div class="part-label">%s %s</div><div class="part-body">%s%s</div></div>' % (icon, label, ('<div class="note">%s</div>' % note) if note else "", body)


def location(record):
    return '<span class="chip"><code>%s</code></span> partition %s%s · 🕒 %s' % (
        esc(record.get("topic")), esc(record.get("partition", "-")), (" · offset %s" % esc(record["offset"])) if "offset" in record else "", esc(record.get("timestamp", "-")))


def key_part(record, note=""):
    return part("🔑", "key", '<span class="chip"><code>%s</code></span> <span class="type">%s</span>' % (esc(record.get("key")), esc(record.get("key_schema"))), note)


def headers_part(record, note=""):
    headers = header_list(record)
    if not headers:
        return part("🏷️", "headers", '<span class="muted">none</span>', note)
    return part("🏷️", "headers", '<table class="kv"><tr><th>key</th><th>value</th><th>type</th></tr>' + "".join(
        '<tr><td><code class="hk">%s</code></td><td><code>%s</code></td><td><span class="type">%s</span></td></tr>' % (esc(h.get("key")), esc(h.get("value")), esc(h.get("schema")))
        for h in headers) + "</table>", note or "(%d)" % len(headers))


def config_table(config):
    return '<table class="config">' + "".join(
        '<tr><td class="ck">%s</td><td><code>%s</code></td></tr>' % (esc(k), esc(v) if v != "" else '<span class="muted">(empty)</span>') for k, v in config.items()) + "</table>"


def render_run(result, run_index):
    steps = result.get("steps", [])
    out = []
    previous = None
    for step in steps:
        record = step.get("record")
        status = step_status(step, previous)
        icon, label, tone = STATUS[status]
        index = step.get("index", 0)
        if index == 0:
            title = "🧾 Input record"
        else:
            title = "🔀 %s <span class=\"alias\">%s</span>" % (esc((step.get("type") or "?").split(".")[-1]), esc(step.get("alias", "")))
        out.append('<section class="card step st-%s" id="r%d-s%d">' % (status, run_index, index))
        out.append('<div class="step-head"><span class="num">%s</span><h3>%s</h3><span class="badge %s">%s %s</span></div>' % (index, title, tone, icon, label))
        meta = []
        if step.get("type"):
            meta.append(("🧩 class", "<code>%s</code>" % esc(step["type"])))
        if step.get("origin"):
            meta.append(("📦 from", esc(step["origin"])))
        if step.get("also_in"):
            meta.append(("⚠️ also in", '<span class="warn">⚠️ %s (the worker could load another copy)</span>' % esc(", ".join(step["also_in"]))))
        if step.get("config"):
            meta.append(("⚙️ config", config_table(step["config"])))
        if step.get("predicate"):
            meta.append(("🎯 predicate", "<code>%s</code> (%s) = <b>%s</b>%s" % (esc(step["predicate"]), esc((step.get("predicate_type") or "").split(".")[-1]),
                                                                             esc(step.get("predicate_result")), ", negate=true" if step.get("negate") else "")))
        if meta:
            out.append('<table class="meta">' + "".join("<tr><th>%s</th><td>%s</td></tr>" % (k, v) for k, v in meta) + "</table>")
        if status == "error":
            out.append('<div class="error">❌ %s</div>' % esc(step.get("error")))
            if step.get("stack_trace"):
                out.append("<details><summary>stack trace</summary><pre>%s</pre></details>" % esc(step["stack_trace"]))
        elif status == "dropped":
            out.append('<div class="dropped">🗑️ the transform returned null: the record is dropped, the next transforms do not run</div>')
        elif record is not None:
            if index == 0:
                out.append(part("📍", "topic", location(record)))
                out.append(key_part(record))
                out.append(headers_part(record))
            elif previous is not None:
                moves = ['<tr><td class="ck">%s</td><td><span class="removed">%s</span> → <span class="added">%s</span></td></tr>' % (field, esc(previous.get(field)), esc(record.get(field)))
                         for field in ("topic", "partition", "timestamp") if record.get(field) != previous.get(field)]
                if moves:
                    out.append(part("📍", "topic", '<table class="config">%s</table>' % "".join(moves), "(changed)"))
                if record.get("key") != previous.get("key") or record.get("key_schema") != previous.get("key_schema"):
                    out.append(key_part(record, '(changed, was <code>%s</code> %s)' % (esc(previous.get("key")), esc(previous.get("key_schema")))))
                rows = header_rows(previous, record)
                if rows:
                    out.append(part("🏷️", "headers", '<table class="kv"><tr><th></th><th>key</th><th>before</th><th>after</th></tr>' + "".join(
                        '<tr class="%s"><td>%s</td><td><code class="hk">%s</code></td><td>%s</td><td>%s</td></tr>' % (
                            kind, {"added": "+", "removed": "−", "changed": "~"}[kind], esc(key),
                            ("<code>%s</code> <span class=\"type\">%s</span>" % (esc(bv), esc(bs))) if bs else "",
                            ("<code>%s</code> <span class=\"type\">%s</span>" % (esc(av), esc(as_))) if as_ else "")
                        for kind, key, bv, bs, av, as_ in rows) + "</table>", "(changes)"))
            value_after = parse(record.get("value"))
            value_before = parse(previous.get("value")) if previous is not None and status != "skipped" else None
            value_changed = index == 0 or previous is None or record.get("value") != previous.get("value") or record.get("value_schema") != previous.get("value_schema")
            if status == "applied" and not value_changed:
                out.append(part("📄", "value", '<span class="muted">➖ unchanged</span>'))
            elif status in ("applied", "input") or (status == "unchanged" and index == 0):
                out.append(part("📄", "value", '<pre class="json">%s</pre>' % render_json(value_after, value_before if index > 0 else None),
                                ("schema: %s" % esc(record.get("value_schema"))) if index == 0 else
                                '(after this step; <span class="added">added</span>, <span class="changed">changed</span>, <span class="removed">removed</span>)'))
                rows = schema_rows(previous, record) if index > 0 else []
                if index > 0 and rows:
                    out.append('<table class="schema-diff"><tr><th></th><th>field</th><th>before</th><th>after</th></tr>' + "".join(
                        '<tr class="%s"><td>%s</td><td><code>%s</code></td><td>%s</td><td>%s</td></tr>' % (
                            kind, {"added": "+", "removed": "−", "changed": "~"}[kind], esc(name), esc(b), esc(a)) for kind, name, b, a in rows) + "</table>")
                elif index > 0 and record.get("value_schema") != (previous or {}).get("value_schema"):
                    out.append('<div class="muted schema">schema: %s → %s</div>' % (esc((previous or {}).get("value_schema")), esc(record.get("value_schema"))))
            elif status == "unchanged":
                out.append('<div class="muted">➖ the record is unchanged</div>')
            elif status == "skipped":
                out.append('<div class="muted">⏭️ the predicate decided not to apply this transform: the record goes to the next step unchanged</div>')
        out.append("</section>")
        if record is not None and status not in ("error", "dropped"):
            previous = record
        if status in ("error", "dropped"):
            break
    return "\n".join(out)


def render_final(result, run_index):
    """the record after the whole chain: what the connector writes (sink) or sends to kafka (source)"""
    kind, text = outcome(result)
    steps = result.get("steps", [])
    out = ['<section class="card final" id="r%d-final">' % run_index,
           '<div class="step-head"><span class="num">🏁</span><h3>Final record</h3><span class="badge %s">%s</span></div>' % (
               {"ok": "good", "dropped": "warning", "error": "critical"}[kind], {"ok": "✅ after the whole chain", "dropped": "🗑️ dropped", "error": "❌ failed"}[kind])]
    if kind != "ok":
        out.append('<div class="%s">%s: no record comes out of the chain</div>' % ("dropped" if kind == "dropped" else "error", esc(text)))
        out.append("</section>")
        return "\n".join(out)
    record = [s for s in steps if s.get("record")][-1]["record"]
    sink = result.get("connector_type", "sink") == "sink"
    out.append('<div class="muted">%s</div>' % ("what the sink connector receives in put()" if sink else "what the source connector sends to kafka (before the converters)"))
    out.append(part("📍", "topic", location(record)))
    out.append(key_part(record))
    out.append(headers_part(record))
    out.append(part("📄", "value", '<pre class="json">%s</pre>' % render_json(parse(record.get("value")), None), "schema: %s" % esc(record.get("value_schema"))))
    out.append("</section>")
    return "\n".join(out)


def outcome(result):
    steps = result.get("steps", [])
    for step in steps:
        if step.get("error"):
            return "error", "❌ failed at step %s (%s): %s" % (step.get("index"), step.get("alias"), step.get("error"))
        if step.get("dropped"):
            return "dropped", "🗑️ dropped by step %s (%s)" % (step.get("index"), step.get("alias"))
    last = [s for s in steps if s.get("record")]
    record = last[-1]["record"] if last else {}
    return "ok", "✅ topic %s · key %s · value %s" % (record.get("topic"), record.get("key"), record.get("value"))


def normalized(result):
    """the comparable content of a run: values as json (key order of a schemaless map ignored)"""
    out = []
    for step in result.get("steps", []):
        record = step.get("record") or {}
        out.append(json.dumps({"alias": step.get("alias"), "error": (step.get("error") or "").split(":")[0] or None, "dropped": step.get("dropped"),
                               "skipped": step.get("skipped"), "topic": record.get("topic"), "key": parse(record.get("key")),
                               "value": parse(record.get("value")), "headers": record.get("headers")}, sort_keys=True))
    return out


def comparison(results):
    """steps as rows, versions as columns; the cells that differ from the first version are flagged"""
    labels = [r.get("label") or "run %d" % (i + 1) for i, r in enumerate(results)]
    norms = [normalized(r) for r in results]
    max_steps = max(len(r.get("steps", [])) for r in results)
    head = "<tr><th>step</th>" + "".join("<th>%s<br><span class=\"muted\">Kafka %s</span></th>" % (esc(l), esc(r.get("kafka_version"))) for l, r in zip(labels, results)) + "</tr>"
    rows = []
    for i in range(max_steps):
        name = ""
        cells = []
        for j, r in enumerate(results):
            steps = r.get("steps", [])
            if i >= len(steps):
                cells.append('<td class="muted">—</td>')
                continue
            step = steps[i]
            name = name or ("input" if i == 0 else "%s %s" % ((step.get("type") or "?").split(".")[-1], step.get("alias")))
            prev = steps[i - 1].get("record") if i > 0 else None
            st = step_status(step, prev)
            icon, label, tone = STATUS[st]
            differs = j > 0 and (i >= len(norms[0]) or norms[j][i] != norms[0][i])
            if st == "error":
                text = esc(step.get("error"))[:220]
            elif st == "dropped":
                text = "record dropped"
            else:
                rec = step.get("record") or {}
                text = "topic <code>%s</code><br><code>%s</code>" % (esc(rec.get("topic")), esc(rec.get("value"))[:220])
            cells.append('<td class="%s"><span class="badge %s">%s %s</span>%s<div class="cell">%s</div></td>' % (
                "differs" if differs else "", tone, icon, label, ' <span class="badge warning">⚠️ ≠ first version</span>' if differs else "", text))
        rows.append("<tr><th>%s. %s</th>%s</tr>" % (i, esc(name), "".join(cells)))
    same = len(set("\n".join(n) for n in norms)) == 1
    verdict = '<div class="verdict good">✅ same result with all the versions</div>' if same else '<div class="verdict warning">⚠️ the versions give different results: the differing cells are flagged</div>'
    return verdict + '<div class="card"><table class="compare">' + head + "".join(rows) + "</table></div>"


def short_error(error, limit=140):
    """first line of an error without the exception class, shortened"""
    text = (error or "").strip().splitlines()[0] if (error or "").strip() else "unknown error"
    head, sep, rest = text.partition(": ")
    if sep and "." in head and " " not in head:
        text = rest
    return text if len(text) <= limit else text[:limit - 1].rstrip() + "…"


def step_name(step):
    """the alias of a transform, with its class when it helps"""
    short = (step.get("type") or "").split(".")[-1]
    alias = step.get("alias") or "?"
    return "%s, %s" % (alias, short) if short else alias


def run_verdict(result):
    """(tone, emoji, sentence) summarising the chain of one run"""
    if result.get("error"):
        return "critical", "❌", "The SMT test could not run: %s" % short_error(result["error"])
    steps = result.get("steps", [])
    for step in steps:
        if step.get("error"):
            return "critical", "❌", "Step %s (%s) failed: %s" % (step.get("index"), step_name(step), short_error(step.get("error")))
        if step.get("dropped"):
            return "warning", "🗑️", "The record was dropped by step %s (%s)" % (step.get("index"), step_name(step))
    transforms = len(steps) - 1
    skipped = sum(1 for s in steps if s.get("index") and s.get("skipped"))
    text = "The record went through the %d transform%s" % (transforms, "" if transforms == 1 else "s")
    if skipped:
        text += " (%d skipped by predicate)" % skipped
    return "good", "✅", text


def end(text):
    """a sentence ends with a period, unless it was shortened"""
    return text if text.endswith("…") else text + "."


def banner(results):
    """the one-sentence verdict under the header; with several versions, whether they agree"""
    verdicts = [run_verdict(r) for r in results]
    if len(results) == 1:
        tone, icon, text = verdicts[0]
        return '<div class="banner %s">%s %s</div>' % (tone, icon, end(esc(text)))
    labels = [r.get("label") or "run %d" % (i + 1) for i, r in enumerate(results)]
    if len(set("\n".join(normalized(r)) for r in results)) == 1:
        tone, icon, text = verdicts[0]
        return '<div class="banner %s">%s The %d versions agree: %s</div>' % (tone, icon, len(results), end(esc(text[0].lower() + text[1:])))
    # same outcome everywhere (all applied, same step dropped or failed): the records themselves differ
    if len(set(v[2] for v in verdicts)) == 1:
        return '<div class="banner warning">⚠️ The versions give different records: %s in all of them, but the values differ (see the flagged cells below).</div>' % (
            esc(verdicts[0][2][0].lower() + verdicts[0][2][1:]))
    return '<div class="banner warning">⚠️ The versions disagree: %s</div>' % end("; ".join(
        "<b>%s</b> %s %s" % (esc(l), v[1], esc(v[2][0].lower() + v[2][1:])) for l, v in zip(labels, verdicts)))


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
.root { color-scheme: light; --page: #f9f9f7; --surface: #fcfcfb; --text: #0b0b0b; --text2: #52514e; --muted: #898781; --grid: #e1e0d9;
  --border: rgba(11,11,11,0.10); --accent: #2a78d6; --good: #0ca30c; --good-bg: #e7f6e7; --warning: #b77900; --warning-bg: #fdf2dc;
  --critical: #d03b3b; --critical-bg: #fbe9e9; --added: #e3f5e3; --changed: #fdf0d2; --removed: #fbe4e4; }
@media (prefers-color-scheme: dark) { :root:where(:not([data-theme="light"])) .root { color-scheme: dark; --page: #0d0d0d; --surface: #1a1a19;
  --text: #f0efec; --text2: #c3c2b7; --muted: #898781; --grid: #2c2c2a; --border: rgba(255,255,255,0.10); --accent: #3987e5;
  --good-bg: #12301a; --warning: #fab219; --warning-bg: #3a2f12; --critical-bg: #3a1717; --added: #163a1f; --changed: #3d3216; --removed: #421c1c; } }
:root[data-theme="dark"] .root { color-scheme: dark; --page: #0d0d0d; --surface: #1a1a19; --text: #f0efec; --text2: #c3c2b7; --muted: #898781;
  --grid: #2c2c2a; --border: rgba(255,255,255,0.10); --accent: #3987e5; --good-bg: #12301a; --warning: #fab219; --warning-bg: #3a2f12;
  --critical-bg: #3a1717; --added: #163a1f; --changed: #3d3216; --removed: #421c1c; }
* { box-sizing: border-box; } body { margin: 0; }
.root { background: var(--page); color: var(--text); min-height: 100vh; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; padding: 28px 32px 48px; }
header { display: flex; justify-content: space-between; gap: 16px; align-items: flex-start; }
h1 { font-size: 1.35rem; margin: 0 0 4px; font-weight: 600; } h2 { font-size: 1.05rem; margin: 26px 0 10px; } h3 { font-size: 1rem; margin: 0; font-weight: 600; }
.sub, .muted { color: var(--text2); font-size: .875rem; } .muted { color: var(--muted); }
.theme-toggle { white-space: nowrap; font: inherit; font-size: .8rem; color: var(--text2); background: var(--surface); border: 1px solid var(--border); border-radius: 6px; padding: 4px 10px; cursor: pointer; }
.card { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 14px 18px; margin: 12px 0; }
.chain { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin: 18px 0 6px; }
.chain a { text-decoration: none; color: inherit; } .arrow { color: var(--muted); }
.badge { display: inline-block; font-size: .78rem; padding: 2px 8px; border-radius: 999px; border: 1px solid var(--border); white-space: nowrap; }
.badge.good { background: var(--good-bg); } .badge.warning { background: var(--warning-bg); } .badge.critical { background: var(--critical-bg); }
.badge.neutral { background: var(--page); }
.step-head { display: flex; align-items: center; gap: 10px; margin-bottom: 8px; }
.num { display: inline-flex; align-items: center; justify-content: center; width: 26px; height: 26px; border-radius: 50%; background: var(--page); border: 1px solid var(--border); font-size: .8rem; font-weight: 600; }
.alias { color: var(--text2); font-weight: 400; }
.final { border-width: 2px; border-color: var(--accent); }
.step.st-error { border-color: var(--critical); border-width: 2px; } .step.st-dropped { border-color: var(--warning); border-width: 2px; }
table { border-collapse: collapse; } .meta { font-size: .84rem; margin: 4px 0 8px; }
.meta th { text-align: left; color: var(--text2); font-weight: 500; width: 124px; padding: 3px 12px 3px 0; vertical-align: top; white-space: nowrap; }
.meta td { padding: 3px 0; } code { font-family: "SFMono-Regular", Consolas, Menlo, monospace; font-size: .8rem; }
.meta code { background: var(--page); border: 1px solid var(--border); border-radius: 4px; padding: 0 4px; margin-right: 4px; display: inline-block; margin-bottom: 2px; }
pre { margin: 0; font-family: "SFMono-Regular", Consolas, Menlo, monospace; font-size: .8rem; white-space: pre-wrap; word-break: break-word; }
.json { background: var(--page); border: 1px solid var(--border); border-radius: 6px; padding: 10px 12px; }
.json .k { color: var(--accent); }
.added { background: var(--added); border-radius: 3px; } .changed { background: var(--changed); border-radius: 3px; cursor: help; }
.removed { background: var(--removed); text-decoration: line-through; border-radius: 3px; }
.part { display: grid; grid-template-columns: 112px 1fr; gap: 12px; align-items: start; padding: 8px 0; border-top: 1px solid var(--grid); font-size: .86rem; }
.part-label { font-weight: 600; white-space: nowrap; padding-top: 1px; } .part-body { min-width: 0; }
.note { color: var(--muted); font-size: .78rem; margin-bottom: 4px; } .note code { font-size: .76rem; }
.chip code { background: var(--page); border: 1px solid var(--border); border-radius: 4px; padding: 1px 6px; font-size: .84rem; font-weight: 600; }
.type { font-size: .72rem; color: var(--text2); background: var(--page); border: 1px solid var(--border); border-radius: 999px; padding: 0 7px; font-family: "SFMono-Regular", Consolas, Menlo, monospace; }
.kv { font-size: .82rem; } .kv th { text-align: left; color: var(--muted); font-weight: 500; font-size: .74rem; padding: 0 16px 3px 0; }
.kv td { padding: 3px 16px 3px 0; border-top: 1px solid var(--grid); } .kv .hk { font-weight: 600; }
.kv tr.added td, .kv tr.removed td, .kv tr.changed td { background: none; } .kv tr.added { background: var(--added); } .kv tr.changed { background: var(--changed); }
.kv tr.removed { background: var(--removed); } .kv tr.removed .hk { text-decoration: line-through; }
.config { font-size: .82rem; border: 1px solid var(--border); border-radius: 6px; background: var(--page); border-collapse: separate; border-spacing: 0; }
.config td { padding: 3px 10px; vertical-align: top; } .config tr + tr td { border-top: 1px solid var(--grid); }
.config .ck { color: var(--text2); font-family: "SFMono-Regular", Consolas, Menlo, monospace; font-size: .78rem; white-space: nowrap; }
.config code, .meta .config code { font-weight: 600; word-break: break-all; background: none; border: 0; padding: 0; margin: 0; }
.label { font-size: .8rem; color: var(--text2); margin: 6px 0 4px; }
.schema { margin-top: 6px; font-size: .8rem; }
.schema-diff { font-size: .82rem; margin-top: 8px; } .headers { margin-bottom: 4px; } .schema-diff th, .schema-diff td { padding: 3px 12px 3px 0; text-align: left; }
.schema-diff th { color: var(--text2); font-weight: 500; }
.error { background: var(--critical-bg); border-radius: 6px; padding: 10px 12px; font-size: .86rem; }
.dropped { background: var(--warning-bg); border-radius: 6px; padding: 10px 12px; font-size: .86rem; }
.warn { color: var(--warning); }
details { margin-top: 8px; } summary { cursor: pointer; font-size: .84rem; color: var(--text2); }
.verdict { padding: 10px 14px; border-radius: 8px; margin: 10px 0; font-size: .9rem; } .verdict.good { background: var(--good-bg); } .verdict.warning { background: var(--warning-bg); } .verdict.critical { background: var(--critical-bg); }
.result { font-size: .9rem; }
.banner { background: var(--surface); border: 1px solid var(--border); border-left: 4px solid var(--muted); border-radius: 10px; padding: 12px 18px; margin: 16px 0 4px; font-size: 1rem; font-weight: 500; }
.banner.good { border-left-color: var(--good); } .banner.warning { border-left-color: var(--warning); } .banner.critical { border-left-color: var(--critical); }
.compare { width: 100%; font-size: .82rem; } .compare th, .compare td { border-bottom: 1px solid var(--grid); padding: 8px 10px; text-align: left; vertical-align: top; }
.compare th { color: var(--text2); font-weight: 500; } .compare td.differs { background: var(--warning-bg); }
.cell { margin-top: 4px; word-break: break-word; }
.tabs { display: flex; gap: 6px; margin: 16px 0 4px; flex-wrap: wrap; }
.tab { font: inherit; font-size: .85rem; padding: 5px 12px; border-radius: 6px; border: 1px solid var(--border); background: var(--surface); color: var(--text); cursor: pointer; }
.tab[aria-selected="true"] { border-color: var(--accent); box-shadow: inset 0 -2px 0 var(--accent); }
footer { color: var(--muted); font-size: .78rem; margin-top: 24px; }
</style></head>
<body><div class="root">
<header><div><h1>🔀 __TITLE__</h1><p class="sub">__SUBTITLE__</p></div><button class="theme-toggle" id="theme-toggle" type="button">Toggle theme</button></header>
__BANNER__
__BODY__
<footer>🛠️ Generated by playground connector smt test. Hover a changed field to see its previous value.</footer>
</div>
<script>
document.getElementById("theme-toggle").addEventListener("click", () => {
  const root = document.documentElement;
  const dark = root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  root.dataset.theme = dark ? "light" : "dark";
});
document.querySelectorAll(".tab").forEach(tab => tab.addEventListener("click", () => {
  document.querySelectorAll(".tab").forEach(t => t.setAttribute("aria-selected", t === tab ? "true" : "false"));
  document.querySelectorAll(".run").forEach(r => r.hidden = r.id !== tab.dataset.run);
}));
</script>
</body></html>
"""


def main():
    parser = argparse.ArgumentParser(description="HTML report of a playground connector smt test run")
    parser.add_argument("--result", action="append", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--title", default="SMT test")
    args = parser.parse_args()
    results = []
    for path in args.result:
        with open(path) as f:
            results.append(json.load(f))

    body = []
    first = results[0]
    if len(results) > 1:
        body.append("<h2>🆚 Comparison of the versions</h2>")
        body.append(comparison(results))
        body.append('<h2>🔀 Steps per version</h2><div class="tabs">%s</div>' % "".join(
            '<button class="tab" type="button" data-run="run%d" aria-selected="%s">%s</button>' % (i, "true" if i == 0 else "false", esc(r.get("label") or "run %d" % (i + 1)))
            for i, r in enumerate(results)))
    for i, result in enumerate(results):
        body.append('<div class="run" id="run%d"%s>' % (i, " hidden" if i > 0 else ""))
        if result.get("error"):
            body.append('<div class="card error">❌ %s</div></div>' % esc(result["error"]))
            continue
        if result.get("plugin_loading"):
            body.append('<div class="card warn">⚠️ %s</div>' % esc(result["plugin_loading"]))
        steps = result.get("steps", [])
        chain = []
        previous = None
        for step in steps:
            st = step_status(step, previous)
            icon, label, tone = STATUS[st]
            name = "input" if step.get("index") == 0 else "%s %s" % ((step.get("type") or "?").split(".")[-1], step.get("alias"))
            chain.append('<a href="#r%d-s%d"><span class="badge %s" title="%s">%s %s</span></a>' % (i, step.get("index", 0), tone, esc(label), icon, esc(name)))
            if step.get("record") and st not in ("error", "dropped"):
                previous = step["record"]
            if st in ("error", "dropped"):
                break
        chain.append('<a href="#r%d-final"><span class="badge neutral" title="the record after the whole chain">🏁 final record</span></a>' % i)
        body.append('<div class="chain">%s</div>' % '<span class="arrow">→</span>'.join(chain))
        kind, text = outcome(result)
        tone = {"ok": "good", "dropped": "warning", "error": "critical"}[kind]
        body.append('<div class="verdict %s result">%s</div>' % (tone, esc(text)))
        body.append(render_run(result, i))
        body.append(render_final(result, i))
        body.append("</div>")

    transforms = len(first.get("steps", [])) - 1
    subtitle = "%d transform(s) on a %s record · %s" % (transforms, first.get("connector_type", "sink"),
                                                       " · ".join("%s (Kafka %s)" % (r.get("label") or "run", r.get("kafka_version")) for r in results))
    page = PAGE.replace("__TITLE__", esc(args.title)).replace("__SUBTITLE__", esc(subtitle)).replace("__BANNER__", banner(results)).replace("__BODY__", "\n".join(body))
    with open(args.output, "w") as f:
        f.write(page)
    print(args.output)


if __name__ == "__main__":
    sys.exit(main())
