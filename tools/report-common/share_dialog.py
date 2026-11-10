#!/usr/bin/env python3
"""
📤 Share, for every playground HTML report (thread dump, heap dump, GC logs, flight recorder, tcp dump, XStream report,
CFK bundle, benchmark, SMT test, connector diagnose, DLQ, diff, CVE scan, certificates, Kafka Streams, costs…): a button
in the header (and the S key) that opens a dialog to send the report to a colleague:

  💾 Download this report   the page as a self-contained .html (a Blob of the page as it was loaded)
  💬 Copy the summary       the plain-text digest (the one the command prints in the terminal, else verdict + findings)
  🎫 🧵 📝                  Markdown for a ticket, Slack text and rich text (share_formats.py), when there is Markdown
  🔗 Copy the path          where the report is on this machine
  ✉️ Email the summary      a new mail, subject = the title of the report

Same look as the dialog of the analyze logs report (tools/log-analyzer/log_report.py keeps its own, with the .zip of its
file pages and the sanitization state): this module does not import it. Python 3.8, stdlib only.

  add_share(page_html, title=None, summary=None, ticket=None)  the dialog before </body> (None: read from the page)
  share_block(title, summary, ticket="")           the CSS + embedded texts + dialog + script, to put in a page
  from_page(page_html)                             (title, verdict, [(severity, text)]) read back from a rendered page
  summary_text() / ticket_markdown()               a summary and a Markdown digest from a verdict and findings
"""

import html
import re
from typing import List, Optional, Sequence, Tuple

try:
    import share_formats
except ImportError:  # pragma: no cover - share_formats.py sits next to this file
    share_formats = None

Finding = Tuple[str, str]

SEV_ICONS = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🟢", "INFO": "ℹ️", "OK": "✅",
             "WARN": "🟡", "WARNING": "🟡", "ERROR": "🔴", "FATAL": "🔴"}


def _e(s) -> str:
    return html.escape("" if s is None else str(s), quote=True)


def _text(fragment: str) -> str:
    """an HTML fragment as one line of text"""
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", fragment or ""))).strip()


def _embed(id_: str, text: str) -> str:
    # every < encoded, not only </: a log line with <!--<script> would put the parser in the double escaped state of a
    # script element, and the rest of the page would become text of this one. Every \ first (\u005c): a \u003c of the
    # text itself (a Jackson-escaped log line) must come back as it was, never as a live < in the HTML copied as rich text
    return f"<script type='text/plain' id='{id_}'>{embed_text(text)}</script>"


def embed_text(text: str) -> str:
    """a text for a <script type='text/plain'> element, read back by unembed() of SHARE_SCRIPT"""
    return (text or "").replace("\\", "\\u005c").replace("<", "\\u003c")


def md_cell(s) -> str:
    return re.sub(r"\s+", " ", str(s)).replace("|", "\\|").strip()


# ── summaries ──────────────────────────────────────────────────────────────────────────────────────────────────────────
def from_page(page_html: str) -> Tuple[str, str, List[Finding]]:
    """the title (<title>), the verdict (the first .verdict block) and the findings (the .rec-card of findings_html) of a
    rendered report: the summary of a report whose generator does not give one"""
    m = re.search(r"<title>(.*?)</title>", page_html, re.S | re.I)
    title = _text(m.group(1)) if m else "Report"
    # the verdict of report_html (verdict_html), of the JFR / benchmark / CFK pages; the banner of the SMT test report
    m = (re.search(r"<div class=['\"][^'\"]*\bverdict\b[^'\"]*['\"][^>]*>(.*?)</div>", page_html, re.S)
         or re.search(r"<div class=['\"]banner\b[^'\"]*['\"][^>]*>(.*?)</div>", page_html, re.S))
    verdict = _text(m.group(1)) if m else ""
    findings = []
    # the text of a finding up to its details (rec-details / rec-meta / rec-scope / rec-flag) or the end of its card
    for m in re.finditer(r"<span class=['\"]rec-badge [^'\"]*['\"]>(.*?)</span><(?:span|div) class=['\"]rec-text['\"]>(.*?)"
                         r"(?=<(?:ul|div|span) class=['\"]?rec-(?:details|meta|scope|flag|action)|</span></div>|</div></div>)",
                         page_html, re.S):
        sev = _text(m.group(1)).split(" ")[-1].upper()
        findings.append((sev, _text(m.group(2))))
    return title, verdict, findings


def _norm(findings) -> List[Finding]:
    """(severity, text) tuples, or the {severity, text} dicts of findings_html"""
    return [(f.get("severity", ""), f.get("text") or f.get("message") or "") if isinstance(f, dict) else (f[0], f[1])
            for f in findings]


