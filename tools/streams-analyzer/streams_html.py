"""
HTML view of the Kafka Streams report of streams_report.py, with the shared look of the playground reports
(tools/report-common/report_html.py):

- fragment(report): the 🌊 Kafka Streams section, embedded in the log report of playground analyze logs
  (log_report.py --html-section)
- page_html(report, title): a standalone page, playground streams status --html

Per application: KPI tiles, findings, a state timeline per instance (restarts and the time without logs shown), the
instances, the task assignment (task × instance, active or standby), the known errors with their advice, the consumer
group (streams status only).
"""

import os
import re
import sys
from datetime import datetime

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
from report_html import badge, card, e, findings_html, kpi, kpis_html, page, table  # noqa: E402

STATE_COLORS = {
    "RUNNING": "#16a34a", "REBALANCING": "#f59e0b", "PARTITIONS_ASSIGNED": "#f59e0b", "PARTITIONS_REVOKED": "#f59e0b",
    "CREATED": "#94a3b8", "STARTING": "#94a3b8", "PENDING_SHUTDOWN": "#64748b", "NOT_RUNNING": "#475569",
    "PENDING_ERROR": "#dc2626", "ERROR": "#b91c1c", "DEAD": "#b91c1c",
}
NO_LOGS_COLOR = "#e5e7eb"
CSS = """<style>
.st-timeline{width:100%;overflow-x:auto}.st-timeline svg{display:block;width:100%;height:auto;min-width:700px}
.st-legend{display:flex;flex-wrap:wrap;gap:12px;font-size:12px;margin:6px 0 2px}
.st-legend span{display:inline-flex;align-items:center;gap:4px}.st-legend i{width:12px;height:12px;border-radius:2px;display:inline-block}
.st-tasks td.a{background:rgba(22,163,74,.18);color:#16a34a;font-weight:600;text-align:center}
.st-tasks td.s{background:rgba(37,99,235,.16);color:#3b82f6;text-align:center}
.st-tasks td.x{background:rgba(220,38,38,.2);color:#ef4444;font-weight:700;text-align:center}
.st-tasks td.n{text-align:center;color:#94a3b8}
</style>"""


def seconds(ts):
    try:
        return datetime.fromisoformat(ts).timestamp()
    except (TypeError, ValueError):
        return None


def short(ts):
    return ts.replace("T", " ")[:19] if ts else "?"


def duration(sec):
    if sec is None:
        return "?"
    sec = int(round(sec))
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m{sec % 60:02d}s"
    return f"{sec // 3600}h{(sec % 3600) // 60:02d}m"


def state_badge(state, container_status=None):
    if container_status and container_status != "running":
        return badge(f"{state or '?'} · container {container_status}", "failed")
    cls = {"RUNNING": "running", "REBALANCING": "warn", "ERROR": "failed", "PENDING_ERROR": "failed",
           "PENDING_SHUTDOWN": "paused", "NOT_RUNNING": "paused"}.get(state or "", "paused")
    return badge(state or "?", cls)


def segments(instance):
    """(start, end, state) of the client of an instance over time, and the gaps without logs (state None)"""
    out = []
    clients = instance.get("timeline", [])
    for n_client, client in enumerate(clients):
        events = client["transitions"]
        for k, t in enumerate(events):
            if t.get("restart"):
                # the previous run stopped at its last line, and nothing was logged until the restart
                if out and t.get("previous_last_seen"):
                    start, _, state = out[-1]
                    out[-1] = (start, t["previous_last_seen"], state)
                    out.append((t["previous_last_seen"], t["at"], None))
                continue
            nxt = next((x for x in events[k + 1:]), None)
            if nxt is None:
                # the current run lasts until the end of the logs (a quiet instance logs nothing while RUNNING), an
                # older one until the last line naming it
                current = n_client == len(clients) - 1
                end = (instance.get("timeline_end") if current else None) or client.get("last_seen") or t["at"]
            elif nxt.get("restart"):
                end = nxt.get("previous_last_seen") or nxt["at"]
            else:
                end = nxt["at"]
            out.append((t["at"], end, t["to"]))
    return [(a, b, st) for a, b, st in out if a and b]


