#!/usr/bin/env python3
"""Confluent Cloud release notes, from the docs RSS feed, filtered by date, connector, category or regex.

docs.confluent.io publishes the Confluent Cloud release notes as one RSS feed
(https://docs.confluent.io/cloud/current/release-notes.xml) with the whole history (2019 onwards): one
<item> per release-notes day, its <link> pointing to the anchor of the day. The body is HTML: mostly a
<ul> with one <li> per change (a nested list belongs to its parent change), sometimes a <dl> (one
<dt>/<dd> pair per change) or plain <p> paragraphs. A change about a fully managed connector links the
connector page, /cloud/current/connectors/[<dir>/]cc-<name>.html#<anchor>: that link, not the wording, is
what --connector matches.

Prints a JSON document on stdout; warnings go to stderr. The feed is cached in --cache-dir for one day.
"""
import argparse
import datetime
import email.utils
import glob
import html.parser
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

# fetch, cache and text helpers are shared with the connector plugin changelog (no __pycache__ in the repo)
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "connector-changelog"))
from changelog import cached_fetch, clean, warn  # noqa: E402

FEED = "https://docs.confluent.io/cloud/current/release-notes.xml"
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CONNECTOR_PAGE = re.compile(r"/cloud/current/connectors/(?:[^/\"#?]+/)*(cc-[a-z0-9-]+)\.html(?:#([a-z0-9-]+))?")
# a change can be in several categories; "connectors" also comes from a connector page link
CATEGORIES = {
    "connectors": re.compile(r"\bconnectors?\b|single message transform|\bSMTs?\b", re.I),
    "flink": re.compile(r"\bflink\b", re.I),
    "schema-registry": re.compile(r"schema registry|schema linking|data contracts?|data quality rules?|CSFLE|field.level encryption|stream governance|stream catalog|stream lineage", re.I),
    "tableflow": re.compile(r"\btableflow\b", re.I),
    "ksqldb": re.compile(r"\bksqldb\b", re.I),
    "networking": re.compile(r"private ?link|privatelink|vpc peering|\bpeering\b|transit gateway|private network|private service connect|\bPNI\b|egress|ingress|\bDNS\b|network link|gateway", re.I),
    "security": re.compile(r"\bRBAC\b|\bACLs?\b|oauth|\bSSO\b|\bSAML\b|\bOIDC\b|api keys?|\bBYOK\b|encryption|audit log|identity pool|identity provider|\bMFA\b|\bmTLS\b|certificate|service accounts?|secret manager", re.I),
    "cli": re.compile(r"confluent cli|\bconfluent [a-z-]+ [a-z-]+\b command|\bCLI\b", re.I),
    "terraform": re.compile(r"\bterraform\b", re.I),
    "cluster-linking": re.compile(r"cluster link", re.I),
}


ADMONITIONS = {"Note", "Important", "Tip", "Warning", "Caution", "Attention"}