def summary_text(title: str, verdict: str = "", findings: Sequence = (), meta: Sequence[str] = (),
                 limit: int = 15) -> str:
    """a plain-text summary: title, verdict, meta lines, findings (worst first, as written by the generator)"""
    findings = _norm(findings)
    out = [title]
    if verdict:
        out.append(f"Verdict: {verdict}")
    out += [m for m in meta if m]
    if findings:
        out += ["", f"Findings ({len(findings)}):"]
        out += [f"  {SEV_ICONS.get(s.upper(), '•')} {s.upper()}: {t}" for s, t in list(findings)[:limit]]
        if len(findings) > limit:
            out.append(f"  … and {len(findings) - limit} more in the report")
    return "\n".join(out) + "\n"


def ticket_markdown(title: str, verdict: str = "", findings: Sequence = (), meta: Sequence[str] = (),
                    command: str = "") -> str:
    """the Markdown of 🎫 Copy for a ticket (and, converted by share_formats, of 🧵 Slack and 📝 rich text)"""
    findings = _norm(findings)
    out = [f"## {title}", ""]
    if verdict:
        out += [f"**Verdict:** {verdict}", ""]
    if meta:
        out += [f"- {m}" for m in meta if m] + [""]
    if findings:
        out += ["### Findings", "", "| Severity | Finding |", "| --- | --- |"]
        out += [f"| {SEV_ICONS.get(s.upper(), '')} {md_cell(s.upper())} | {md_cell(t)} |" for s, t in findings]
        out.append("")
    out.append(f"_Generated by `{command}` (kafka-docker-playground)._" if command
               else "_Generated by kafka-docker-playground._")
    return "\n".join(out) + "\n"


# ── the dialog ─────────────────────────────────────────────────────────────────────────────────────────────────────────
def _card(attrs: str, icon: str, what: str, why: str, cls: str = "") -> str:
    return (f"<button type='button' class='share-card{' ' + cls if cls else ''}' {attrs}><span class='sc-icon'>{icon}</span><span class='sc-body'>"
            f"<b>{what}</b><small>{why}</small></span><span class='sc-go' aria-hidden='true'>›</span></button>")


def share_block(title: str, summary: str, ticket: str = "") -> str:
    """the dialog of a report: CSS, the summary (and the ticket Markdown in 3 formats) as text/plain scripts, the dialog,
    the script that adds the 📤 button to the header (and the S key)"""
    formats = ""
    if ticket and share_formats is not None:
        formats = (_embed("pg-share-ticket", ticket) + _embed("pg-share-slack", share_formats.md_to_slack(ticket))
                   + _embed("pg-share-html", share_formats.md_to_html(ticket)))
    elif ticket:
        formats = _embed("pg-share-ticket", ticket)
    has = {"slack": "pg-share-slack" in formats, "html": "pg-share-html" in formats}
    cards = (_card("data-share='download'", "💾", "Download this report (.html)",
                   "one self-contained file: attach it to a ticket, a mail or a Slack message", "sc-primary")
             + "<div class='share-grid'>"
             + _card("data-share='summary'", "💬", "Copy the summary", "the verdict and the findings as plain text, like the terminal")
             + (_card("data-share='ticket'", "🎫", "Copy for a ticket", "Markdown with a table of the findings: paste it in Zendesk or Jira")
                if ticket else "")
             + (_card("data-share='slack'", "🧵", "Copy for Slack", "the same, in Slack formatting: paste it in a Slack message")
                if has["slack"] else "")
             + (_card("data-share='html'", "📝", "Copy as rich text (HTML)",
                      "the same with real tables: paste it in Zendesk, Gmail, Confluence or Google Docs") if has["html"] else "")
             + _card("data-share='path'", "🔗", "Copy the path", "where the report is on this machine")
             + _card("data-share='mail'", "✉️", "Email the summary", "a new mail with the summary: attach the downloaded .html")
             + "</div>")
    return (SHARE_CSS + _embed("pg-share-summary", summary) + formats
            + f"<dialog class='share-dlg' aria-labelledby='pg-share-h' data-title='{_e(title)}'><div class='sd-head'>"
            "<h3 id='pg-share-h'>📤 Share this report</h3>"
            "<button type='button' class='share-close sd-x' aria-label='close'>✕</button></div>"
            "<div class='sd-body'><p class='share-warn'>⚠️ Internal to Confluent: the report can contain hostnames, IPs and "
            "other details of its input. Review it before sending it outside.</p>"
            + cards + "<p class='share-done' aria-live='polite'></p></div>"
            "<div class='sd-foot'><span class='sd-meta'>S opens this dialog, Esc closes it</span>"
            "<button type='button' class='share-close'>Close</button></div></dialog>"
            + SHARE_SCRIPT)


