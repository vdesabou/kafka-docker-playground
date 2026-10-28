#!/usr/bin/env python3
"""Changes of Confluent Platform versions, from the docs changelog feeds.

docs.confluent.io publishes one RSS feed per minor line of Confluent Platform
(https://docs.confluent.io/platform/8.3/release-notes/changelog.xml), one <item> per patch version. Each
item lists the commits of the community components (Common, Kafka, ksqlDB, REST Proxy, Schema Registry),
one <h4> per component and one <li> per commit. The feed of a line that does not exist redirects to an HTML
page: the lines are found by probing (x.y+1, then x+1.0).

Prints a JSON document on stdout (--format text: the same as playground prints it, used by the fzf preview
of the --tag picker); warnings go to stderr. Network answers are cached in --cache-dir for one day.
"""
import argparse
import html.parser
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

# fetch, cache and version helpers are shared with the connector plugin changelog (no __pycache__ in the repo)
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "connector-changelog"))
from changelog import cached_fetch, clean, vkey, warn  # noqa: E402

FEED = "https://docs.confluent.io/platform/{line}/release-notes/changelog.xml"
FIRST_LINE = (7, 4)  # oldest line with a feed
# no CVE ids in the feeds: security fixes are tagged [security], or are upgrades of libraries with frequent CVEs
SECURITY = re.compile(
    r"\[security\]|security (fix|issue|patch|update)|CVE-\d|vulnerab|(update|bump|upgrade).*(netty|jetty|jackson|log4j|logback|bouncycastle|nimbus|snappy"
    r"|zstd|protobuf|guava|commons-|vertx|avro|gson|okhttp|zookeeper|spring|tomcat)",
    re.IGNORECASE,
)
COMPONENTS = {
    "common": "Common",
    "kafka": "Kafka",
    "ksqldb": "ksqlDB",
    "rest-proxy": "REST Proxy",
    "schema-registry": "Schema Registry",
}


def line_of(version):
    k = vkey(version)
    return (k[0], k[1] if len(k) > 1 else 0)


def line_str(line):
    return f"{line[0]}.{line[1]}"


class Changes(html.parser.HTMLParser):
    """Commits of a version: [(component, title, short sha, url)], component = the enclosing <h4> (or <h3>)."""

    def __init__(self):
        super().__init__()
        self.changes = []
        self.heading, self.heading_buf = None, []
        self.component = "Other"
        self.in_li, self.li_buf, self.li_url = 0, [], None

    def handle_starttag(self, tag, attrs):
        if tag in ("h3", "h4"):
            self.heading, self.heading_buf = tag, []
        elif tag == "a" and self.heading:
            # the headerlink anchor ends the heading text
            self.end_heading()
        elif tag == "li":
            self.in_li += 1
            if self.in_li == 1:
                self.li_buf, self.li_url = [], None
        elif tag == "a" and self.in_li and self.li_url is None:
            self.li_url = dict(attrs).get("href")

    def end_heading(self):
        text = clean("".join(self.heading_buf))
        if text and (self.heading == "h4" or text != "Community Features"):
            self.component = text
        self.heading = None

    def handle_endtag(self, tag):
        if tag in ("h3", "h4") and self.heading:
            self.end_heading()
        elif tag == "li" and self.in_li:
            self.in_li -= 1
            if self.in_li == 0:
                text = clean("".join(self.li_buf))
                if text:
                    sha, sep, title = text.partition(" - ")
                    if not sep or " " in sha:
                        sha, title = "", text
                    self.changes.append((self.component, title, sha, self.li_url))

    def handle_data(self, data):
        if self.heading:
            self.heading_buf.append(data)
        elif self.in_li:
            self.li_buf.append(data)