class Changes(html.parser.HTMLParser):
    """Changes of one release-notes day: [{"text", "links"}].

    A change is a top-level <li> (nested lists included, their items joined with "; "), a <dt>/<dd> pair,
    or a <p> outside any list. A heading (<h3>/<h4>, or a <p> ending with ":" right before a list) is kept
    as the "section" of the changes that follow it.
    """

    def __init__(self):
        super().__init__()
        self.changes = []
        self.section = None
        self.lists = 0  # <ul>/<ol> depth
        self.dl = 0
        self.cur = None  # buffer of the change being read
        self.links = []
        self.heading = None
        self.p = None  # buffer of a top-level <p>
        self.p_links = []
        self.intro_links = None  # links of the "…:" paragraph introducing the current list
        self.section_before_intro = None
        self.admonition = None

    def start_change(self):
        self.cur, self.links = [], []

    def end_change(self):
        if self.cur is not None:
            text = clean("".join(self.cur))
            text = re.sub(r"\s+([.,;:])(?=\s|$)", r"\1", text)
            text = re.sub(r";(\s*;)+", ";", text)
            text = re.sub(r":\s*[:;]\s*", ": ", text)
            text = re.sub(r"([.;:!?])\s*\.(\s|$)", r"\1\2", text).strip(" ;")
            if text:
                self.changes.append({"section": self.section, "text": text, "links": list(dict.fromkeys(self.links))})
        self.cur, self.links = None, []

    def handle_starttag(self, tag, attrs):
        if tag in ("h2", "h3", "h4", "h5"):
            self.heading = []
            return
        if tag in ("ul", "ol"):
            if self.lists == 0 and self.p is not None:
                # "<p>The following connectors now …:</p><ul>": the paragraph introduces the list
                self.flush_p(intro=True)
            self.lists += 1
            if self.lists > 1 and self.cur is not None:
                self.cur.append(": " if not "".join(self.cur).rstrip().endswith(":") else " ")
            return
        if tag == "dl":
            self.flush_p()
            self.dl += 1
            return
        if tag == "li":
            if self.lists == 1 and self.dl == 0:
                self.start_change()
            elif self.cur is not None and self.lists > 1:
                self.cur.append("; ")
            return
        if tag == "dt" and self.dl and self.lists == 0:
            self.end_change()
            self.start_change()
            return
        if tag == "dd" and self.cur is not None:
            self.cur.append(": ")
            return
        if tag == "p" and self.lists == 0 and self.dl == 0 and self.heading is None:
            self.flush_p()
            self.p, self.p_links = [], []
            return
        if tag == "a":
            href = dict(attrs).get("href")
            if href and not href.startswith("#"):
                if self.cur is not None:
                    self.links.append(href)
                elif self.p is not None:
                    self.p_links.append(href)
            return
        if tag == "br" and self.cur is not None:
            self.cur.append(" ")

    def flush_p(self, intro=False):
        if self.p is None:
            return
        text = clean("".join(self.p))
        links = list(dict.fromkeys(self.p_links))
        self.p, self.p_links = None, []
        if not text:
            return
        if text in ADMONITIONS:
            # <div class="admonition note"><p class="admonition-title">Note</p><p>…</p>: "Note: …"
            self.admonition = text
            return
        if self.admonition:
            text, self.admonition = f"{self.admonition}: {text}", None
        if intro:
            self.section_before_intro = self.section
            self.section = text.rstrip(":")
            # its links (the connector of "The X connector now supports:") belong to the list items
            self.intro_links = links
        else:
            self.changes.append({"section": self.section, "text": text, "links": links})

    def handle_endtag(self, tag):
        if tag in ("h2", "h3", "h4", "h5") and self.heading is not None:
            text = clean("".join(self.heading))
            self.section = text or self.section
            self.heading = None
            return
        if tag in ("ul", "ol"):
            self.lists = max(0, self.lists - 1)
            if self.lists >= 1 and self.cur is not None:
                # text after a nested list ("…; Salesforce Source V2. Secret manager integration is…")
                self.cur.append(". ")
            if self.lists == 0 and self.intro_links is not None:
                # an introduction only covers its own list
                self.section, self.intro_links = self.section_before_intro, None
            return
        if tag == "li" and self.lists == 1 and self.dl == 0:
            self.links = (self.intro_links or []) + self.links
            self.end_change()
            return
        if tag == "dl":
            self.end_change()
            self.dl = max(0, self.dl - 1)
            return
        if tag == "p" and self.p is not None and self.lists == 0 and self.dl == 0:
            # kept until the next tag: a "…:" paragraph followed by a list is an introduction
            if not clean("".join(self.p)).endswith(":"):
                self.flush_p()

    def handle_data(self, data):
        if self.heading is not None:
            self.heading.append(data)
        elif self.cur is not None:
            self.cur.append(data)
        elif self.p is not None:
            self.p.append(data)

    def close(self):
        super().close()
        self.flush_p()
        self.end_change()