def add_share(page_html: str, title: Optional[str] = None, summary: Optional[str] = None, ticket: Optional[str] = None,
              command: str = "") -> str:
    """the page with its 📤 Share dialog, before its last </body> (at the end without one). title, summary and ticket
    (Markdown, "" for none) default to what from_page() reads in the page: its verdict and findings; command: the
    playground command named at the end of the ticket Markdown. A page that already has a dialog (the analyze logs
    report) is returned as it is"""
    if "class='share-dlg'" in page_html or 'class="share-dlg"' in page_html:
        return page_html
    if title is None or summary is None or ticket is None:
        p_title, verdict, findings = from_page(page_html)
        title = title or p_title
        if summary is None:
            summary = summary_text(title, verdict, findings)
        if ticket is None:
            ticket = ticket_markdown(title, verdict, findings, command=command) if (verdict or findings) else ""
    block = share_block(title, summary, ticket)
    i = page_html.lower().rfind("</body>")
    return page_html[:i] + block + page_html[i:] if i >= 0 else page_html + block


SHARE_CSS = """<style>
.share-open{font:inherit;cursor:pointer}
.share-hero{font-size:.85rem;font-weight:700;padding:6px 16px;border-radius:999px;border:0;background:#fff;color:#4c1d95;
box-shadow:0 4px 14px rgba(15,23,42,.25);transition:transform .1s;white-space:nowrap}.share-hero:hover{transform:translateY(-1px);background:#f5f3ff}
.header-meta .share-hero{margin-left:auto}
.share-next{margin-left:auto;align-self:flex-start}
/* below the fixed Toggle theme of the page (top right of the window) */
.share-corner{position:absolute;top:44px;right:24px;z-index:2}
.share-float{position:fixed;top:12px;right:16px;z-index:30;font-size:.8rem;font-weight:700;padding:5px 12px;border-radius:999px;border:0;background:#7c3aed;color:#fff}
.share-dlg{border:0;border-radius:18px;padding:0;width:min(660px,92vw);max-width:660px;max-height:88vh;overflow:auto;
box-shadow:0 30px 80px rgba(15,23,42,.45);background:#fff;color:#1e293b;position:fixed;inset:0;margin:auto;height:fit-content;
font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;line-height:1.45}
.share-dlg[open]{animation:sd-in .22s cubic-bezier(.22,1,.36,1)}
@keyframes sd-in{from{opacity:0;transform:translateY(14px) scale(.97)}to{opacity:1;transform:none}}
.share-dlg::backdrop{background:rgba(15,23,42,.6);backdrop-filter:blur(3px)}
.sd-head{display:flex;align-items:center;justify-content:space-between;padding:16px 20px;color:#fff;
background:radial-gradient(500px 120px at 0% 0%,rgba(56,189,248,.35),transparent 60%),linear-gradient(120deg,#312e81,#6d28d9 60%,#a21caf)}
.sd-head h3{font-size:1.1rem;margin:0;color:#fff!important;border:0;padding:0}
.sd-x{border:0!important;background:rgba(255,255,255,.16)!important;color:#fff!important;width:30px;height:30px;padding:0!important;border-radius:50%!important;font-size:.9rem}
.sd-x:hover{background:rgba(255,255,255,.3)!important}
.sd-body{padding:16px 20px 6px}
.share-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:12px 0 4px}
.share-card{display:flex;align-items:center;gap:12px;width:100%;text-align:left;font:inherit;color:inherit;text-decoration:none;cursor:pointer;
padding:12px 14px;border-radius:14px;border:1px solid #e2e8f0;background:#f8fafc;transition:transform .12s,box-shadow .12s,border-color .12s,background .12s}
.share-card:hover{transform:translateY(-2px);border-color:#a78bfa;box-shadow:0 10px 24px -12px rgba(109,40,217,.5);background:#faf5ff}
.share-card:focus-visible{outline:2px solid #7c3aed;outline-offset:2px}
.sc-icon{flex:none;display:flex;align-items:center;justify-content:center;width:40px;height:40px;border-radius:12px;font-size:1.25rem;
background:linear-gradient(135deg,#ede9fe,#e0f2fe)}
.sc-body{display:flex;flex-direction:column;gap:2px;min-width:0}
.sc-body b{font-size:.9rem}.sc-body small{font-size:.74rem;color:#64748b;line-height:1.35}
.sc-go{margin-left:auto;font-size:1.3rem;color:#a78bfa;transition:transform .12s}.share-card:hover .sc-go{transform:translateX(3px)}
.share-card.sc-primary{color:#fff;border:0;padding:14px 16px;background:linear-gradient(120deg,#2563eb,#7c3aed);box-shadow:0 12px 28px -14px rgba(37,99,235,.8)}
.share-card.sc-primary:hover{background:linear-gradient(120deg,#1d4ed8,#6d28d9)}
.share-card.sc-primary .sc-icon{background:rgba(255,255,255,.18)}.share-card.sc-primary small{color:rgba(255,255,255,.85)}
.share-card.sc-primary .sc-go{color:#fff}
.share-card.sc-done{border-color:#22c55e!important;background:#f0fdf4!important}
.share-card.sc-done .sc-icon{background:#bbf7d0}
.share-done{min-height:1.4em;margin:8px 0 0;font-size:.82rem;font-weight:600;color:#15803d}
.sd-foot{display:flex;align-items:center;justify-content:space-between;padding:10px 20px 16px}
.sd-meta{font-size:.75rem;color:#64748b}
@media (max-width:560px){.share-grid{grid-template-columns:1fr}}
@media (prefers-reduced-motion:reduce){.share-dlg[open]{animation:none}.share-card{transition:none}}
.share-warn{background:#fef3c7;color:#92400e;border-radius:12px;padding:10px 14px;font-size:.82rem;border-left:4px solid #f59e0b;margin:0 0 12px}
.share-close{font:inherit;font-size:.8rem;padding:3px 12px;border-radius:6px;border:1px solid #cbd5e1;background:transparent;color:inherit;cursor:pointer}
html[data-theme=dark] .share-hero{background:#ede9fe;color:#4c1d95}
html[data-theme=dark] .share-dlg{background:#1e293b;color:#e2e8f0}
html[data-theme=dark] .share-card{background:#0f172a;border-color:#334155}
html[data-theme=dark] .share-card:hover{background:#1e1b4b;border-color:#7c3aed}
html[data-theme=dark] .sc-icon{background:linear-gradient(135deg,#312e81,#0c4a6e)}
html[data-theme=dark] .sc-body small,html[data-theme=dark] .sd-meta{color:#94a3b8}
html[data-theme=dark] .share-card.sc-primary{background:linear-gradient(120deg,#2563eb,#7c3aed)}
html[data-theme=dark] .share-card.sc-primary small{color:rgba(255,255,255,.85)}
html[data-theme=dark] .share-card.sc-done{background:#052e16!important}
html[data-theme=dark] .share-done{color:#86efac}
html[data-theme=dark] .share-warn{background:#422006;color:#fcd34d}
html[data-theme=dark] .share-close{border-color:#334155}
</style>"""

