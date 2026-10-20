"""
Self-contained HTML report generator for the CFK Bundle Analyzer.
No external CDN dependencies — produces a single offline-viewable file.
"""

import html
from collections import defaultdict
from datetime import datetime
from typing import Dict, List

import recommendations


SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3}
SEVERITY_COLOR = {
    "critical": "#b91c1c",
    "high": "#c2410c",
    "medium": "#a16207",
    "low": "#15803d",
}
SEVERITY_BG = {
    "critical": "#fef2f2",
    "high": "#fff7ed",
    "medium": "#fefce8",
    "low": "#f0fdf4",
}
# coloured circle shown before the severity text (badges, filters, tiles)
SEVERITY_EMOJI = {"critical": "🔴", "high": "🟠", "medium": "🟡", "low": "🟢"}

# one emoji per category heading, same concept = same emoji as the other playground reports
CATEGORY_EMOJI = {
    "Pod Failures": "☸️",
    "Pod Status": "☸️",
    "Container Status": "☸️",
    "Init Container Issues": "☸️",
    "Scheduling Issues": "🗓️",
    "Resource Issues": "💾",
    "Image Issues": "🖼️",
    "Certificate/TLS Issues": "🔐",
    "Authentication Issues": "🔑",
    "RBAC Issues": "🛡️",
    "MDS/RBAC Issues": "🛡️",
    "License Issues": "🎫",
    "Network Issues": "🌐",
    "Volume Issues": "📁",
    "Storage Issues": "📁",
    "Health Check Issues": "🩺",
    "Component Status": "🩺",
    "Kubernetes Events": "📣",
    "Kafka Issues": "📨",
    "Replication Issues": "🔁",
    "KRaft Issues": "🗳️",
    "Zookeeper Issues": "🦓",
    "Schema Registry Issues": "🧬",
    "Connect Issues": "🔌",
    "Control Center Issues": "🎛️",
    "REST Proxy Issues": "🔗",
    "KsqlDB Issues": "🧮",
    "Operator Issues": "🤖",
    "Configuration": "⚙️",
    "Finalizer Issues": "🧹",
    "Reconciliation Blocked": "🧊",
    "Application Errors": "🪵",
    "Other Critical (Unclassified)": "🚨",
    "Other Errors (Unclassified)": "❌",
    "Other Failures (Unclassified)": "❌",
    "Other Exceptions (Unclassified)": "🧩",
    "Other Warnings (Unclassified)": "⚠️",
}
DEFAULT_CATEGORY_EMOJI = "🔎"

# component filter buttons, in this order (keys of analyzer.COMPONENTS)
COMPONENT_LABEL = {
    "kafka": "📨 Kafka",
    "kraftcontroller": "🗳️ KRaft",
    "zookeeper": "🦓 ZooKeeper",
    "connect": "🔌 Connect",
    "schemaregistry": "📜 Schema Registry",
    "ksqldb": "🌊 ksqlDB",
    "controlcenter": "🎛️ Control Center",
    "kafkarestproxy": "🌐 REST Proxy",
    "operator": "⚙️ Operator",
    "other": "❔ Other",
}