def read_feed(line, cache_dir, force_refresh):
    """[(version, released, link, description)] of a minor line, or None when it has no feed."""
    url = FEED.format(line=line_str(line))
    body, _ = cached_fetch(url, cache_dir, force_refresh)
    if not body or "<rss" not in body[:500]:
        return None, url
    items = []
    for item in ET.fromstring(body).iter("item"):
        version = re.sub(r"^\s*Version\s+", "", item.findtext("title") or "").strip()
        description = item.findtext("description") or ""
        m = re.search(r"Released\s+([A-Za-z]+\s+\d{4})", description)
        items.append((version, m.group(1) if m else None, item.findtext("link"), description))
    return items, url


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--from", dest="from_version", help="exclusive lower bound (the version in use)")
    p.add_argument("--to", dest="to_version", help="inclusive upper bound, default: latest published")
    p.add_argument("--version", help="only this version")
    p.add_argument("--same-line", action="store_true", help="without --to, stop at the latest patch of the --from line")
    p.add_argument("--component", action="append", choices=sorted(COMPONENTS), help="only these components")
    p.add_argument("--grep", help="case-insensitive regex, keep only the matching changes")
    p.add_argument("--security", action="store_true", help="keep only the security related changes")
    p.add_argument("--format", choices=["json", "text"], default="json")
    p.add_argument("--cache-dir", default="/tmp/cp-changelog")
    p.add_argument("--force-refresh", action="store_true")
    a = p.parse_args()
    if a.version:
        a.from_version = a.to_version = a.version
    include_from = bool(a.version)
    for v in (a.from_version, a.to_version):
        if v and not re.match(r"^\d+\.\d+", v):
            raise SystemExit(f"❌ {v} is not a Confluent Platform version (x.y.z)")
    if a.from_version and a.to_version and vkey(a.to_version) < vkey(a.from_version):
        raise SystemExit(f"❌ --from {a.from_version} must be lower than --to {a.to_version}")
    pattern = re.compile(a.grep, re.IGNORECASE) if a.grep else None
    components = {COMPONENTS[c] for c in a.component} if a.component else None

    # minor lines to read: from the line of --from (or of --to) up to the line of --to, or the latest one
    if a.to_version:
        last = line_of(a.to_version)
    elif a.same_line and a.from_version:
        last = line_of(a.from_version)
    else:
        last = None
    first = line_of(a.from_version) if a.from_version else (last or (8, 0))
    first = max(first, FIRST_LINE)

    result = {
        "from": a.from_version,
        "to": a.to_version,
        "grep": a.grep,
        "security": a.security,
        "components": sorted(components) if components else None,
        "latest": None,
        "up_to_date": False,
        "feeds": [],
        "versions": [],
    }
    feeds, line, missing = {}, first, []
    while last is None or line <= last:
        items, url = read_feed(line, a.cache_dir, a.force_refresh)
        if items is not None:
            feeds[line] = (items, url)
            line = (line[0], line[1] + 1)
            continue
        missing.append(url)
        # x.y+1 has no feed: try x+1.0, and stop when that one has no feed either
        if line[1] == 0 and line != first:
            break
        line = (line[0] + 1, 0)
    if not feeds:
        for url in missing:
            warn(f"⚠️ no changelog feed: {url}")
        output(result, a.format)
        return
    if not a.from_version and not a.to_version:
        # nothing asked: the latest line only
        feeds = {max(feeds): feeds[max(feeds)]}

    all_versions = [it for line in sorted(feeds) for it in feeds[line][0]]
    result["latest"] = max((v for v, *_ in all_versions), key=vkey)
    to_version = a.to_version or result["latest"]
    result["to"] = to_version
    if a.from_version and not a.to_version and vkey(to_version) <= vkey(a.from_version):
        result["up_to_date"] = True
        output(result, a.format)
        return

    for line in sorted(feeds):
        items, url = feeds[line]
        result["feeds"].append(url)
        for version, released, link, description in items:
            k = vkey(version)
            if k > vkey(to_version):
                continue
            if a.from_version and (k < vkey(a.from_version) or (k == vkey(a.from_version) and not include_from)):
                continue
            parser = Changes()
            parser.feed(description)
            changes = [
                {"component": comp, "title": title, "commit": sha, "url": href, "security": bool(SECURITY.search(title))}
                for comp, title, sha, href in parser.changes
                if (components is None or comp in components) and (pattern is None or pattern.search(title))
            ]
            if a.security:
                changes = [c for c in changes if c["security"]]
            if (pattern or components or a.security) and not changes:
                continue
            result["versions"].append({"version": version, "released": released, "link": link, "changes": changes})
    result["versions"].sort(key=lambda e: vkey(e["version"]), reverse=True)
    output(result, a.format)


def output(result, fmt):
    if fmt == "json":
        print(json.dumps(result, indent=2))
        return
    if result["up_to_date"]:
        print(f"✅ {result['from']} is the latest Confluent Platform version with a changelog ({result['latest']})")
        return
    if not result["versions"]:
        print("🤷 no change for this version" if result["feeds"] else "📜 no changelog feed for this version")
    for v in result["versions"]:
        print(f"🔢 {v['version']} - 📅 released: {v['released'] or '<unknown>'} - {len(v['changes'])} change(s)")
        component = None
        for c in v["changes"]:
            if c["component"] != component:
                component = c["component"]
                count = sum(1 for x in v["changes"] if x["component"] == component)
                print(f"  🧩 {component} ({count})")
            sha = f" ({c['commit']})" if c["commit"] else ""
            print(f"     • {c['title']}{sha}")
    for f in result["feeds"]:
        print(f"🌐 changelog: {f[:-len('.xml')]}.html")


if __name__ == "__main__":
    main()
