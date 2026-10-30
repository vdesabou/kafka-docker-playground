#!/usr/bin/env python3
"""Jars and classes of a connector plugin, for playground connector-plugin search-jar.

Reads the lib/ folder of a plugin (already downloaded by the playground) and answers:
- which jars it ships
- which jar holds a class (--class): exact simple name or fully qualified name first, then a
  case-insensitive substring when nothing has that exact name
- with --worker-index (class<TAB>jar of every jar on the classpath of the connect worker, plus the
  plugin isolation patterns of that worker): which classes are on both sides, and which copy Connect
  loads. A class of the plugin matching the worker's parent-first patterns (org.apache.kafka.*,
  org.slf4j.*, java*...) is always loaded from the worker: the plugin's copy is ignored, the classic
  cause of NoSuchMethodError / NoClassDefFoundError.

Prints a JSON document on stdout; method signatures are added by --javap (a command prefix).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import zipfile

MAX_SIGNATURES = 5


def classes_of_jar(path):
    try:
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
    except (zipfile.BadZipFile, OSError) as e:
        print(f"⚠️ could not read {path}: {e}", file=sys.stderr)
        return []
    out = []
    for n in names:
        if not n.endswith(".class") or n.startswith("META-INF/") or n.endswith("module-info.class") or n.endswith("package-info.class"):
            continue
        out.append(n[:-len(".class")].replace("/", "."))
    return out


def simple_name(cls):
    return cls.rsplit(".", 1)[-1]


def is_anonymous(cls):
    return re.search(r"\$\d+(\$|$)", cls) is not None


def find(query, index):
    """index: list of (class, jar). Returns (mode, matches)."""
    if "." in query:
        exact = [(c, j) for c, j in index if c == query]
    else:
        exact = [(c, j) for c, j in index if simple_name(c) == query or simple_name(c).split("$")[-1] == query]
    if exact:
        return "exact", exact
    q = query.lower()
    return "substring", [(c, j) for c, j in index if q in c.lower() and not is_anonymous(c)]


def java_to_python_regex(p):
    # the patterns of PluginUtils only use constructs both engines share; possessive quantifiers would not be
    return re.compile(p)


def loaded_from_worker(cls, patterns):
    """Same rule as PluginUtils.shouldLoadInIsolation: parent-first when the first pattern matches and no include pattern does."""
    if not patterns:
        return None
    exclude, includes = patterns[0], patterns[1:]
    return bool(exclude.match(cls)) and not any(i.match(cls) for i in includes)


def javap(prefix, jar, cls):
    if not prefix:
        return None
    try:
        if prefix == ["docker"]:
            # no local JDK: run javap in a JDK image, the jar on stdin (no volume to share)
            cmd = ["docker", "run", "--rm", "-i", os.environ.get("PG_JAVAP_IMAGE", "eclipse-temurin:21-jdk"),
                   "sh", "-c", f"cat > /tmp/x.jar && javap -classpath /tmp/x.jar '{cls}'"]
            with open(jar, "rb") as f:
                r = subprocess.run(cmd, stdin=f, capture_output=True, text=True, timeout=300)
        else:
            r = subprocess.run(prefix + ["-classpath", jar, cls], capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"⚠️ javap failed: {e}"
    return (r.stdout or r.stderr).rstrip()


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--lib-dir", required=True, help="lib/ folder of the plugin")
    p.add_argument("--class", dest="cls", help="class to search: simple name, fully qualified name, or part of it")
    p.add_argument("--worker-index", help="file with class<TAB>jar lines of the worker, and PATTERN<TAB><regex> lines")
    p.add_argument("--worker-jars-dir", help="folder with copies of worker jars, for javap on the worker side")
    p.add_argument("--javap", nargs="*", help="javap command (javap, or docker)")
    p.add_argument("--max-shadowed", type=int, default=15)
    a = p.parse_args()

    jars = sorted(f for f in os.listdir(a.lib_dir) if f.endswith(".jar"))
    plugin_index = []
    for jar in jars:
        for c in classes_of_jar(os.path.join(a.lib_dir, jar)):
            plugin_index.append((c, jar))

    result = {"lib_dir": a.lib_dir, "jars": jars, "nb_classes": len(plugin_index)}

    worker_index, patterns = [], []
    if a.worker_index:
        with open(a.worker_index, encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t", 1)
                if len(parts) != 2:
                    continue
                if parts[0] == "PATTERN":
                    try:
                        patterns.append(java_to_python_regex(parts[1]))
                    except re.error as e:
                        print(f"⚠️ could not use isolation pattern {parts[1][:60]}…: {e}", file=sys.stderr)
                else:
                    worker_index.append((parts[0], parts[1]))
        if not patterns:
            print("⚠️ plugin isolation patterns not found in the worker image: which copy wins is not shown", file=sys.stderr)

    if a.cls:
        mode, matches = find(a.cls, plugin_index)
        result["class_query"] = a.cls
        result["match_mode"] = mode
        out = []
        for c, j in matches:
            m = {"class": c, "jar": j}
            if worker_index:
                m["loaded_from_worker"] = loaded_from_worker(c, patterns)
            out.append(m)
        if a.javap is not None and 0 < len(out) <= MAX_SIGNATURES:
            for m in out:
                m["signatures"] = javap(a.javap, os.path.join(a.lib_dir, m["jar"]), m["class"])
        result["matches"] = out
        if worker_index:
            wmode, wmatches = find(a.cls, worker_index)
            wout = []
            for c, j in wmatches:
                m = {"class": c, "jar": j}
                local = os.path.join(a.worker_jars_dir, os.path.basename(j)) if a.worker_jars_dir else None
                if a.javap is not None and local and os.path.exists(local) and len(wmatches) <= MAX_SIGNATURES:
                    m["signatures"] = javap(a.javap, local, c)
                wout.append(m)
            result["worker_matches"] = wout
            result["worker_match_mode"] = wmode

    if worker_index:
        worker_jar_of = {}
        for c, j in worker_index:
            worker_jar_of.setdefault(c, j)
        shadowed, isolated = {}, {}
        for c, j in plugin_index:
            if c not in worker_jar_of:
                continue
            key = (j, worker_jar_of[c])
            target = shadowed if loaded_from_worker(c, patterns) else isolated
            target.setdefault(key, []).append(c)

        def summarize(groups, limit):
            rows = [{"plugin_jar": pj, "worker_jar": wj, "same_jar": pj == os.path.basename(wj),
                     "nb_classes": len(cs), "example": sorted(cs)[0]}
                    for (pj, wj), cs in groups.items()]
            # different jars first: a same jar on both sides is harmless
            rows.sort(key=lambda r: (r["same_jar"], -r["nb_classes"]))
            return rows[:limit] if limit else rows

        result["worker"] = {
            "nb_jars": len({j for _, j in worker_index}),
            "nb_classes": len(worker_jar_of),
            "patterns_found": bool(patterns),
            "shadowed": summarize(shadowed, a.max_shadowed),
            "nb_shadowed_jars": len({pj for pj, _ in shadowed}),
            "nb_shadowed_classes": sum(len(v) for v in shadowed.values()),
            "isolated_duplicates": summarize(isolated, a.max_shadowed),
            "nb_isolated_duplicate_classes": sum(len(v) for v in isolated.values()),
        }

    json.dump(result, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