CSS = """
*, *::before, *::after { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  margin: 0;
  background: #f6f7f9;
  color: #111827;
  line-height: 1.5;
}
header {
  background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
  color: #f9fafb;
  padding: 32px 40px;
  border-bottom: 1px solid #0f172a;
}
header h1 { margin: 0 0 8px 0; font-size: 24px; font-weight: 600; }
header .meta { color: #cbd5e1; font-size: 13px; }
.verdict {
  background: white;
  border: 1px solid #e5e7eb;
  border-left: 4px solid #15803d;
  border-radius: 8px;
  padding: 14px 20px;
  margin-bottom: 24px;
  font-size: 1rem;
  font-weight: 500;
}
.verdict.critical { border-left-color: #b91c1c; }
.verdict.warning  { border-left-color: #c2410c; }
main { max-width: 1180px; margin: 0 auto; padding: 32px 40px 80px 40px; }
.summary {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 16px;
  margin-bottom: 32px;
}
.card {
  background: white;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 18px 20px;
}
.card .label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: #6b7280; margin-bottom: 6px; }
.card .value { font-size: 28px; font-weight: 600; }
.card.critical .value { color: #b91c1c; }
.card.high     .value { color: #c2410c; }
.card.medium   .value { color: #a16207; }
.card.low      .value { color: #15803d; }
.controls {
  display: flex;
  gap: 12px;
  align-items: center;
  margin-bottom: 24px;
  flex-wrap: wrap;
}
.filter-btn {
  background: white;
  border: 1px solid #d1d5db;
  border-radius: 999px;
  padding: 6px 14px;
  font-size: 13px;
  cursor: pointer;
  color: #374151;
  transition: all 0.15s;
}
.filter-btn:hover { border-color: #6b7280; }
.filter-btn.active { background: #111827; color: white; border-color: #111827; }
.search {
  flex: 1;
  min-width: 220px;
  border: 1px solid #d1d5db;
  border-radius: 6px;
  padding: 7px 12px;
  font-size: 13px;
  font-family: inherit;
}
.search:focus { outline: 2px solid #2563eb; outline-offset: -1px; border-color: transparent; }
.controls.components { margin-top: -12px; }
.controls.instances { margin-top: -12px; }
.controls .label { font-size: 12px; color: #6b7280; font-weight: 600; }
.component-btn, .instance-btn {
  background: white;
  border: 1px solid #d1d5db;
  border-radius: 999px;
  padding: 4px 12px;
  font-size: 12.5px;
  cursor: pointer;
  color: #374151;
}
.component-btn:hover, .instance-btn:hover { border-color: #6b7280; }
.component-btn.active, .instance-btn.active { background: #1e3a8a; color: white; border-color: #1e3a8a; }
.component-btn .n, .instance-btn .n { opacity: 0.7; margin-left: 4px; }
.component-tag {
  font-size: 11px;
  background: #eef2ff;
  color: #3730a3;
  padding: 2px 8px;
  border-radius: 4px;
  white-space: nowrap;
}
.no-match { display: none; }
.category {
  background: white;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  margin-bottom: 16px;
  overflow: hidden;
}
.category > summary {
  list-style: none;
  cursor: pointer;
  padding: 16px 20px;
  display: flex;
  align-items: center;
  gap: 12px;
  background: #fafafa;
  border-bottom: 1px solid transparent;
  user-select: none;
}
.category > summary::-webkit-details-marker { display: none; }
.category[open] > summary { border-bottom-color: #e5e7eb; }
.category > summary::before {
  content: "▸";
  font-size: 12px;
  color: #6b7280;
  width: 12px;
  transition: transform 0.15s;
}
.category[open] > summary::before { transform: rotate(90deg); }
.category > summary .title { font-weight: 600; font-size: 15px; flex: 1; }
.severity-pill {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  padding: 3px 8px;
  border-radius: 4px;
}
.count {
  background: #e5e7eb;
  color: #374151;
  font-size: 12px;
  padding: 2px 8px;
  border-radius: 999px;
}
.recommendation {
  padding: 16px 20px 4px 20px;
  background: #f8fafc;
  border-bottom: 1px solid #e5e7eb;
}
.recommendation .why { font-style: italic; color: #4b5563; margin-bottom: 10px; font-size: 14px; }
.recommendation ol { margin: 0 0 12px 20px; padding: 0; }
.recommendation ol li { margin-bottom: 4px; font-size: 13.5px; color: #1f2937; }
.recommendation .docs {
  font-size: 12px;
  color: #2563eb;
  text-decoration: none;
}
.recommendation .docs:hover { text-decoration: underline; }
.issues { padding: 0 20px; }
.issue {
  border-top: 1px solid #f3f4f6;
  padding: 12px 0;
}
.issue:first-child { border-top: none; }
.issue .head {
  display: flex;
  gap: 10px;
  align-items: baseline;
  flex-wrap: wrap;
  margin-bottom: 4px;
}
.issue .location {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 12px;
  color: #6b7280;
}
.issue .message {
  font-size: 13.5px;
  color: #111827;
  white-space: pre-wrap;
  word-break: break-word;
}
.issue details { margin-top: 6px; }
.issue details summary {
  cursor: pointer;
  font-size: 12px;
  color: #2563eb;
  user-select: none;
}
.issue details summary:hover { text-decoration: underline; }
.issue pre {
  background: #0f172a;
  color: #e2e8f0;
  padding: 10px 12px;
  border-radius: 6px;
  font-size: 12px;
  overflow-x: auto;
  margin-top: 8px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}
.no-issues {
  background: white;
  border: 1px solid #d1fae5;
  border-radius: 8px;
  padding: 32px;
  text-align: center;
  color: #047857;
  font-weight: 500;
}
footer {
  text-align: center;
  color: #9ca3af;
  font-size: 12px;
  padding: 24px 0;
}
footer a { color: #6b7280; }
"""


