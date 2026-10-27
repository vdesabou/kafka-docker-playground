#!/usr/bin/env python3
"""Release notes of a Confluent Hub connector plugin between two versions, from the docs changelog feeds.

docs.confluent.io publishes one RSS feed per minor line of a connector
(https://docs.confluent.io/kafka-connectors/s3-sink/12.1/changelog.xml), one <item> per version.
The feed location is not in the plugin manifest: it is derived from the documentation_url of the
manifest, after following its redirects (many manifests still use old URL forms).

Prints a JSON document on stdout (--format text: the same as playground prints it, used by the fzf
preview of the --connector-tag picker); warnings go to stderr. Network answers are cached in --cache-dir
for one day.
"""
import argparse
import html
import html.parser
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

HUB = "https://api.hub.confluent.io/api/plugins"
CACHE_TTL = 24 * 3600
USER_AGENT = "kafka-docker-playground"


def warn(msg):
    print(msg, file=sys.stderr)


def vkey(version):
    """Sortable key of a version: its leading numbers (10.5.7-rc1 -> (10, 5, 7))."""
    nums = re.findall(r"\d+", version.split("-")[0])
    return tuple(int(n) for n in nums) if nums else (0,)


def minor(version):
    k = vkey(version)
    return f"{k[0]}.{k[1] if len(k) > 1 else 0}"


def cached_fetch(url, cache_dir, force_refresh):
    """Body and final URL of url (redirects followed), cached; (None, None) on HTTP error."""
    name = re.sub(r"[^A-Za-z0-9._-]", "_", url)
    path = os.path.join(cache_dir, name)
    if not force_refresh and os.path.exists(path) and time.time() - os.path.getmtime(path) < CACHE_TTL:
        with open(path, encoding="utf-8") as f:
            entry = json.load(f)
        return entry["body"], entry["final_url"]
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            final_url = resp.geturl()
    except urllib.error.HTTPError as e:
        warn(f"⚠️ {url}: HTTP {e.code}")
        body, final_url = None, None
    except (urllib.error.URLError, TimeoutError) as e:
        raise SystemExit(f"❌ {url}: {e}")
    os.makedirs(cache_dir, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"body": body, "final_url": final_url}, f)
    return body, final_url


def feed_base(documentation_url):
    """https://docs.confluent.io/kafka-connectors/<slug> from a resolved documentation URL, or None.

    The slug can be nested (kafka-connectors/tibco/sink/current/index.html): it ends before the
    "current" or "<major>.<minor>" segment.
    """
    m = re.match(r"https?://docs\.confluent\.io/kafka-connectors/(.+)", documentation_url or "")
    if not m:
        return None
    slug = []
    for part in m.group(1).split("/"):
        if part == "current" or re.fullmatch(r"\d+\.\d+", part) or not part or "." in part:
            break
        slug.append(part)
    return "https://docs.confluent.io/kafka-connectors/" + "/".join(slug) if slug else None


class ListItems(html.parser.HTMLParser):
    """Text of each top-level <li> of a release notes fragment (nested lists are kept in their parent)."""

    def __init__(self):
        super().__init__()
        self.items, self.depth, self.buf = [], 0, []

    def handle_starttag(self, tag, attrs):
        if tag == "li":
            self.depth += 1
            if self.depth > 1:
                self.buf.append(" ")

    def handle_endtag(self, tag):
        if tag == "li":
            self.depth -= 1
            if self.depth == 0:
                self.items.append(clean("".join(self.buf)))
                self.buf = []

    def handle_data(self, data):
        if self.depth > 0:
            self.buf.append(data)