def connector_pages(links):
    """{"cc-<page>", "cc-<anchor>"} of the connector pages linked by a change."""
    pages = set()
    for link in links:
        for m in CONNECTOR_PAGE.finditer(link):
            pages.add(m.group(1))
            if m.group(2) and m.group(2).startswith("cc-"):
                pages.add(m.group(2))
    # "cc-oracle-xstream-cdc-source-features" is a sub page of cc-oracle-xstream-cdc-source
    for p in list(pages):
        for suffix in ("-features", "-configuration-properties", "-config", "-quick-start", "-limitations"):
            if p.endswith(suffix):
                pages.add(p[: -len(suffix)])
    return pages


def categories_of(change, pages):
    cats = [c for c, rx in CATEGORIES.items() if rx.search(change["text"]) or (change["section"] and rx.search(change["section"]))]
    if pages and "connectors" not in cats:
        cats.insert(0, "connectors")
    return cats or ["other"]


def fm_examples():
    """[(connector class, example dir, {"cc-…" pages of its README})] of the ccloud/fm-* examples."""
    out = []
    for config in sorted(glob.glob(os.path.join(ROOT, "ccloud", "fm-*", "config-*.json"))):
        directory = os.path.dirname(config)
        cls = re.sub(r"^config-|\.json$", "", os.path.basename(config))
        pages = set()
        readme = os.path.join(directory, "README.md")
        if os.path.exists(readme):
            with open(readme, encoding="utf-8", errors="replace") as f:
                pages = connector_pages(re.findall(r"https://docs\.confluent\.io/cloud/current/connectors/[^ )\"']*", f.read()))
        out.append((cls, os.path.relpath(directory, ROOT), pages))
    return out


def resolve_connector(query):
    """(pages to match, label, text regex or None) of --connector.

    Accepts a connector class (AzureBlobSink: the pages linked by the README of its ccloud/fm-* example), an
    example folder (fm-azure-blob-storage-sink), a page (cc-azure-blob-sink, or its URL), or else free text.
    """
    q = query.strip()
    m = CONNECTOR_PAGE.search(q)
    if m:
        return connector_pages([q]), m.group(1), None
    if re.fullmatch(r"cc-[a-z0-9-]+", q):
        return connector_pages([f"/cloud/current/connectors/{q}.html"]), q, None
    q_class = q.split("/")[-1]  # confluentinc/AzureBlobSink
    examples = fm_examples()
    for cls, directory, pages in examples:
        if cls.lower() == q_class.lower() or os.path.basename(directory) == q.rstrip("/").split("/")[-1]:
            if pages:
                return pages, f"{cls} ({directory}: {', '.join(sorted(pages))})", None
            warn(f"⚠️ {directory}/README.md links no Confluent Cloud connector page: matching \"{q_class}\" in the text")
            return set(), cls, re.compile(re.escape(q_class), re.I)
    return set(), q, re.compile(re.escape(q), re.I)


