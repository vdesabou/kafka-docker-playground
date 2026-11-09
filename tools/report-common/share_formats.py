"""📤 the summary for a ticket (the Markdown of ticket_markdown() in log_report.py, already sanitized) in the other formats of
the Share dialog: text to paste in Slack (its message box keeps *bold* and `code`, not tables: a row becomes a bullet) and HTML with inline styles (copied as rich
text, it pastes formatted in Zendesk, Gmail, Confluence or Google Docs, which drop the classes of a page).

Only the Markdown that ticket_markdown() writes: ## / ### headings, **bold**, _italic_, `code`, [text](url), tables
(cells escaped with \\|), "- " bullets and "  - " sub-bullets, paragraphs."""

import html
import re
from typing import List

_CELL_SPLIT = re.compile(r"(?<!\\)\|")
_LINK = re.compile(r"\[([^\]]+)\]\((https?://[^)\s]+)\)")
_BOLD = re.compile(r"\*\*(.+?)\*\*")
_ITALIC = re.compile(r"(?<![\w*])_(.+?)_(?!\w)")


def _cells(line: str) -> List[str]:
    inner = line.strip()
    if inner.startswith("|"):
        inner = inner[1:]
    if inner.endswith("|") and not inner.endswith("\\|"):
        inner = inner[:-1]
    return [c.strip().replace("\\|", "|") for c in _CELL_SPLIT.split(inner)]


def _blocks(md: str):
    """("h2" | "h3", text), ("table", header, rows), ("ul", [(level, text)]), ("p", [lines])"""
    lines = md.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("### "):
            yield ("h3", line[4:].strip())
            i += 1
        elif line.startswith("## "):
            yield ("h2", line[3:].strip())
            i += 1
        elif line.lstrip().startswith("|"):
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                rows.append(_cells(lines[i]))
                i += 1
            header = rows[0]
            body = [r for r in rows[1:] if not all(re.fullmatch(r":?-{3,}:?", c) for c in r if c)]
            yield ("table", header, body)
        elif re.match(r"^\s*- ", line):
            items = []
            while i < len(lines) and re.match(r"^\s*- ", lines[i]):
                indent = len(lines[i]) - len(lines[i].lstrip())
                items.append((1 if indent >= 2 else 0, lines[i].lstrip()[2:]))
                i += 1
            yield ("ul", items)
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not lines[i].startswith("#") and not lines[i].lstrip().startswith("|") \
                    and not re.match(r"^\s*- ", lines[i]):
                para.append(lines[i])
                i += 1
            yield ("p", para)


# ── HTML ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
_CODE_STYLE = "font-family:Menlo,Consolas,monospace;font-size:12px;background:#f3f4f6;padding:1px 4px;border-radius:3px"
_TH = "border:1px solid #d1d5db;padding:4px 8px;background:#f3f4f6;text-align:left;font-weight:600"
_TD = "border:1px solid #d1d5db;padding:4px 8px;vertical-align:top"


def _inline_html(text: str) -> str:
    out = []
    for part in re.split(r"(`[^`]*`)", text):
        if len(part) >= 2 and part.startswith("`") and part.endswith("`"):
            out.append(f"<code style='{_CODE_STYLE}'>{html.escape(part[1:-1])}</code>")
            continue
        x = html.escape(part, quote=True)
        x = _LINK.sub(lambda m: f"<a href=\"{m.group(2)}\">{m.group(1)}</a>", x)
        x = _BOLD.sub(r"<b>\1</b>", x)
        x = _ITALIC.sub(r"<i>\1</i>", x)
        out.append(x)
    return "".join(out)


def md_to_html(md: str) -> str:
    """the Markdown as an HTML fragment with inline styles, to copy as rich text"""
    out = ["<div style='font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.45;color:#111827'>"]
    for b in _blocks(md):
        kind = b[0]
        if kind == "h2":
            out.append(f"<h2 style='font-size:18px;margin:12px 0 6px'>{_inline_html(b[1])}</h2>")
        elif kind == "h3":
            out.append(f"<h3 style='font-size:15px;margin:14px 0 6px'>{_inline_html(b[1])}</h3>")
        elif kind == "table":
            head = "".join(f"<th style='{_TH}'>{_inline_html(c)}</th>" for c in b[1])
            rows = "".join("<tr>" + "".join(f"<td style='{_TD}'>{_inline_html(c)}</td>" for c in r) + "</tr>" for r in b[2])
            out.append(f"<table style='border-collapse:collapse;margin:4px 0 8px;font-size:13px'><tr>{head}</tr>{rows}</table>")
        elif kind == "ul":
            html_items, open_sub = [], False
            for level, text in b[1]:
                if level and not open_sub:
                    html_items.append("<ul style='margin:2px 0;padding-left:20px'>")
                    open_sub = True
                elif not level and open_sub:
                    html_items.append("</ul>")
                    open_sub = False
                html_items.append(f"<li>{_inline_html(text)}</li>")
            if open_sub:
                html_items.append("</ul>")
            out.append("<ul style='margin:4px 0 8px;padding-left:22px'>" + "".join(html_items) + "</ul>")
        else:
            out.append("<p style='margin:4px 0'>" + "<br>".join(_inline_html(x) for x in b[1]) + "</p>")
    out.append("</div>")
    return "".join(out)


# ── Slack ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
# pasted in the message box of Slack, not posted with the API: the box keeps *bold*, `code` and the bullets, but shows
# &lt; and <url|text> as they are written. So nothing is escaped and a link is "text (url)", Slack makes the URL a link
def _inline_slack(text: str) -> str:
    out = []
    for part in re.split(r"(`[^`]*`)", text):
        if len(part) >= 2 and part.startswith("`") and part.endswith("`"):
            out.append(part)
            continue
        x = _LINK.sub(lambda m: f"{m.group(1)} ({m.group(2)})", part)
        x = _BOLD.sub(r"*\1*", x)
        out.append(x)
    return "".join(out)


def md_to_slack(md: str) -> str:
    """the Markdown as text to paste in Slack: *bold* headings, • bullets, a table row as a bullet (its first two cells,
    then "header: value" for the others, the empty ones left out)"""
    out: List[str] = []
    for b in _blocks(md):
        kind = b[0]
        if kind in ("h2", "h3"):
            if out:
                out.append("")
            out.append(f"*{_inline_slack(b[1]).replace('*', '')}*")
        elif kind == "table":
            header = b[1]
            for r in b[2]:
                parts = [c for c in r[:2] if c]
                parts += [f"{h}: {c}" if h else c for h, c in zip(header[2:], r[2:]) if c]
                out.append("• " + _inline_slack(" · ".join(parts)))
        elif kind == "ul":
            out += [("    ◦ " if level else "• ") + _inline_slack(text) for level, text in b[1]]
        else:
            if out and out[-1] != "":
                out.append("")
            out += [_inline_slack(x) for x in b[1]]
    return "\n".join(out).strip() + "\n"