def timeline_svg(instances):
    rows = [(i["instance"], segments(i)) for i in instances]
    times = [seconds(x) for _, segs in rows for a, b, _ in segs for x in (a, b)]
    times = [t for t in times if t is not None]
    if not times:
        return ""
    t0, t1 = min(times), max(times)
    span = max(t1 - t0, 1.0)
    label_w, width, row_h, top = 110, 1000, 26, 22
    plot_w = width - label_w - 40
    height = top + row_h * len(rows) + 24

    def x(ts):
        return label_w + (seconds(ts) - t0) / span * plot_w

    parts = [f"<svg viewBox='0 0 {width} {height}' role='img' "
             f"aria-label='state of each Kafka Streams instance over time' font-size='11'>"]
    # 5 ticks on the time axis
    for k in range(6):
        tx = label_w + plot_w * k / 5
        at = datetime.fromtimestamp(t0 + span * k / 5)
        # tenths of a second on a short window, else the 5 ticks would repeat the same second
        label = at.strftime("%H:%M:%S") + (f".{at.microsecond // 100000}" if span < 10 else "")
        parts.append(f"<line x1='{tx:.1f}' y1='{top - 4}' x2='{tx:.1f}' y2='{height - 20}' stroke='#cbd5e1' stroke-dasharray='2,3'/>"
                     f"<text x='{tx:.1f}' y='{height - 6}' text-anchor='middle' fill='#64748b'>{label}</text>")
    for r, (name, segs) in enumerate(rows):
        y = top + r * row_h
        parts.append(f"<text x='{label_w - 8}' y='{y + row_h / 2 + 4:.1f}' text-anchor='end' fill='currentColor'>{e(name)}</text>")
        for a, b, state in segs:
            xa, xb = x(a), x(b)
            w = max(xb - xa, 1.5)
            color = NO_LOGS_COLOR if state is None else STATE_COLORS.get(state, "#94a3b8")
            what = "no log (stopped or killed)" if state is None else state
            tip = f"{what}: {short(a)} → {short(b)} ({duration(seconds(b) - seconds(a))})"
            parts.append(f"<rect x='{xa:.1f}' y='{y + 3}' width='{w:.1f}' height='{row_h - 8}' rx='2' fill='{color}'"
                         + (" stroke='#94a3b8' stroke-dasharray='3,2'" if state is None else "")
                         + f"><title>{e(tip)}</title></rect>")
    parts.append("</svg>")
    used = sorted({st for _, segs in rows for _, _, st in segs if st}, key=lambda s: list(STATE_COLORS).index(s) if s in STATE_COLORS else 99)
    legend = "".join(f"<span><i style='background:{STATE_COLORS.get(s, '#94a3b8')}'></i>{e(s)}</span>" for s in used)
    if any(st is None for _, segs in rows for _, _, st in segs):
        legend += f"<span><i style='background:{NO_LOGS_COLOR};outline:1px dashed #94a3b8'></i>no log (stopped or killed)</span>"
    return f"<div class='st-legend'>{legend}</div><div class='st-timeline'>{''.join(parts)}</div>"


def thread_name(name):
    """StreamThread-1 instead of <application.id>-<process UUID>-StreamThread-1"""
    m = re.search(r"(?:Global)?StreamThread-\d+$", name)
    return m.group(0) if m else name


def task_matrix(app):
    instances = [i["instance"] for i in app["instances"]]
    if not app["tasks"]:
        return ""
    rows = []
    for task, owners in app["tasks"].items():
        cells = [f"<code>{e(task)}</code>"]
        for name in instances:
            if name in owners["active"]:
                cls = "x" if len(owners["active"]) > 1 else "a"
                cells.append(f"<span class='{cls}'>active</span>")
            elif name in owners["standby"]:
                cells.append("<span class='s'>standby</span>")
            else:
                cells.append("<span class='n'>·</span>")
        rows.append(cells)
    html = table(["Task"] + [e(n) for n in instances], rows)
    # the class goes on the cell: rewrite <td><span class='a'>…</span></td> into <td class='a'>…</td>
    for cls in ("a", "s", "x", "n"):
        html = html.replace(f"<td><span class='{cls}'>", f"<td class='{cls}'>")
    html = html.replace("</span></td>", "</td>")
    return f"<div class='st-tasks'>{html}</div>"