JS = """
const filterButtons = document.querySelectorAll('.filter-btn');
const componentButtons = document.querySelectorAll('.component-btn');
const instanceButtons = document.querySelectorAll('.instance-btn');
const instanceBar = document.querySelector('.controls.instances');
const categories = document.querySelectorAll('.category');
const searchInput = document.getElementById('search');
const noMatch = document.querySelector('.no-match');

let currentFilter = 'all';
let currentComponent = 'all';
let currentInstance = 'all';
let currentSearch = '';

function applyFilters() {
  const counts = { total: 0, critical: 0, high: 0, medium: 0, low: 0 };
  categories.forEach(cat => {
    const title = cat.querySelector('summary .title').textContent.toLowerCase();
    let visible = 0;
    cat.querySelectorAll('.issue').forEach(issue => {
      const inScope =
        (currentComponent === 'all' || issue.dataset.component === currentComponent) &&
        (currentInstance === 'all' || issue.dataset.instance === currentInstance) &&
        (!currentSearch || title.includes(currentSearch) || issue.textContent.toLowerCase().includes(currentSearch));
      const show = inScope && (currentFilter === 'all' || issue.dataset.severity === currentFilter);
      issue.style.display = show ? '' : 'none';
      if (show) visible++;
      // the summary cards count every severity of the selected component / instance / search
      if (inScope) {
        counts.total++;
        counts[issue.dataset.severity]++;
      }
    });
    cat.style.display = visible ? '' : 'none';
    cat.querySelector('summary .count').textContent = visible;
  });
  document.querySelectorAll('.card[data-count]').forEach(card => {
    card.querySelector('.value').textContent = counts[card.dataset.count];
  });
  const anyVisible = [...categories].some(cat => cat.style.display !== 'none');
  if (noMatch) noMatch.style.display = anyVisible ? 'none' : 'block';
}

function activate(buttons, btn) {
  buttons.forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
}

filterButtons.forEach(btn => {
  btn.addEventListener('click', () => {
    activate(filterButtons, btn);
    currentFilter = btn.dataset.filter;
    applyFilters();
  });
});

componentButtons.forEach(btn => {
  btn.addEventListener('click', () => {
    activate(componentButtons, btn);
    currentComponent = btn.dataset.component;
    currentInstance = 'all';
    // instance chips of the selected component only, when it has more than one instance
    let shown = 0;
    instanceButtons.forEach(b => {
      const mine = b.dataset.instance === 'all' || b.dataset.component === currentComponent;
      b.style.display = mine ? '' : 'none';
      b.classList.toggle('active', b.dataset.instance === 'all');
      if (mine && b.dataset.instance !== 'all') shown++;
    });
    if (instanceBar) instanceBar.style.display = (currentComponent !== 'all' && shown > 1) ? '' : 'none';
    applyFilters();
  });
});

instanceButtons.forEach(btn => {
  btn.addEventListener('click', () => {
    activate(instanceButtons, btn);
    currentInstance = btn.dataset.instance;
    applyFilters();
  });
});

if (searchInput) {
  searchInput.addEventListener('input', () => {
    currentSearch = searchInput.value.toLowerCase().trim();
    applyFilters();
  });
}
"""


def _esc(s) -> str:
    if s is None:
        return ""
    return html.escape(str(s), quote=True)


def _severity_worst(issues: List[Dict]) -> str:
    if not issues:
        return "low"
    return min(
        (i.get("severity", "low") for i in issues),
        key=lambda s: SEVERITY_ORDER.get(s, 99),
    )


def _verdict(summary: Dict, categories_sorted: List[str], grouped: Dict[str, List[Dict]]) -> str:
    """One friendly sentence on top of the report, computed from the severity counts."""
    critical = summary.get("critical", 0)
    high = summary.get("high", 0)
    medium = summary.get("medium", 0)
    if critical:
        # categories are sorted worst first: the first one holding a critical issue is where to start
        first = next(
            (c for c in categories_sorted if any(i.get("severity") == "critical" for i in grouped[c])),
            "",
        )
        text = f"🚨 {critical} critical finding{'s' if critical > 1 else ''}"
        if high:
            text += f", {high} high"
        if first:
            text += f": start with {first}."
        else:
            text += "."
        return f'<div class="verdict critical">{_esc(text)}</div>'
    if high or medium:
        n = high + medium
        text = f"⚠️ {n} thing{'s' if n > 1 else ''} to look at, nothing critical."
        return f'<div class="verdict warning">{_esc(text)}</div>'
    return '<div class="verdict">✅ Nothing alarming in this CFK support bundle.</div>'