def parse_date(value, what):
    try:
        return datetime.date.fromisoformat(value)
    except ValueError:
        raise SystemExit(f"❌ {what} {value}: not a date (YYYY-MM-DD)")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--since", help="first day (included), YYYY-MM-DD")
    p.add_argument("--until", help="last day (included), YYYY-MM-DD")
    p.add_argument("--around", help="day of interest, YYYY-MM-DD: --days before and after it")
    p.add_argument("--days", type=int, default=None, help="with --around: days before and after (default 7); alone: the last N days")
    p.add_argument("--connector", action="append", help="connector class, ccloud/fm-* example, cc-<page> or text")
    p.add_argument("--category", action="append", choices=sorted(CATEGORIES) + ["other"])
    p.add_argument("--grep", help="case-insensitive regex on the text of the change")
    p.add_argument("--list-categories", action="store_true")
    p.add_argument("--cache-dir", default="/tmp/ccloud-changelog")
    p.add_argument("--force-refresh", action="store_true")
    p.add_argument("--today", help=argparse.SUPPRESS)  # tests
    a = p.parse_args()

    if a.list_categories:
        print("\n".join(sorted(CATEGORIES) + ["other"]))
        return
    today = parse_date(a.today, "--today") if a.today else datetime.date.today()
    since = parse_date(a.since, "--since") if a.since else None
    until = parse_date(a.until, "--until") if a.until else None
    if a.around:
        if a.since or a.until:
            raise SystemExit("❌ --around cannot be used with --since or --until")
        around = parse_date(a.around, "--around")
        days = 7 if a.days is None else a.days
        since, until = around - datetime.timedelta(days=days), around + datetime.timedelta(days=days)
    elif a.days is not None:
        if a.since:
            raise SystemExit("❌ --days cannot be used with --since (use --until, or --around)")
        since = (until or today) - datetime.timedelta(days=a.days)
    elif not since and not until and not a.connector and not a.grep:
        # nothing to narrow it down: the last 30 days (a connector or a regex searches the whole history)
        since = today - datetime.timedelta(days=30)
    if since and until and until < since:
        raise SystemExit(f"❌ --since {since} must be before --until {until}")
    if a.days is not None and a.days < 0:
        raise SystemExit("❌ --days must be positive")
    try:
        pattern = re.compile(a.grep, re.I) if a.grep else None
    except re.error as e:
        raise SystemExit(f"❌ --grep {a.grep}: {e}")

    connectors = [resolve_connector(c) for c in (a.connector or [])]

    body, _ = cached_fetch(FEED, a.cache_dir, a.force_refresh)
    if not body or "<rss" not in body[:500]:
        raise SystemExit(f"❌ {FEED} is not an RSS feed")
    try:
        root = ET.fromstring(body)
    except ET.ParseError as e:
        raise SystemExit(f"❌ {FEED}: {e}")

    result = {
        "feed": FEED,
        "page": "https://docs.confluent.io/cloud/current/release-notes/index.html",
        "since": since.isoformat() if since else None,
        "until": until.isoformat() if until else None,
        "connectors": [label for _, label, _ in connectors] or None,
        "categories": a.category,
        "grep": a.grep,
        "latest": None,
        "oldest": None,
        "days": [],
    }
    for item in root.iter("item"):
        try:
            day = email.utils.parsedate_to_datetime(item.findtext("pubDate")).date()
        except (TypeError, ValueError):
            warn(f"⚠️ skipping \"{item.findtext('title')}\": no publication date")
            continue
        result["latest"] = max(result["latest"] or day.isoformat(), day.isoformat())
        result["oldest"] = min(result["oldest"] or day.isoformat(), day.isoformat())
        if (since and day < since) or (until and day > until):
            continue
        parser = Changes()
        parser.feed(item.findtext("{http://purl.org/rss/1.0/modules/content/}encoded") or item.findtext("description") or "")
        parser.close()
        changes = []
        for change in parser.changes:
            pages = connector_pages(change["links"])
            cats = categories_of(change, pages)
            if a.category and not set(a.category) & set(cats):
                continue
            if pattern and not (pattern.search(change["text"]) or (change["section"] and pattern.search(change["section"]))):
                continue
            if connectors and not any(
                (want and want & pages) or (rx and (rx.search(change["text"]) or (change["section"] and rx.search(change["section"]))))
                for want, _, rx in connectors
            ):
                continue
            changes.append({
                "section": change["section"],
                "text": change["text"],
                "categories": cats,
                "connector_pages": sorted(pages),
                "links": change["links"],
            })
        if changes:
            result["days"].append({"date": day.isoformat(), "link": item.findtext("link"), "changes": changes})
    result["days"].sort(key=lambda d: d["date"], reverse=True)
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