def finding_items(app):
    items = []
    for f in app["findings"]:
        sev = "CRITICAL" if f.startswith(("❌", "🛑", "💀")) else "HIGH" if f.startswith(("⚠️", "⏳")) else "MEDIUM"
        items.append({"severity": sev, "text": f})
    for err in app["errors"]:
        items.append({"severity": "HIGH", "text": f"{err['title']} x{err['count']} ({', '.join(err['labels'])}, "
                                                  f"first {short(err['first'])}, last {short(err['last'])})",
                      "details": [err["advice"], err["sample"]]})
    return items


def app_html(app):
    inst = app["instances"]
    running = sum(1 for i in inst if i["state"] == "RUNNING" and i.get("container_status", "running") == "running")
    rebalances = sum(i["rebalances"] for i in inst)
    restored = sum(i["restored_records"] for i in inst)
    errors = sum(err["count"] for err in app["errors"])
    versions = sorted({i["version"] for i in inst if i["version"]})
    group = app.get("consumer_group")
    tiles = [
        kpi("🧩 Instances", len(inst), f"{running} RUNNING", "ok" if inst and running == len(inst) else "danger"),
        kpi("🔀 Rebalances", rebalances, f"{sum(i['rebalancing_seconds'] for i in inst):g}s in REBALANCING"),
        kpi("📋 Tasks", len(app["tasks"]), "assigned"),
        kpi("♻️ Restored", restored, "records from the changelogs"),
        kpi("🔥 Known errors", errors, f"{len(app['errors'])} kind(s)", "danger" if errors else "ok"),
    ]
    if group:
        lag = group.get("lag")
        tiles.append(kpi("👥 Consumer group", group.get("state") or "not found",
                         f"{group.get('members') if group.get('members') is not None else '?'} member(s), lag "
                         f"{lag if lag is not None else '-'}", "ok" if group.get("state") == "Stable" else "warn"))
    rows = []
    for i in inst:
        threads = "<br>".join(f"{e(thread_name(t['name']))} {badge(t['state'] or '?', 'running' if t['state'] == 'RUNNING' else 'warn')}"
                              for t in i["threads"]) or "-"
        not_restored = sorted({t for th in i["threads"] for t in th["not_restored"]})
        restoring = "<br>".join(f"{e(r['changelog'])} (end {r['end_offset']}"
                                + (f", position {r['position']}" if r["position"] is not None else "") + ")" for r in i["restoring"])
        rows.append([e(i["instance"]), state_badge(i["state"], i.get("container_status")), e(short(i["state_since"])),
                     f"{i['rebalances']} ({i['rebalancing_seconds']:g}s)", str(i["restarts"]), threads,
                     e(", ".join(sorted({t for th in i["threads"] for t in th["active"]}))) or "-",
                     e(", ".join(sorted({t for th in i["threads"] for t in th["standby"]}))) or "-",
                     (e(", ".join(not_restored)) or "-") + (f"<br>{restoring}" if restoring else ""),
                     f"{i['restored_records']} / {i['restored_changelogs']}"])
    title = f"🌊 {e(app['application_id'])}" + (f" · Kafka Streams {e(', '.join(versions))}" if versions else "")
    body = [kpis_html(tiles), findings_html(finding_items(app))]
    timeline = timeline_svg(inst)
    if timeline:
        body.append(card("🕐 State of the instances over time", timeline))
    body.append(card("🧩 Instances", table(["Instance", "State", "Since", "Rebalances", "Restarts", "Threads", "Active tasks",
                                           "Standby tasks", "Not restored / restoring", "Restored records / changelogs"], rows, num=(3, 4, 9))))
    matrix = task_matrix(app)
    if matrix:
        body.append(card("📋 Task assignment", matrix))
    return f"<h2 class='section-title'>{title}</h2>" + "".join(body)


def fragment(report):
    return CSS + "".join(app_html(a) for a in report["applications"])


def page_html(report, title):
    apps = report["applications"]
    meta = [e(f"{len(apps)} application(s)"), e(f"{sum(len(a['instances']) for a in apps)} instance(s)")]
    footer = ("From the INFO lines of the Kafka Streams library (State transition, Handle new assignment, Restored and ready "
              "to run, Finished restoring changelog) — tools/streams-analyzer")
    return page(title, "🌊 Kafka Streams status", meta, fragment(report), e(footer))
