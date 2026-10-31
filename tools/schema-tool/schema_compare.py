#!/usr/bin/env python3
"""Compares two `playground schema export` folders, for `playground schema compare`.

    python3 -I schema_compare.py --left <folder> --left-label europe --right <folder> --right-label us [--json]

Reports the subjects only on one side, and for the subjects on both: missing versions, versions whose schema id or
content differ, and subject-level compatibility differences. Context prefixes (:.europe:orders-value) are ignored.

Exit code: 0 identical, 1 different, 2 unreadable input.
"""

import argparse
import json
import os
import re
import sys

CONTEXT_PREFIX = re.compile(r"^:\.[^:]*:")


def load(folder):
    with open(os.path.join(folder, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    subjects = {}
    for s in manifest.get("subjects", []):
        name = CONTEXT_PREFIX.sub("", s["subject"])
        versions = {}
        for v in s.get("versions", []):
            with open(os.path.join(folder, v["file"]), encoding="utf-8") as f:
                text = f.read()
            versions[v["version"]] = {"id": v.get("id"), "schema": normalize(text, v.get("schemaType", "AVRO")),
                                      "type": v.get("schemaType", "AVRO")}
        subjects[name] = {"compatibility": s.get("compatibility"), "versions": versions}
    return manifest, subjects


def normalize(text, schema_type):
    if schema_type == "PROTOBUF":
        return re.sub(r"\s+", " ", text).strip()
    try:
        return json.dumps(json.loads(text), sort_keys=True, separators=(",", ":"))
    except ValueError:
        return text.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--left", required=True)
    ap.add_argument("--left-label", default="left")
    ap.add_argument("--right", required=True)
    ap.add_argument("--right-label", default="right")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    try:
        _ml, left = load(args.left)
        _mr, right = load(args.right)
    except (OSError, ValueError, KeyError) as e:
        print(f"❌ can't read the exports: {e}", file=sys.stderr)
        return 2

    only_left = sorted(set(left) - set(right))
    only_right = sorted(set(right) - set(left))
    differences = []
    same = []
    for name in sorted(set(left) & set(right)):
        a, b = left[name], right[name]
        diffs = []
        for v in sorted(set(a["versions"]) | set(b["versions"])):
            va, vb = a["versions"].get(v), b["versions"].get(v)
            if va and not vb:
                diffs.append({"version": v, "issue": f"missing in {args.right_label}", "id": va["id"]})
            elif vb and not va:
                diffs.append({"version": v, "issue": f"missing in {args.left_label}", "id": vb["id"]})
            else:
                if va["schema"] != vb["schema"]:
                    diffs.append({"version": v, "issue": "different schema", "left_id": va["id"], "right_id": vb["id"]})
                elif va["id"] != vb["id"]:
                    diffs.append({"version": v, "issue": "same schema, different id", "left_id": va["id"],
                                  "right_id": vb["id"]})
        if (a["compatibility"] or None) != (b["compatibility"] or None):
            diffs.append({"issue": "different subject-level compatibility", "left": a["compatibility"],
                          "right": b["compatibility"]})
        if diffs:
            differences.append({"subject": name, "differences": diffs})
        else:
            same.append(name)

    identical = not only_left and not only_right and not differences
    if args.json:
        print(json.dumps({"left": args.left_label, "right": args.right_label, "identical": identical,
                          "only_in_left": only_left, "only_in_right": only_right, "identical_subjects": same,
                          "different_subjects": differences}, indent=2))
        return 0 if identical else 1

    print(f"🔀 {args.left_label}  ↔  {args.right_label}")
    for name in same:
        n = len(left[name]["versions"])
        print(f"   ✅ {name}: {n} version(s), same schemas and ids")
    for name in only_left:
        print(f"   ⬅️ {name}: only in {args.left_label} ({len(left[name]['versions'])} version(s))")
    for name in only_right:
        print(f"   ➡️ {name}: only in {args.right_label} ({len(right[name]['versions'])} version(s))")
    for d in differences:
        print(f"   ❌ {d['subject']}:")
        for x in d["differences"]:
            if "version" not in x:
                print(f"      🛡️ {x['issue']}: {x['left']} ↔ {x['right']}")
            elif "left_id" in x:
                print(f"      v{x['version']}: {x['issue']} (id {x['left_id']} ↔ id {x['right_id']})")
            else:
                print(f"      v{x['version']}: {x['issue']} (id {x['id']})")
    print("")
    if identical:
        print(f"🧭 identical: {len(same)} subject(s)")
    else:
        ids = sum(1 for d in differences for x in d["differences"] if x.get("issue") == "same schema, different id")
        print(f"🧭 {len(same)} identical, {len(differences)} different, {len(only_left)} only in {args.left_label}, "
              f"{len(only_right)} only in {args.right_label}"
              + (f": {ids} version(s) with another id (records written on one side don't decode on the other "
                 f"with the same id)" if ids else ""))
    return 0 if identical else 1


if __name__ == "__main__":
    sys.exit(main())