SHARE_SCRIPT = """<script>
(function () {
  const dlg = document.querySelector(".share-dlg");
  if (!dlg) return;
  // 💾 the page as it was loaded: taken now (this script runs at the end of the body, before the DOMContentLoaded
  // handlers of the report fill or change the page), without the open dialog; the copy has its dialog too
  const snapshot = "<!DOCTYPE html>\\n" + document.documentElement.outerHTML;
  function addOpen(where, cls, before) {
    if (!where) return null;
    const b = document.createElement("button");
    b.type = "button"; b.className = "share-open " + cls; b.textContent = "📤 Share";
    b.title = "send this report to a colleague: download it, copy the summary for Slack or a ticket, an email (S)";
    b.setAttribute("aria-haspopup", "dialog");
    b.addEventListener("click", () => dlg.showModal());
    if (before) where.insertBefore(b, before); else where.appendChild(b);
    return b;
  }
  function place() {
    if (document.querySelector(".share-open")) return;
    // the header of report_html (header_html / page): in its meta pills
    const meta = document.querySelector(".header .header-meta");
    if (meta) { addOpen(meta, "share-hero"); return; }
    // a <header> of its own (benchmark, flight recorder, SMT test, CFK bundle): next to its Toggle theme, else top right
    const header = document.querySelector("header");
    if (header) {
      const toggle = header.querySelector(".theme-toggle");
      if (toggle && toggle.parentElement === header) { addOpen(header, "share-hero share-next", toggle); return; }
      if (getComputedStyle(header).position === "static") header.style.position = "relative";
      addOpen(header, "share-hero share-corner");
      return;
    }
    addOpen(document.body, "share-float");
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", place); else place();
  document.addEventListener("keydown", function (ev) {
    if ((ev.key === "s" || ev.key === "S") && !ev.metaKey && !ev.ctrlKey && !ev.altKey
        && !(ev.target && ev.target.closest && ev.target.closest("input, textarea, select, [contenteditable]")) && !dlg.open) {
      ev.preventDefault();
      dlg.showModal();
    }
  });
  const done = dlg.querySelector(".share-done");
  // embed_text() back: \\u003c is <, \\u005c is \\ (in one pass: a \\u003c of the text, written \\u005cu003c, stays as it was)
  function unembed(t) { return t.replace(/\\\\u00(3c|5c)/g, (m, h) => h === "3c" ? "<" : "\\\\"); }
  function embedded(id) { const el = document.getElementById(id); return el ? unembed(el.textContent) : ""; }
  const summary = embedded("pg-share-summary");
  const said = what => { done.textContent = "✅ " + what; };
  function fallback(text, what) {
    const ta = document.createElement("textarea");
    ta.value = text; dlg.appendChild(ta); ta.select();
    // execCommand returns false when the copy is refused (it does not always throw): the text stays there to copy by hand
    let copied = false;
    try { copied = document.execCommand("copy"); } catch (e) { copied = false; }
    if (!copied) { done.textContent = "the copy failed: select the text and copy it"; return; }
    said(what + " copied to the clipboard");
    ta.remove();
  }
  function copy(text, what) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => said(what + " copied to the clipboard"), () => fallback(text, what));
    } else fallback(text, what);
  }
  function fallbackRich(htmlText, what) {
    const box = document.createElement("div");
    box.contentEditable = "true";
    box.style.cssText = "position:fixed;left:-9999px;top:0";
    box.innerHTML = htmlText;
    dlg.appendChild(box);
    const range = document.createRange(), sel = window.getSelection();
    range.selectNodeContents(box); sel.removeAllRanges(); sel.addRange(range);
    let copied = false;
    try { copied = document.execCommand("copy"); } catch (e) { copied = false; }
    if (copied) said(what + " copied to the clipboard");
    else done.textContent = "the copy failed: use 🎫 Copy for a ticket";
    sel.removeAllRanges();
    box.remove();
  }
  // rich text: text/html for the editors that take it (Zendesk, Gmail, Confluence, Docs), the Markdown as text/plain
  function copyRich(htmlText, plain, what) {
    if (navigator.clipboard && navigator.clipboard.write && window.ClipboardItem) {
      navigator.clipboard.write([new ClipboardItem({"text/html": new Blob([htmlText], {type: "text/html"}),
                                                    "text/plain": new Blob([plain], {type: "text/plain"})})])
        .then(() => said(what + " copied to the clipboard"), () => fallbackRich(htmlText, what));
    } else fallbackRich(htmlText, what);
  }
  function fileName() {
    const page = decodeURIComponent(location.pathname).split("/").pop();
    if (/\\.html?$/i.test(page)) return page;
    return (dlg.dataset.title || "report").replace(/[^\\w.-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80) + ".html";
  }
  dlg.addEventListener("click", function (ev) {
    if (ev.target.closest(".share-close") || ev.target === dlg) { dlg.close(); return; }
    const b = ev.target.closest("[data-share]");
    if (!b) return;
    b.classList.add("sc-done"); setTimeout(() => b.classList.remove("sc-done"), 1600);
    const path = decodeURIComponent(location.pathname);
    const what = b.dataset.share;
    if (what === "download") {
      const url = URL.createObjectURL(new Blob([snapshot], {type: "text/html"}));
      const a = document.createElement("a");
      a.href = url; a.download = fileName(); document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 4000);
      said(fileName() + " downloaded");
    }
    else if (what === "summary") copy(summary, "the summary");
    else if (what === "ticket") copy(embedded("pg-share-ticket"), "the summary for a ticket");
    else if (what === "slack") copy(embedded("pg-share-slack"), "the summary for Slack");
    else if (what === "html") copyRich(embedded("pg-share-html"), embedded("pg-share-ticket"), "the summary as rich text");
    else if (what === "path") copy(path, "the path");
    else if (what === "mail") {
      const body = "Report: " + path.split("/").pop() + " (attached)\\n\\n" + summary;
      location.href = "mailto:?subject=" + encodeURIComponent("📤 " + (dlg.dataset.title || "playground report"))
        // cut by code points: a cut in the middle of an emoji (a surrogate pair) makes encodeURIComponent throw
        + "&body=" + encodeURIComponent(Array.from(body).length > 1800 ? Array.from(body).slice(0, 1800).join("") + "\\n…" : body);
    }
  });
})();
</script>"""
