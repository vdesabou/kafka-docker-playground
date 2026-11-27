#!/usr/bin/env python3
"""
The support areas of the Academy exercises (docs/academy.md), from one source: the "👥 Support area: …" line at the top
of the "🤯 Details" tab of each exercise (its first area, then the others). From it, this script writes:

- the Area column of the index of docs/academy.md,
- its "🧭 By support area" section (the exercises of each area, in italics where it is not their first area),
- the "🧑‍🎓 Academy exercises" section of each area page (docs/area-*.md).

Run it after adding an exercise or changing its area (idempotent):

    python3 -I scripts/academy-support-areas.py

An exercise without a "👥 Support area:" line, or with an unknown area, is an error (exit 1).
"""

import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ACADEMY = os.path.join(ROOT, "docs", "academy.md")

# the areas of docs/areas.md: (short name in the Area column, title of the area page, area page)
AREAS = {
    "connect": ("🔗 Connect", "🔗 Connect", "area-connect.md"),
    "core": ("🖥️ Brokers & clients", "🖥️ Brokers, clients and observability", "area-core-observability.md"),
    "streams": ("🌊 Streams, schemas & non-Java", "🌊 Streams, schemas and non-Java clients", "area-streams-schema-registry.md"),
    "platform": ("🛡️ Platform & security", "🛡️ Platform, security and Cloud infra", "area-platform-security.md"),
}
# what the "👥 Support area:" line may say for each area: its short name, the title of its page, or an older label
ALIASES = {
    "connect": ["🔗 Connect", "🔌 Connect"],
    "core": ["🖥️ Brokers & clients", "🖥️ Brokers, clients and observability", "🧠 Core & Observability"],
    "streams": ["🌊 Streams, schemas & non-Java", "🌊 Streams, schemas and non-Java clients", "🌊 Streams, SR & Non-Java"],
    "platform": ["🛡️ Platform & security", "🛡️ Platform, security and Cloud infra", "🔐 Platform, Security & Cloud Infra"],
}
AREA_LINE = re.compile(r"^👥 Support area: (.+)$", re.M)


def area_of(label):
    for key, names in ALIASES.items():
        if label.strip() in names:
            return key
    return None


def slug(title):
    """the id docsify gives to a heading: lowercase, punctuation removed, spaces to dashes"""
    s = re.sub(r"[^\w\s-]", "", title.lower())
    return re.sub(r"\s", "-", s.strip())


def main():
    t = open(ACADEMY).read()
    # the exercises (### headings of the level sections), not the areas of the "By support area" section
    by_area_titles = {v[0] for v in AREAS.values()} | {v[1] for v in AREAS.values()} | {n for ns in ALIASES.values() for n in ns}
    exercises = []
    errors = []
    for m in re.finditer(r"^### (.+?)\n(.*?)(?=^### |^## |\Z)", t, re.S | re.M):
        title, body = m.group(1), m.group(2)
        if title in by_area_titles or "#### **🤯 Details**" not in body:
            continue
        line = AREA_LINE.search(body)
        if not line:
            errors.append(f"{title}: no '👥 Support area:' line in its Details tab")
            continue
        keys = [area_of(x) for x in line.group(1).split(" · ")]
        if None in keys:
            errors.append(f"{title}: unknown area in '{line.group(0)}' (one of: {', '.join(v[0] for v in AREAS.values())})")
            continue
        exercises.append((title, keys))
    if errors:
        print("\n".join("❌ " + e for e in errors), file=sys.stderr)
        sys.exit(1)
    areas_of = dict(exercises)

    # the "👥 Support area:" lines, with the short names
    def normalize(m):
        keys = [area_of(x) for x in m.group(1).split(" · ")]
        return "👥 Support area: " + " · ".join(AREAS[k][0] for k in keys)
    t = AREA_LINE.sub(normalize, t)

    # the index: | Level | Area | Exercise | … (the Area column added when missing)
    out, levels = [], {}
    for line in t.split("\n"):
        if line.startswith("| Level | Exercise |"):
            line = "| Level | Area | Exercise |" + line[len("| Level | Exercise |"):]
        elif line.startswith("| --- | --- | --- | --- |") and out and out[-1].startswith("| Level | Area |") and line.count("|") == 5:
            line = "| --- | --- | --- | --- | --- |"
        else:
            m = re.match(r"^\| (⭐+) \| (?:([^|\[]*?) \| )?\[(.+?)\]\(", line)
            if m and m.group(3) in areas_of:
                levels[m.group(3)] = m.group(1)
                rest = line[m.end(2) + 3 if m.group(2) is not None else len(f"| {m.group(1)} | "):]
                line = f"| {m.group(1)} | {' · '.join(AREAS[k][0] for k in areas_of[m.group(3)])} | {rest}"
        out.append(line)
    t = "\n".join(out)

    def items(key):
        first = [x for x, k in exercises if k[0] == key]
        other = [x for x, k in exercises if key in k[1:]]
        return [(x, True) for x in first] + [(x, False) for x in other]

    # the "🧭 By support area" section of docs/academy.md
    section = ["## 🧭 By support area", "",
               "The exercises by the GTS support area (skill-based routing) whose cases they look like, the areas of "
               "[🗺️ Start from your area](/areas.md). An exercise that belongs to two areas is listed in both, the second "
               "time in italics.", ""]
    for key, (short, page_title, page) in AREAS.items():
        section += [f"### {page_title}", "", f"The questions, commands and deep dives of this area: [{page_title}](/{page}).", ""]
        lst = items(key)
        if not lst:
            section.append("No exercise yet.")
        for x, first in lst:
            link = f"[{x}](/academy?id={slug(x)})"
            section.append(f"* {levels.get(x, '')} {link if first else '*' + link + '*'}")
        section.append("")
    block = "\n".join(section).rstrip("\n") + "\n"
    if "## 🧭 By support area" in t:
        t = re.sub(r"## 🧭 By support area\n.*?(?=\n## )", block, t, flags=re.S)
    else:
        t = t.replace("\n## ⭐ Beginner", "\n" + block + "\n## ⭐ Beginner", 1)
    open(ACADEMY, "w").write(t)

    # the "🧑‍🎓 Academy exercises" section of each area page, before its last section or at the end
    for key, (short, page_title, page) in AREAS.items():
        path = os.path.join(ROOT, "docs", page)
        p = open(path).read()
        lst = items(key)
        lines = ["## 🧑‍🎓 Academy exercises", "",
                 "Real issues of this area to reproduce and troubleshoot yourself, with the solution of each step hidden "
                 "until you ask for it ([🧑‍🎓 Playground Academy](/academy.md)):", ""]
        if not lst:
            lines.append("No exercise yet.")
        for x, first in lst:
            link = f"[{x}](/academy?id={slug(x)})"
            lines.append(f"* {levels.get(x, '')} {link}" + ("" if first else f" (also {AREAS[areas_of[x][0]][0]})"))
        sec = "\n".join(lines) + "\n"
        if "## 🧑‍🎓 Academy exercises" in p:
            p = re.sub(r"## 🧑‍🎓 Academy exercises\n.*?(?=\n## |\Z)", sec.rstrip("\n") + "\n", p, flags=re.S)
        else:
            p = p.rstrip("\n") + "\n\n" + sec
        open(path, "w").write(p)
    counts = ", ".join(f"{AREAS[k][0]} {len(items(k))}" for k in AREAS)
    print(f"✅ {len(exercises)} exercises: {counts}")


if __name__ == "__main__":
    main()
