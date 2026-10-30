#!/usr/bin/env python3
"""Libraries bundled in a connector plugin, and their changes between two versions of it.

Reads the lib/ folder of a plugin (downloaded by the playground). Each library comes from the
META-INF/maven/<group>/<artifact>/pom.properties files of the jars (a fat jar holds several: the
libraries shaded inside it are listed too, with the jar they're in), or from the jar file name when
the jar has no pom.properties.

With one --lib-dir: the list. With two: the diff (upgraded, downgraded, added, removed).
Prints a JSON document on stdout.
"""
import argparse
import json
import os
import re
import sys
import zipfile

FILENAME = re.compile(r"^(?P<artifact>.+?)-(?P<version>\d[\w.+-]*)\.jar$")


def version_key(v):
    parts = re.split(r"[.\-+_]", v or "")
    return [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in parts]


def read_pom_properties(z, name):
    props = {}
    for line in z.read(name).decode("utf-8", "replace").splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    return props


def libraries(lib_dir):
    libs = []
    for jar in sorted(f for f in os.listdir(lib_dir) if f.endswith(".jar")):
        path = os.path.join(lib_dir, jar)
        poms = []
        try:
            with zipfile.ZipFile(path) as z:
                for n in z.namelist():
                    if n.startswith("META-INF/maven/") and n.endswith("/pom.properties"):
                        p = read_pom_properties(z, n)
                        if p.get("artifactId") and p.get("version"):
                            poms.append(p)
        except (zipfile.BadZipFile, OSError) as e:
            print(f"⚠️ could not read {jar}: {e}", file=sys.stderr)
        m = FILENAME.match(jar)
        if not poms:
            libs.append({"artifact": m.group("artifact") if m else jar[:-4], "group": None,
                         "version": m.group("version") if m else None, "jar": jar, "source": "filename", "shaded": False})
            continue
        # the jar's own library: the pom.properties whose artifactId starts the file name, else the only one
        main = None
        for p in poms:
            if jar.startswith(p["artifactId"] + "-") or jar == p["artifactId"] + ".jar":
                main = p
                break
        if main is None and len(poms) == 1:
            main = poms[0]
        for p in poms:
            libs.append({"artifact": p["artifactId"], "group": p.get("groupId"), "version": p["version"], "jar": jar,
                         "source": "pom.properties", "shaded": p is not main})
        if main is None and m:
            # several libraries inside, none named like the jar: keep the jar itself too
            libs.append({"artifact": m.group("artifact"), "group": None, "version": m.group("version"), "jar": jar,
                         "source": "filename", "shaded": False})
    return libs


def by_artifact(libs):
    """artifact -> lib, the jar's own library winning over a copy shaded in another jar."""
    out = {}
    for lib in libs:
        key = lib["artifact"]
        if key not in out or (out[key]["shaded"] and not lib["shaded"]):
            out[key] = lib
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--lib-dir", action="append", required=True, help="lib/ folder; twice to compare")
    p.add_argument("--label", action="append", default=[], help="label of each --lib-dir")
    p.add_argument("--grep", help="case-insensitive regex on group:artifact and jar name")
    a = p.parse_args()

    rx = re.compile(a.grep, re.IGNORECASE) if a.grep else None

    def keep(lib):
        return not rx or rx.search(f"{lib['group'] or ''}:{lib['artifact']}") or rx.search(lib["jar"])

    labels = a.label + [os.path.basename(os.path.dirname(d.rstrip("/"))) for d in a.lib_dir[len(a.label):]]
    if len(a.lib_dir) == 1:
        libs = [lib for lib in libraries(a.lib_dir[0]) if keep(lib)]
        libs.sort(key=lambda l: (l["shaded"], l["artifact"].lower()))
        json.dump({"plugin": labels[0], "nb_jars": len({l["jar"] for l in libs}), "libraries": libs}, sys.stdout, indent=2)
        print()
        return

    old, new = by_artifact(libraries(a.lib_dir[0])), by_artifact(libraries(a.lib_dir[1]))
    changes = []
    for art in sorted(set(old) | set(new), key=str.lower):
        o, n = old.get(art), new.get(art)
        lib = n or o
        if not keep(lib):
            continue
        if o and n:
            if o["version"] == n["version"]:
                continue
            kind = "upgraded" if version_key(n["version"]) > version_key(o["version"]) else "downgraded"
        else:
            kind = "added" if n else "removed"
        changes.append({"artifact": art, "group": lib["group"], "change": kind,
                        "from": o["version"] if o else None, "to": n["version"] if n else None,
                        "from_jar": o["jar"] if o else None, "to_jar": n["jar"] if n else None,
                        "shaded": bool((n or o)["shaded"])})
    unchanged = sum(1 for art in set(old) & set(new) if old[art]["version"] == new[art]["version"] and keep(new[art]))
    json.dump({"from": labels[0], "to": labels[1], "changes": changes, "nb_unchanged": unchanged}, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
