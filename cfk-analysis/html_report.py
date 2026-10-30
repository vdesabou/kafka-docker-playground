"""
Self-contained HTML report generator for the CFK Bundle Analyzer.
No external CDN dependencies — produces a single offline-viewable file.
"""

import html
import os
import sys
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Tuple

import recommendations

# the light / dark theme and "Toggle theme" button shared with the other playground reports
# (tools/report-common/report_html.py, mounted in /tmp/report-common by playground analyze cfk-bundle); without it, the
# report stays light only. No __pycache__ left in the repository.
sys.dont_write_bytecode = True
for _path in (os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "report-common"), "/tmp/report-common"):
    if os.path.isfile(os.path.join(_path, "report_html.py")):
        sys.path.insert(0, _path)
        break
try:
    import report_html
except ImportError:
    report_html = None


SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3}
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
    "KRaft Migration": "🚚",
    "Rollout Issues": "🔄",
    "Bundle Coverage": "🕰️",
    "Recent Changes": "🕒",
    "Plugin Issues": "🧩",
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
    "JVM Truststore Issues": "🔐",
    "Compatibility": "🧭",
    "Application Errors": "🪵",
    "Other Critical (Unclassified)": "🚨",
    "Other Errors (Unclassified)": "❌",
    "Other Failures (Unclassified)": "❌",
    "Other Exceptions (Unclassified)": "🧩",
    "Other Warnings (Unclassified)": "⚠️",
}
DEFAULT_CATEGORY_EMOJI = "🔎"

