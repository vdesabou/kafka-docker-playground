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
const categories = document.querySelectorAll('.category');
const searchInput = document.getElementById('search');

let currentFilter = 'all';
let currentSearch = '';

function applyFilters() {
  categories.forEach(cat => {
    const sev = cat.dataset.severity;
    const text = cat.textContent.toLowerCase();

    const severityMatch =
      currentFilter === 'all' ||
      cat.querySelectorAll(`.issue[data-severity="${currentFilter}"]`).length > 0;

    const searchMatch = !currentSearch || text.includes(currentSearch);

    cat.style.display = (severityMatch && searchMatch) ? '' : 'none';

    if (currentFilter !== 'all') {
      cat.querySelectorAll('.issue').forEach(issue => {
        issue.style.display = (issue.dataset.severity === currentFilter) ? '' : 'none';
      });
    } else {
      cat.querySelectorAll('.issue').forEach(issue => { issue.style.display = ''; });
    }
  });
}

filterButtons.forEach(btn => {
  btn.addEventListener('click', () => {
    filterButtons.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFilter = btn.dataset.filter;
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
      <div class="card"><div class="label">Total issues</div><div class="value">{_esc(summary.get('total_issues', 0))}</div></div>
      <div class="card critical"><div class="label">Critical</div><div class="value">{_esc(summary.get('critical', 0))}</div></div>
      <div class="card high"><div class="label">High</div><div class="value">{_esc(summary.get('high', 0))}</div></div>
      <div class="card medium"><div class="label">Medium</div><div class="value">{_esc(summary.get('medium', 0))}</div></div>
      <div class="card low"><div class="label">Low</div><div class="value">{_esc(summary.get('low', 0))}</div></div>
    </div>
    """

    controls_html = """
    <div class="controls">
      <button class="filter-btn active" data-filter="all">All</button>
      <button class="filter-btn" data-filter="critical">Critical</button>
      <button class="filter-btn" data-filter="high">High</button>
      <button class="filter-btn" data-filter="medium">Medium</button>
      <button class="filter-btn" data-filter="low">Low</button>
      <input id="search" class="search" type="search" placeholder="Search messages, files, categories…" />
    </div>
    """

    if not issues:
        body_html = '<div class="no-issues">No issues detected in this bundle.</div>'
    else:
        cat_blocks = []
        for cat in categories_sorted:
            items = grouped[cat]
            worst = _severity_worst(items)
            rec = recommendations.for_category(cat)

            issue_rows = []
            for issue in items:
                sev = issue.get("severity", "low")
                loc = _esc(issue.get("file", ""))
                if issue.get("line_number"):
                    loc += f":{issue['line_number']}"
                msg = _esc(issue.get("message", ""))
                context = issue.get("context")
                context_block = ""
                if context:
                    context_block = (
                        f'<details><summary>Show context</summary>'
                        f'<pre>{_esc(context)}</pre></details>'
                    )
                issue_rows.append(f"""
                <div class="issue" data-severity="{_esc(sev)}">
                  <div class="head">
                    <span class="severity-pill" style="background:{SEVERITY_BG[sev]};color:{SEVERITY_COLOR[sev]}">{_esc(sev)}</span>
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
                <span class="severity-pill" style="background:{SEVERITY_BG[worst]};color:{SEVERITY_COLOR[worst]}">{_esc(worst)}</span>
                <span class="title">{_esc(cat)}</span>
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

        body_html = "".join(cat_blocks)

    bundle_meta = f"Bundle: {_esc(bundle_label)}" if bundle_label else ""

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
      &nbsp;·&nbsp; Time: {summary.get('analysis_time', 0):.2f}s
      {("&nbsp;·&nbsp; " + bundle_meta) if bundle_meta else ""}
    </div>
  </header>
  <main>
    {summary_html}
    {controls_html}
    {body_html}
  </main>
  <footer>
    Generated by <strong>playground debug cfk-bundle-analyze</strong>
    &nbsp;·&nbsp; Sensitive values are sanitized by default — review before sharing externally.
  </footer>
  <script>{JS}</script>
</body>
</html>
"""
