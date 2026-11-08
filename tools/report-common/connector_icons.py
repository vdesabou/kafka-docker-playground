#!/usr/bin/env python3
"""The icon of a connector in the 🔌 Connectors cards of the log report: the icon of the examples that use its class in
docs/content-template.md (the one of the website, images/icons/ of this repository).

  python3 tools/report-common/connector_icons.py
      writes connector_icons.json next to this file from docs/content-template.md and the connector.class /
      connection.url of the example scripts (connect/, ccloud/): run it again when an example or an icon is added

The JSON is committed because analyze logs also runs from a sparse clone (scripts, tools, cfk-analysis) without the
examples nor the icons: the report points to the icons on GitHub, like the website.

  classes  short class name -> icon, when most of the examples of that class have the same icon (S3SinkConnector: s3.png)
  jdbc     scheme of a jdbc: connection.url -> icon, for the classes shared by many databases (JdbcSinkConnector…)

A JDBC class without a majority icon (JdbcSinkConnector: oracle, mysql, postgresql… examples) gets the generic jdbc.png,
replaced by the icon of the database when the logs show its connection.url.
"""
import collections
import glob
import json
import os
import re
import sys
from typing import Optional

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MAP_FILE = os.path.join(HERE, "connector_icons.json")
# raw.githubusercontent.com directly: github.com/<repo>/raw/ is only a redirect to it (and answered 504 on 2026-11-08)
ICON_URL = "https://raw.githubusercontent.com/vdesabou/kafka-docker-playground/master/images/icons/"
JDBC_ICON = "jdbc.png"

_MAP = None


def _load() -> dict:
    global _MAP
    if _MAP is None:
        try:
            with open(MAP_FILE, encoding="utf-8") as fh:
                _MAP = json.load(fh)
        except (OSError, ValueError):
            _MAP = {"classes": {}, "jdbc": {}}
    return _MAP


def jdbc_scheme(url: Optional[str]) -> Optional[str]:
    """jdbc:oracle:thin:@… -> oracle, jdbc:jtds:sqlserver://… -> jtds"""
    m = re.match(r"^\s*jdbc:([a-z0-9]+)", url or "", re.I)
    return m.group(1).lower() if m else None


def icon_url(cls: Optional[str], url: Optional[str] = None) -> Optional[str]:
    """the URL of the icon of a connector (its class, short or full, and its connection.url), None when unknown"""
    m = _load()
    scheme = jdbc_scheme(url)
    short = (cls or "").split(".")[-1]
    name = (m["jdbc"].get(scheme) if scheme else None) or m["classes"].get(short)
    # a JDBC class unknown to the examples (another vendor's, a newer one): the generic JDBC icon
    if not name and "jdbc" in short.lower():
        name = JDBC_ICON
    return ICON_URL + name if name else None


def build() -> dict:
    icons = {}
    with open(os.path.join(ROOT, "docs", "content-template.md"), encoding="utf-8") as fh:
        for line in fh:
            m = re.search(r'images/icons/([^"]+)".*?:((?:connect|ccloud)/[^:]+):\s*$', line)
            if m:
                icons[m.group(2)] = m.group(1)
    classes = collections.defaultdict(collections.Counter)
    schemes = collections.defaultdict(collections.Counter)
    for folder, icon in icons.items():
        for script in glob.glob(os.path.join(ROOT, folder, "*.sh")):
            with open(script, encoding="utf-8", errors="ignore") as fh:
                text = fh.read()
            for cls in set(re.findall(r'"connector\.class"\s*:\s*"([^"$]+)"', text)):
                classes[cls.split(".")[-1]][icon] += 1
            for scheme in set(re.findall(r'"connection\.url"\s*:\s*"jdbc:([a-z0-9]+)', text, re.I)):
                schemes[scheme.lower()][icon] += 1

    def majority(counter: collections.Counter) -> Optional[str]:
        # only an icon that most of the examples share: JdbcSinkConnector (oracle, mysql, postgresql…) gets none
        icon, n = counter.most_common(1)[0]
        return icon if n * 2 > sum(counter.values()) else None

    out = {"classes": {}, "jdbc": {}}
    for cls, counter in sorted(classes.items()):
        if majority(counter):
            out["classes"][cls] = majority(counter)
        elif "jdbc" in cls.lower():
            out["classes"][cls] = JDBC_ICON
    for scheme, counter in sorted(schemes.items()):
        if majority(counter):
            out["jdbc"][scheme] = majority(counter)
    return out


def main() -> int:
    out = build()
    with open(MAP_FILE, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print(f"{MAP_FILE}: {len(out['classes'])} classes, {len(out['jdbc'])} jdbc schemes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