def _component_controls(issues: List[Dict], summary: Dict) -> str:
    """Component buttons with their issue count, and the instance (CR name) chips of each component"""
    by_component: Dict[str, int] = defaultdict(int)
    by_instance: Dict[tuple, int] = defaultdict(int)
    for i in issues:
        component = i.get("component", "other")
        by_component[component] += 1
        if i.get("instance"):
            by_instance[(component, i["instance"])] += 1
    if not by_component:
        return ""
    ordered = [c for c in COMPONENT_LABEL if by_component.get(c)] + \
              sorted(c for c in by_component if c not in COMPONENT_LABEL)
    buttons = [f'<button class="component-btn active" data-component="all">🧩 All components<span class="n">{len(issues)}</span></button>']
    buttons += [
        f'<button class="component-btn" data-component="{_esc(c)}">{_esc(COMPONENT_LABEL.get(c, c))}<span class="n">{by_component[c]}</span></button>'
        for c in ordered
    ]
    chips = ['<button class="instance-btn active" data-instance="all">All instances</button>']
    chips += [
        f'<button class="instance-btn" data-component="{_esc(c)}" data-instance="{_esc(name)}" style="display:none">{_esc(name)}<span class="n">{n}</span></button>'
        for (c, name), n in sorted(by_instance.items())
    ]
    scope = ""
    if summary.get("components"):
        scope = f' <span class="label">(report limited to --component {_esc(" ".join(summary["components"]))})</span>'
    return (
        f'<div class="controls components"><span class="label">Component</span>{"".join(buttons)}{scope}</div>'
        f'<div class="controls instances" style="display:none"><span class="label">Instance</span>{"".join(chips)}</div>'
    )