# value of the connector filter for the issues without a connector context
NO_CONNECTOR = "-"

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
  background: linear-gradient(135deg, #1e3a5f 0%, #2563eb 100%);
  color: #fff;
  padding: 32px 40px;
}
header h1 { margin: 0 0 8px 0; font-size: 24px; font-weight: 600; }
header .meta { color: #fff; opacity: .85; font-size: 13px; }
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
.controls.connectors { margin-top: -12px; }
.connector-filter { font-family: inherit; font-size: 13px; max-width: 420px; padding: 4px 6px; border-radius: 6px; border: 1px solid #d1d5db; background: white; }
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
.severity-pill.critical { background: #fef2f2; color: #b91c1c; }
.severity-pill.high { background: #fff7ed; color: #c2410c; }
.severity-pill.medium { background: #fefce8; color: #a16207; }
.severity-pill.low { background: #f0fdf4; color: #15803d; }
.count {
  background: #e5e7eb;
  color: #374151;
  font-size: 12px;
  padding: 2px 8px;
  border-radius: 999px;
}
.panel {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  margin-bottom: 16px;
  padding: 12px 20px;
}
.panel > summary { cursor: pointer; font-weight: 600; font-size: 15px; }
.panel .label { font-weight: 400; color: #6b7280; font-size: 12px; margin-left: 8px; }
.panel .facts { margin: 10px 0; font-size: 14px; }
table.env { border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 12.5px; }
table.env th { text-align: left; color: #6b7280; font-weight: 600; border-bottom: 1px solid #e5e7eb; padding: 4px 8px; }
table.env td { border-bottom: 1px solid #f3f4f6; padding: 4px 8px; vertical-align: top; word-break: break-all; }
table.env td.nowrap { white-space: nowrap; word-break: normal; }
.panel details.cfg { margin: 6px 0; border: 1px solid #e5e7eb; border-radius: 6px; padding: 6px 10px; }
.panel details.cfg > summary { cursor: pointer; font-size: 13.5px; }
.panel details.cfg pre { max-height: 420px; overflow: auto; }
.panel h3 { font-size: 14px; margin: 14px 0 4px; }
.panel .cfg-search { margin: 8px 0; width: 100%; max-width: 420px; }
table.cfg td:first-child { width: 34%; }
.affected { margin-top: 4px; font-size: 12.5px; }
.affected > summary { cursor: pointer; color: #4b5563; }
.recommendation {
  padding: 16px 20px 4px 20px;
  background: #f8fafc;
  border-bottom: 1px solid #e5e7eb;
}
.recommendation .why { font-style: italic; color: #4b5563; margin-bottom: 10px; font-size: 14px; }
.recommendation ol { margin: 0 0 12px 20px; padding: 0; }
.next-steps { margin-top: 8px; padding: 8px 12px; border-left: 3px solid #2563eb; background: #eff6ff; border-radius: 4px; font-size: 13px; }
.next-steps ol { margin: 4px 0 6px 20px; padding: 0; }
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
.issue .location a.file-link {
  color: inherit;
  text-decoration: underline dotted;
}
.issue .location a.file-link:hover {
  color: #2563eb;
  text-decoration: underline;
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


# the dark theme of CSS (same palette as the other reports)
DARK_CSS = """
body{background:#0f172a;color:#e2e8f0}
.verdict,.card,.category,.panel{background:#1e293b;border-color:#334155}
.card .label,.panel .label,.controls .label,.issue .location,footer,footer a,.category > summary::before{color:#94a3b8}
.issue .location a.file-link:hover{color:#93c5fd}
.card.critical .value{color:#fca5a5}.card.high .value{color:#fdba74}.card.medium .value{color:#fcd34d}.card.low .value{color:#86efac}
.filter-btn,.component-btn,.instance-btn,.search,.connector-filter{background:#1e293b;border-color:#334155;color:#cbd5e1}
.filter-btn:hover,.component-btn:hover,.instance-btn:hover{border-color:#94a3b8}
.filter-btn.active{background:#e2e8f0;color:#0f172a;border-color:#e2e8f0}
.component-btn.active,.instance-btn.active{background:#2563eb;color:#fff;border-color:#2563eb}
.component-tag{background:#172554;color:#93c5fd}
.category > summary{background:#273449}
.category[open] > summary{border-bottom-color:#334155}
.count{background:#334155;color:#cbd5e1}
table.env th{color:#94a3b8;border-bottom-color:#334155}
table.env td{border-bottom-color:#273449}
.panel details.cfg{border-color:#334155}
.affected > summary,.recommendation .why{color:#94a3b8}
.recommendation{background:#172033;border-bottom-color:#334155}
.recommendation ol li,.issue .message{color:#e2e8f0}
.next-steps{background:#172554;border-left-color:#60a5fa}
.recommendation .docs,.issue details summary,a{color:#93c5fd}
.issue{border-top-color:#273449}
.issue pre{background:#0b1220}
.no-issues{background:#1e293b;border-color:#14532d;color:#86efac}
.severity-pill.critical{background:#450a0a;color:#fca5a5}.severity-pill.high{background:#431407;color:#fdba74}
.severity-pill.medium{background:#422006;color:#fcd34d}.severity-pill.low{background:#052e16;color:#86efac}
"""


def _theme() -> str:
    """the dark rules, the "Toggle theme" button and its script, when the shared report module is there"""
    if report_html is None:
        return f"<style>{CSS}</style>"
    return (f"<style>{CSS}{report_html.LOG_CSS}{report_html.dark(DARK_CSS)}{report_html.THEME_TOGGLE_CSS}</style>"
            f"{report_html.THEME_SCRIPT}")


JS = """
const filterButtons = document.querySelectorAll('.filter-btn');
const componentButtons = document.querySelectorAll('.component-btn');
const instanceButtons = document.querySelectorAll('.instance-btn');
const instanceBar = document.querySelector('.controls.instances');
const categories = document.querySelectorAll('.category');
const searchInput = document.getElementById('search');
const connectorSelect = document.getElementById('connector-filter');
const noMatch = document.querySelector('.no-match');

let currentFilter = 'all';
let currentComponent = 'all';
let currentInstance = 'all';
let currentSearch = '';
let currentConnector = 'all';

// connector options of the selected component / instance / search only, with their issue count there
function updateConnectorOptions(byConnector) {
  if (!connectorSelect) return;
  let names = 0;
  connectorSelect.querySelectorAll('option').forEach(opt => {
    if (opt.value === 'all') return;
    const n = byConnector[opt.value] || 0;
    opt.textContent = (opt.value === '-' ? '— no connector context —' : opt.value) + ` (${n})`;
    // disabled too: Safari ignores hidden on an option
    opt.hidden = opt.disabled = n === 0 && opt.value !== currentConnector;
    if (n && opt.value !== '-') names++;
  });
  connectorSelect.querySelector('option[value="all"]').textContent =
    `All (${names} connector(s)${byConnector['-'] ? ' + no connector' : ''})`;
}

function applyFilters() {
  const counts = { total: 0, critical: 0, high: 0, medium: 0, low: 0 };
  const byConnector = {};
  categories.forEach(cat => {
    const title = cat.querySelector('summary .title').textContent.toLowerCase();
    let visible = 0;
    cat.querySelectorAll('.issue').forEach(issue => {
      const connectors = issue.dataset.connectors.split(' ');
      const inContext =
        (currentComponent === 'all' || issue.dataset.component === currentComponent) &&
        (currentInstance === 'all' || issue.dataset.instance === currentInstance) &&
        (!currentSearch || title.includes(currentSearch) || issue.textContent.toLowerCase().includes(currentSearch));
      if (inContext) connectors.forEach(c => { byConnector[c] = (byConnector[c] || 0) + 1; });
      const inScope = inContext && (currentConnector === 'all' || connectors.includes(currentConnector));
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
  updateConnectorOptions(byConnector);
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

if (connectorSelect) {
  connectorSelect.addEventListener('change', () => {
    currentConnector = connectorSelect.value;
    applyFilters();
  });
}

if (searchInput) {
  searchInput.addEventListener('input', () => {
    currentSearch = searchInput.value.toLowerCase().trim();
    applyFilters();
  });
}

// ⚙️ Configuration: keys / values filter, opens the blocks with a match
document.querySelectorAll('.cfg-search').forEach(input => {
  input.addEventListener('input', () => {
    const q = input.value.toLowerCase().trim();
    const panel = input.closest('.panel');
    panel.querySelectorAll('tr.cfg-row').forEach(tr => { tr.hidden = q !== '' && !tr.textContent.toLowerCase().includes(q); });
    panel.querySelectorAll('details.cfg').forEach(d => {
      if (q) d.open = !!d.querySelector('tr.cfg-row:not([hidden])') || d.querySelector('summary').textContent.toLowerCase().includes(q);
    });
  });
});
// the connector picked in the issues filter: its config opens
if (connectorSelect) {
  connectorSelect.addEventListener('change', () => {
    document.querySelectorAll('details.cfg[data-connector]').forEach(d => { d.open = d.dataset.connector === connectorSelect.value; });
  });
}
"""


def _esc(s) -> str:
    if s is None:
        return ""
    return html.escape(str(s), quote=True)


def _log(s) -> str:
    """Log text with the colors of the other playground reports (timestamp, level, exception…), plain without them"""
    return report_html.log_html(s) if report_html is not None else _esc(s)


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


def _connector_controls(issues: List[Dict]) -> str:
    """Connector picker with the issue count of each connector, when log records have a Connect connector context"""
    by_connector: Dict[str, int] = defaultdict(int)
    for i in issues:
        for name in i.get("connectors") or []:
            by_connector[name] += 1
    if not by_connector:
        return ""
    without = sum(1 for i in issues if not i.get("connectors"))
    options = [f'<option value="all">All ({len(by_connector)} connector(s){" + no connector" if without else ""})</option>']
    options += [f'<option value="{_esc(name)}">{_esc(name)} ({n})</option>'
                for name, n in sorted(by_connector.items(), key=lambda kv: (-kv[1], kv[0]))]
    if without:
        options.append(f'<option value="{NO_CONNECTOR}">— no connector context — ({without})</option>')
    return (f'<div class="controls connectors"><span class="label">Connector</span>'
            f'<select id="connector-filter" class="connector-filter" title="only the issues of this connector '
            f'([connector|task-0] context of the log record)">{"".join(options)}</select></div>')


def _environment_html(results: Dict, timeline_limit: int = 40) -> str:
    """Versions / images table and the latest changes, both collapsible"""
    env = results.get("environment") or {}
    components = env.get("components") or {}
    blocks = []
    if env.get("kubernetes_version") or env.get("cfk_version") or components:
        facts = []
        if env.get("kubernetes_version"):
            facts.append(f"☸️ Kubernetes <strong>{_esc(env['kubernetes_version'])}</strong>")
        if env.get("cfk_version") or env.get("operator_image_tag"):
            facts.append(f"🤖 CFK operator <strong>{_esc(env.get('cfk_version', '?'))}</strong> "
                         f"(image tag {_esc(env.get('operator_image_tag', '?'))})")
        rows = "".join(
            f"<tr><td>{_esc(name)}</td><td><code>{_esc(info.get('image', ''))}</code></td>"
            f"<td><code>{_esc(info.get('init_image', ''))}</code></td></tr>"
            for name, info in sorted(components.items())
        )
        table = (f'<table class="env"><tr><th>Component</th><th>Application image</th><th>Init image</th></tr>{rows}</table>'
                 if rows else "")
        blocks.append(f"""
        <details class="panel" open>
          <summary>🧭 Environment</summary>
          <div class="facts">{" &nbsp;·&nbsp; ".join(facts)}</div>
          {table}
        </details>""")
    timeline = results.get("timeline") or []
    if timeline:
        rows = "".join(
            f"<tr><td class=\"nowrap\">{_esc(c['time'])}</td><td>{_esc(c['kind'])}/{_esc(c['name'])}</td>"
            f"<td>{_esc(c['what'])}" + (f" <strong>⚠️ {_esc(c['before_failure'])}</strong>" if c.get('before_failure') else "")
            + "</td></tr>"
            for c in timeline[:timeline_limit]
        )
        blocks.append(f"""
        <details class="panel" open>
          <summary>🕒 Recent changes <span class="label">newest first, {min(len(timeline), timeline_limit)} of {len(timeline)}: managedFields of the CRs / StatefulSets, pod (re)starts</span></summary>
          <table class="env"><tr><th>Time (UTC)</th><th>Object</th><th>Change</th></tr>{rows}</table>
        </details>""")
    return "".join(blocks)


def _runbooks_html(results: Dict) -> str:
    """Known CFK issues matched in the bundle (runbooks.py): what they mean, public KB / docs links"""
    hits = results.get("runbooks") or []
    if not hits:
        return ""
    rows = []
    for hit in hits:
        example = hit.get("example") or {}
        where = example.get("file", "") + (f":{example['line_number']}" if example.get("line_number") else "")
        links = " · ".join([f'<a href="{_esc(l["url"])}" target="_blank" rel="noopener">📘 {_esc(l.get("title") or l["url"])}</a>'
                            for l in hit.get("links") or []] +
                           [f'<a href="{_esc(l["url"])}" target="_blank" rel="noopener" title="internal runbook of Confluent support">'
                            f'🔒 {_esc(l.get("title") or l["url"])}</a>' for l in hit.get("internal_links") or []])
        rows.append(f"<tr><td class=\"nowrap\"><span class=\"severity-pill {_esc(hit['severity'])}\">"
                    f"{SEVERITY_EMOJI.get(hit['severity'], '')} {_esc(hit['severity'])}</span></td>"
                    f"<td><strong>{_esc(hit['title'])}</strong><br>{_esc(hit['advice'])}"
                    f"{'<br>' + links if links else ''}</td>"
                    f"<td>{_esc(hit['issues'])} issue(s), ×{_esc(hit['occurrences'])}<br><code>{_esc(where)}</code></td></tr>")
    return f"""
        <details class="panel" open>
          <summary>📕 Known CFK issues <span class="label">{len(hits)} matched: log messages and events of known CFK problems, read the runbook before digging further</span></summary>
          <table class="env"><tr><th>Severity</th><th>Known issue</th><th>Seen in</th></tr>{"".join(rows)}</table>
        </details>"""


def _log_coverage_html(results: Dict) -> str:
    """Time range of each log of the bundle, with the start of its pod when the bundle has its manifest"""
    windows = (results.get("coverage") or {}).get("log_windows") or []
    if not windows:
        return ""
    rows = "".join(
        f"<tr><td><code>{_esc(w['file'])}</code></td><td class=\"nowrap\">{_esc(w['first'])}</td>"
        f"<td class=\"nowrap\">{_esc(w['last'])}</td><td class=\"nowrap\">{_esc(w.get('span') or '')}</td>"
        f"<td class=\"nowrap\">{_esc(w.get('pod_started') or '')}</td></tr>"
        for w in windows)
    return f"""
        <details class="panel">
          <summary>🕰️ Log coverage <span class="label">{len(windows)} log files, from {_esc(min(w['first'] for w in windows))} to {_esc(max(w['last'] for w in windows))}: what happened outside these ranges is not in the bundle</span></summary>
          <table class="env"><tr><th>Log</th><th>From</th><th>To</th><th>Covers</th><th>Pod started</th></tr>{rows}</table>
        </details>"""


def _properties_table(text: str) -> Tuple[str, int]:
    """key=value lines as a table (comments and blank lines left out), with the number of keys"""
    rows = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line or line.startswith(("#", "!")):
            continue
        key, _, value = line.partition("=")
        rows.append(f'<tr class="cfg-row"><td><code>{_esc(key.strip())}</code></td><td><code>{_esc(value.strip())}</code></td></tr>')
    return f'<table class="env cfg"><tr><th>Key</th><th>Value</th></tr>{"".join(rows)}</table>', len(rows)


def _dump_where(dump: Dict) -> str:
    where = dump.get("file", "")
    if dump.get("line"):
        where += f":{dump['line']}"
    if dump.get("time"):
        where += f" ({dump['time'].replace('T', ' ')})"
    return where


# components of the ⚙️ Configuration section: title, main properties file rendered by CFK, what the log dump holds
CONFIG_COMPONENTS = (
    ("kafka", "🧱 Kafka", "kafka.properties"),
    ("zookeeper", "🦓 ZooKeeper", "zookeeper.properties"),
    ("schemaregistry", "📜 Schema Registry", "schemaregistry.properties"),
    ("connect", "🔌 Connect", "connect.properties"),
    ("controlcenter", "🎛️ Control Center", "controlcenter.properties"),
)


def _component_config_html(name: str, config: Dict, main: str) -> str:
    """One CR: main properties file of its ConfigMap, configOverrides, other ConfigMap files, config dumps of the logs"""
    files = config.get("files") or {}
    inner = []
    nb_keys = 0
    if files.get(main):
        table, nb_keys = _properties_table(files[main])
        inner.append(f'<div class="label">{_esc(main)} rendered by CFK, from {_esc(config.get("source", ""))}</div>{table}')
    for key, text in (config.get("overrides") or {}).items():
        if key == "server":
            table, n = _properties_table(text)
            inner.append(f'<details class="cfg"><summary>✏️ configOverrides.server of the CR ({n} keys, already in {_esc(main)} above)</summary>{table}</details>')
        else:
            inner.append(f'<details class="cfg"><summary>✏️ configOverrides.{_esc(key)} of the CR</summary><pre>{_esc(text)}</pre></details>')
    for fname in ("jvm.config", "log4j.properties", "plugins.json"):
        if files.get(fname):
            inner.append(f'<details class="cfg"><summary>📄 {_esc(fname)}</summary><pre>{_esc(files[fname])}</pre></details>')
    for dump in config.get("dumps") or []:
        table, n = _properties_table(dump.get("text", ""))
        inner.append(f'<details class="cfg"><summary>🪵 {_esc(dump.get("title", ""))} logged at startup, with the defaults ({n} keys) · '
                     f'{_esc(_dump_where(dump))}</summary>{table}</details>')
    what = f"{main}, {nb_keys} keys" if nb_keys else "no ConfigMap in the bundle"
    return (f'<details class="cfg"><summary><strong>{_esc(name)}</strong> <span class="label">{_esc(what)}</span></summary>'
            f'{"".join(inner)}</details>')


def _configuration_html(results: Dict) -> str:
    """Kafka, ZooKeeper, Schema Registry, Connect and Control Center CRs (ConfigMap rendered by CFK, configOverrides of the CR, config dumps of the
    logs) and connectors (Connector CRs, config dumps of the Connect logs), one collapsible block each"""
    config = results.get("configuration") or {}
    components = config.get("components") or {}
    connectors = config.get("connectors") or {}
    if not any(components.values()) and not connectors:
        return ""
    blocks = []
    for kind, title, main in CONFIG_COMPONENTS:
        crs = components.get(kind) or {}
        if crs:
            blocks.append(f"<h3>{title} ({len(crs)})</h3>")
            blocks += [_component_config_html(name, crs[name], main) for name in sorted(crs)]
    blocks.append(f"<h3>🧩 Connectors ({len(connectors)})</h3>")
    if not connectors:
        blocks.append('<div class="label">No connector config in this bundle: no Connector CR, and no "…ConnectorConfig values:" '
                      'dump in the Connect logs (logged when a connector starts, so missing when the logs begin later). Ask for '
                      'the output of <code>curl -s http://&lt;connect&gt;:8083/connectors?expand=info</code> (configs) and '
                      '<code>?expand=status</code>.</div>')
    for name, conn in sorted(connectors.items()):
        sources = ([conn["cr"]] if conn.get("cr") else []) + list((conn.get("dumps") or {}).values())
        inner = []
        for src in sources:
            table, n = _properties_table(src.get("text", ""))
            inner.append(f'<div class="label">{_esc(src.get("title", ""))} ({n} keys) · {_esc(_dump_where(src))}</div>{table}')
        facts = " · ".join(_esc(x) for x in (conn.get("class", "").split(".")[-1], conn.get("cluster"), conn.get("state")) if x)
        blocks.append(f'<details class="cfg" data-connector="{_esc(name)}"><summary>🧩 <strong>{_esc(name)}</strong> '
                      f'<span class="label">{facts}</span></summary>{"".join(inner)}</details>')
    return f"""
        <details class="panel" open>
          <summary>⚙️ Configuration <span class="label">Kafka, ZooKeeper, Schema Registry, Connect, Control Center: properties rendered by CFK (ConfigMap &lt;cr&gt;-shared-config), configOverrides of the CR, config logged at startup · connectors: Connector CRs, config logged when they start</span></summary>
          <input class="search cfg-search" type="search" placeholder="Filter keys and values…" />
          {"".join(blocks)}
        </details>"""


def render(results: Dict, bundle_label: str = "") -> str:
    summary = results.get("summary", {})
    issues = results.get("issues", [])

    runbook_titles = {h["name"]: h["title"] for h in results.get("runbooks") or []}
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
    {_connector_controls(issues)}
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
                # a copy of the file next to the report (tools/report-common/log_viewer.py), at the line
                if issue.get("viewer"):
                    loc = (f'<a class="file-link" href="{_esc(issue["viewer"])}" target="_blank" rel="noopener" '
                           f'title="open the file{" at this line" if issue.get("line_number") else ""}">{loc}</a>')
                if issue.get("count", 1) > 1:
                    loc += f" &nbsp;×{_esc(issue['count'])}"
                msg = _log(issue.get("message", ""))
                for cause in issue.get("caused_by") or []:
                    msg += f"<br>&nbsp;&nbsp;↳ {_log('Caused by: ' + cause)}"
                for name in issue.get("runbooks") or []:
                    msg += f"<br>&nbsp;&nbsp;📕 Known CFK issue: <strong>{_esc(runbook_titles.get(name, name))}</strong>"
                if issue.get("next_steps"):
                    msg += ('<div class="next-steps"><strong>🧭 Next steps</strong><ol>'
                            + "".join(f"<li>{_esc(step)}</li>" for step in issue["next_steps"]) + "</ol>"
                            + " · ".join(f'<a href="{_esc(u)}" target="_blank" rel="noopener">📘 {_esc(u.rsplit("/", 1)[-1])}</a>'
                                         for u in issue.get("docs") or []) + "</div>")
                affected = issue.get("affected") or []
                if len(affected) > 1 or (affected and issue.get("count", 1) > 1):
                    msg += (f'<details class="affected"><summary>🔌 Affects {len(affected)} task(s)</summary>'
                            f'<pre>{_esc(chr(10).join(affected))}</pre></details>')
                context = issue.get("context")
                context_block = ""
                if context:
                    context_block = (
                        f'<details><summary>📋 Show context</summary>'
                        f'<pre>{_log(context)}</pre></details>'
                    )
                issue_rows.append(f"""
                <div class="issue" data-severity="{_esc(sev)}" data-component="{_esc(component)}" data-instance="{_esc(instance)}" data-connectors="{_esc(" ".join(issue.get("connectors") or [NO_CONNECTOR]))}">
                  <div class="head">
                    <span class="severity-pill {_esc(sev)}">{SEVERITY_EMOJI.get(sev, "")} {_esc(sev)}</span>
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
                <span class="severity-pill {_esc(worst)}">{SEVERITY_EMOJI.get(worst, "")} {_esc(worst)}</span>
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
    viewer_folder = next((i["viewer"].split("/")[0] for i in issues if i.get("viewer")), "")

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
  {_theme()}
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
    {_runbooks_html(results)}
    {_environment_html(results)}
    {_log_coverage_html(results)}
    {_configuration_html(results)}
    {controls_html}
    {body_html}
  </main>
  <footer>
    🛠️ Generated by <strong>playground analyze cfk-bundle</strong>
    &nbsp;·&nbsp; Sensitive values are sanitized by default (best effort) — review before sharing externally.
    {("&nbsp;·&nbsp; The file locations open a copy of the file in " + _esc(viewer_folder) + "/: keep that folder with the report.") if viewer_folder else ""}
  </footer>
  <script>{JS}</script>
</body>
</html>
"""