def clean(text):
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def changes_of(fragment):
    parser = ListItems()
    parser.feed(fragment or "")
    items = [i for i in parser.items if i]
    if not items:
        text = clean(re.sub(r"<[^>]+>", " ", fragment or ""))
        items = [text] if text else []
    return items


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--connector-plugin", required=True, help="owner/name on Confluent Hub")
    p.add_argument("--from", dest="from_version", help="exclusive lower bound (the version in use)")
    p.add_argument("--to", dest="to_version", help="inclusive upper bound, default: latest on Hub")
    p.add_argument("--include-from", action="store_true", help="--from is included")
    p.add_argument("--version", help="only this version (same as --from X --to X --include-from)")
    p.add_argument("--grep", help="case-insensitive regex, keep only the matching changes")
    p.add_argument("--format", choices=["json", "text"], default="json")
    p.add_argument("--cache-dir", default="/tmp/connector-plugin-changelog")
    p.add_argument("--force-refresh", action="store_true")
    a = p.parse_args()
    if a.version:
        a.from_version = a.to_version = a.version.lstrip("v")
        a.include_from = True

    owner, _, name = a.connector_plugin.partition("/")
    if not owner or not name:
        raise SystemExit(f"❌ --connector-plugin must be owner/name, got {a.connector_plugin}")
    pattern = re.compile(a.grep, re.IGNORECASE) if a.grep else None

    body, _ = cached_fetch(f"{HUB}/{owner}/{name}/versions", a.cache_dir, a.force_refresh)
    try:
        hub_versions = json.loads(body) if body else []
    except json.JSONDecodeError:
        hub_versions = []
    if not hub_versions:
        raise SystemExit(f"❌ could not get versions of {a.connector_plugin} from Confluent Hub")
    hub_versions.sort(key=lambda v: vkey(v["version"]))
    release_dates = {v["version"]: v.get("release_date") for v in hub_versions}

    to_version = a.to_version or hub_versions[-1]["version"]
    def after_from(version):
        if not a.from_version:
            return True
        return vkey(version) >= vkey(a.from_version) if a.include_from else vkey(version) > vkey(a.from_version)

    up_to_date = bool(a.from_version and not a.to_version and not after_from(to_version))
    if a.from_version and a.to_version and not after_from(to_version):
        raise SystemExit(f"❌ --from {a.from_version} must be lower than --to {to_version}")

    # documentation_url of the most recent manifest, resolved to the current docs URL
    manifest_url = hub_versions[-1].get("manifest_url")
    manifest_body, _ = cached_fetch(manifest_url, a.cache_dir, a.force_refresh) if manifest_url else (None, None)
    documentation_url = json.loads(manifest_body).get("documentation_url") if manifest_body else None
    resolved = cached_fetch(documentation_url, a.cache_dir, a.force_refresh)[1] if documentation_url else None
    base = feed_base(resolved)

    result = {
        "connector_plugin": a.connector_plugin,
        "from": a.from_version,
        "to": to_version,
        "grep": a.grep,
        "up_to_date": up_to_date,
        "documentation_url": documentation_url,
        "feeds": [],
        "versions": [],
    }
    if up_to_date:
        output(result, a.format)
        return
    if not base:
        warn(f"⚠️ no changelog feed for {a.connector_plugin}: its documentation ({documentation_url} -> {resolved}) is not a docs.confluent.io/kafka-connectors page")
        output(result, a.format)
        return

    # minor lines to read: the ones of the Hub versions in range, plus the ones of the bounds
    if a.from_version:
        in_range = [v["version"] for v in hub_versions if after_from(v["version"]) and vkey(v["version"]) <= vkey(to_version)]
        lines = {minor(v) for v in in_range} | {minor(to_version)}
    else:
        lines = {minor(to_version)}

    entries = {}
    for line in sorted(lines, key=vkey):
        url = f"{base}/{line}/changelog.xml"
        feed, _ = cached_fetch(url, a.cache_dir, a.force_refresh)
        if not feed or "<rss" not in feed[:500]:
            warn(f"⚠️ no changelog feed for the {line} line: {url}")
            continue
        result["feeds"].append(url)
        for item in ET.fromstring(feed).iter("item"):
            version = re.sub(r"^\s*Version\s+", "", item.findtext("title") or "").strip()
            k = vkey(version)
            if k > vkey(to_version) or not after_from(version):
                continue
            changes = changes_of(item.findtext("description"))
            if pattern:
                changes = [c for c in changes if pattern.search(c)]
                if not changes:
                    continue
            entries[version] = {
                "version": version,
                "release_date": release_dates.get(version),
                "link": item.findtext("link"),
                "changes": changes,
            }
    result["versions"] = sorted(entries.values(), key=lambda e: vkey(e["version"]), reverse=True)
    output(result, a.format)


def output(result, fmt):
    if fmt == "json":
        print(json.dumps(result, indent=2))
        return
    if result["up_to_date"]:
        print(f"✅ {result['from']} is the latest version on Confluent Hub")
    elif not result["versions"]:
        print("🤷 no release notes for this version" if result["feeds"] else "📜 no changelog feed for this connector plugin")
    for v in result["versions"]:
        print(f"🔢 v{v['version']} - 📅 release date: {v['release_date'] or '<unknown>'}")
        for c in v["changes"]:
            print(f"   • {c}")
    for f in result["feeds"]:
        print(f"🌐 changelog: {f[:-len('.xml')]}.html")


if __name__ == "__main__":
    main()