def render(results: Dict, bundle_label: str = "") -> str:
    summary = results.get("summary", {})
    issues = results.get("issues", [])

    grouped: Dict[str, List[Dict]] = defaultdict(list)
    for i in issues:
        grouped[i.get("category", "Uncategorized")].append(i)

    categories_sorted = sorted(
        grouped.keys(),
        key=lambda c: SEVERITY_ORDER.get(_severity_worst(grouped[c]), 99),
    )

    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S %Z").strip()

    summary_html = f"""
    <div class="summary">
      <div class="card" data-count="total"><div class="label">🔎 Total issues</div><div class="value">{_esc(summary.get('total_issues', 0))}</div></div>
      <div class="card critical" data-count="critical"><div class="label">{SEVERITY_EMOJI['critical']} Critical</div><div class="value">{_esc(summary.get('critical', 0))}</div></div>
      <div class="card high" data-count="high"><div class="label">{SEVERITY_EMOJI['high']} High</div><div class="value">{_esc(summary.get('high', 0))}</div></div>
      <div class="card medium" data-count="medium"><div class="label">{SEVERITY_EMOJI['medium']} Medium</div><div class="value">{_esc(summary.get('medium', 0))}</div></div>
      <div class="card low" data-count="low"><div class="label">{SEVERITY_EMOJI['low']} Low</div><div class="value">{_esc(summary.get('low', 0))}</div></div>
    </div>
    """

    controls_html = f"""
    <div class="controls">
      <button class="filter-btn active" data-filter="all">📋 All</button>
      <button class="filter-btn" data-filter="critical">{SEVERITY_EMOJI['critical']} Critical</button>
      <button class="filter-btn" data-filter="high">{SEVERITY_EMOJI['high']} High</button>
      <button class="filter-btn" data-filter="medium">{SEVERITY_EMOJI['medium']} Medium</button>
      <button class="filter-btn" data-filter="low">{SEVERITY_EMOJI['low']} Low</button>
      <input id="search" class="search" type="search" placeholder="Search messages, files, categories, pods…" />
    </div>
    {_component_controls(issues, summary)}
    """

    if not issues:
        body_html = '<div class="no-issues">🎉 No issues detected in the scanned files (see coverage above).</div>'
    else:
        cat_blocks = []
        for cat in categories_sorted:
            items = grouped[cat]
            worst = _severity_worst(items)
            rec = recommendations.for_category(cat)

            issue_rows = []
            for issue in items:
                sev = issue.get("severity", "low")
                component = issue.get("component", "other")
                instance = issue.get("instance", "")
                tag = COMPONENT_LABEL.get(component, component) + (f" · {instance}" if instance else "")
                loc = _esc(issue.get("file", ""))
                if issue.get("line_number"):
                    loc += f":{issue['line_number']}"
                if issue.get("count", 1) > 1:
                    loc += f" &nbsp;×{_esc(issue['count'])}"
                msg = _esc(issue.get("message", ""))
                for cause in issue.get("caused_by") or []:
                    msg += f"<br>&nbsp;&nbsp;↳ Caused by: {_esc(cause)}"
                context = issue.get("context")
                context_block = ""
                if context:
                    context_block = (
                        f'<details><summary>📋 Show context</summary>'
                        f'<pre>{_esc(context)}</pre></details>'
                    )
                issue_rows.append(f"""
                <div class="issue" data-severity="{_esc(sev)}" data-component="{_esc(component)}" data-instance="{_esc(instance)}">
                  <div class="head">
                    <span class="severity-pill" style="background:{SEVERITY_BG[sev]};color:{SEVERITY_COLOR[sev]}">{SEVERITY_EMOJI.get(sev, "")} {_esc(sev)}</span>
                    <span class="component-tag">{_esc(tag)}</span>
                    <span class="location">{loc}</span>
                  </div>
                  <div class="message">{msg}</div>
                  {context_block}
                </div>
                """)

            rec_steps = "".join(f"<li>{_esc(step)}</li>" for step in rec.get("steps", []))
            docs_link = ""
            if rec.get("docs"):
                docs_link = f'<a class="docs" href="{_esc(rec["docs"])}" target="_blank" rel="noopener">📘 Docs reference</a>'

            cat_blocks.append(f"""
            <details class="category" data-severity="{_esc(worst)}" open>
              <summary>
                <span class="severity-pill" style="background:{SEVERITY_BG[worst]};color:{SEVERITY_COLOR[worst]}">{SEVERITY_EMOJI.get(worst, "")} {_esc(worst)}</span>
                <span class="title">{CATEGORY_EMOJI.get(cat, DEFAULT_CATEGORY_EMOJI)} {_esc(cat)}</span>
                <span class="count">{len(items)}</span>
              </summary>
              <div class="recommendation">
                <div class="why">{_esc(rec.get("summary", ""))}</div>
                <ol>{rec_steps}</ol>
                {docs_link}
              </div>
              <div class="issues">
                {"".join(issue_rows)}
              </div>
            </details>
            """)

        body_html = "".join(cat_blocks) + '<div class="no-issues no-match">No issue matches these filters.</div>'

    verdict_html = _verdict(summary, categories_sorted, grouped)

    bundle_meta = f"Bundle: {_esc(bundle_label)}" if bundle_label else ""
    coverage = results.get("coverage") or {}
    coverage_meta = ""
    if coverage:
        coverage_meta = (
            f"&nbsp;·&nbsp; {_esc(coverage.get('pods', 0))} pods, {_esc(coverage.get('custom_resources', 0))} CFK CRs, "
            f"{_esc(coverage.get('events', 0))} events, {_esc(coverage.get('log_files', 0))} log files "
            f"({_esc(coverage.get('log_lines', 0))} lines)"
        )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>CFK Bundle Analysis Report</title>
  <style>{CSS}</style>
</head>
<body>
  <header>
    <h1>📦 CFK Bundle Analysis Report</h1>
    <div class="meta">
      Generated {_esc(generated_at)}
      &nbsp;·&nbsp; Files analyzed: {_esc(summary.get('files_analyzed', 0))}
      {coverage_meta}
      &nbsp;·&nbsp; Time: {summary.get('analysis_time', 0):.2f}s
      {("&nbsp;·&nbsp; " + bundle_meta) if bundle_meta else ""}
    </div>
  </header>
  <main>
    {verdict_html}
    {summary_html}
    {controls_html}
    {body_html}
  </main>
  <footer>
    🛠️ Generated by <strong>playground analyze cfk-bundle</strong>
    &nbsp;·&nbsp; Sensitive values are sanitized by default (best effort) — review before sharing externally.
  </footer>
  <script>{JS}</script>
</body>
</html>
"""
