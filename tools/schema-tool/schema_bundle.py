#!/usr/bin/env python3
"""Turns what a customer can send about their Schema Registry into one import plan, for `playground schema import`.

    python3 -I schema_bundle.py plan --input <folder | manifest.json | schemas.json | _schemas dump> [--subject-prefix p]

Inputs:
  - a folder written by `playground schema export` (manifest.json + one file per version)
  - a JSON array of versions: `curl <registry>/schemas?deleted=false`, `playground schema get --json`
    (objects with subject, version, id, schemaType, schema, references…), or `curl <registry>/subjects/<s>/versions/<v>`
    objects concatenated in an array
  - a dump of the _schemas topic: `playground topic consume -t _schemas --json`, or kafka-console-consumer with
    --property print.key=true --property print.timestamp=true (the last state of every live version is kept)

Prints the plan as JSON on stdout:
  {"source": "...", "format": "...", "global": {"compatibility": ..., "mode": ...},
   "subjects": {"<subject>": {"compatibility": ..., "mode": ..., "alias": ...}},
   "versions": [{"subject", "version", "id", "schemaType", "schema", "references", "metadata", "ruleSet"}, ...]}
versions are sorted by id: a referenced schema is registered before the schemas that reference it.

Exit code: 0, 2 on unreadable input.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from schema_history import parse_line  # noqa: E402

EXTENSIONS = {"AVRO": "avsc", "JSON": "json", "PROTOBUF": "proto"}


def version_entry(obj):
    return {
        "subject": obj["subject"],
        "version": obj.get("version"),
        "id": obj.get("id"),
        "schemaType": obj.get("schemaType") or "AVRO",
        "schema": obj.get("schema"),
        "references": obj.get("references") or [],
        "metadata": obj.get("metadata"),
        "ruleSet": obj.get("ruleSet"),
    }


def from_manifest(path):
    folder = os.path.dirname(os.path.abspath(path))
    with open(path, encoding="utf-8") as f:
        manifest = json.load(f)
    versions = []
    subjects = {}
    for s in manifest.get("subjects", []):
        subjects[s["subject"]] = {k: s.get(k) for k in ("compatibility", "mode", "alias")}
        for v in s.get("versions", []):
            with open(os.path.join(folder, v["file"]), encoding="utf-8") as f:
                schema = f.read()
            if v.get("schemaType", "AVRO") != "PROTOBUF":
                # stored pretty-printed, sent compact
                schema = json.dumps(json.loads(schema), separators=(",", ":"))
            versions.append(version_entry({**v, "subject": s["subject"], "schema": schema}))
    return {"format": "playground schema export", "global": manifest.get("global", {}), "subjects": subjects,
            "versions": versions}


def from_array(data):
    versions = [version_entry(o) for o in data
                if isinstance(o, dict) and o.get("subject") and o.get("schema") is not None and not o.get("deleted")]
    subjects = {v["subject"]: {"compatibility": None, "mode": None, "alias": None} for v in versions}
    return {"format": "JSON array of versions", "global": {}, "subjects": subjects, "versions": versions}


def from_schemas_topic(records):
    live = {}
    configs = {}
    modes = {}
    for _ts, key, value in records:
        kt = key.get("keytype")
        subject = key.get("subject")
        if kt == "SCHEMA":
            k = (subject, key.get("version"))
            if value is None or value.get("deleted"):
                live.pop(k, None)
            else:
                live[k] = value
        elif kt == "DELETE_SUBJECT":
            last = (value or {}).get("version")
            for k in [k for k in live if k[0] == subject and (last is None or k[1] <= last)]:
                live.pop(k)
        elif kt == "CLEAR_SUBJECT":
            for k in [k for k in live if k[0] == subject]:
                live.pop(k)
        elif kt == "CONFIG":
            if value is None:
                configs.pop(subject, None)
            else:
                configs[subject] = value
        elif kt == "MODE":
            if value is None:
                modes.pop(subject, None)
            else:
                modes[subject] = value.get("mode")
    versions = [version_entry({**v, "subject": k[0], "version": k[1]}) for k, v in live.items()]
    subjects = {}
    for v in versions:
        cfg = configs.get(v["subject"]) or {}
        subjects[v["subject"]] = {"compatibility": cfg.get("compatibilityLevel"), "mode": modes.get(v["subject"]),
                                  "alias": cfg.get("alias")}
    glob = {"compatibility": (configs.get(None) or {}).get("compatibilityLevel"), "mode": modes.get(None)}
    return {"format": "_schemas topic dump", "global": glob, "subjects": subjects, "versions": versions}


def build_plan(path):
    if os.path.isdir(path):
        manifest = os.path.join(path, "manifest.json")
        if not os.path.isfile(manifest):
            raise ValueError(f"{path} has no manifest.json (not a 'playground schema export' folder)")
        return from_manifest(manifest)
    if os.path.basename(path) == "manifest.json":
        return from_manifest(path)
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    stripped = text.lstrip()
    if stripped.startswith("["):
        return from_array(json.loads(text))
    if stripped.startswith("{") and "\n" not in stripped.strip():
        obj = json.loads(text)
        if "subjects" in obj and "versions" not in obj:
            raise ValueError("this looks like a manifest.json: pass the export folder")
        return from_array([obj])
    records = [r for r in (parse_line(line) for line in text.splitlines()) if r]
    if records:
        return from_schemas_topic(records)
    raise ValueError("unknown format: expected an export folder, a JSON array of versions, or a _schemas dump")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["plan"])
    ap.add_argument("--input", required=True)
    ap.add_argument("--subject-prefix")
    args = ap.parse_args()
    try:
        plan = build_plan(args.input)
    except (OSError, ValueError, KeyError) as e:
        print(f"❌ {e}", file=sys.stderr)
        return 2
    if args.subject_prefix:
        plan["versions"] = [v for v in plan["versions"] if v["subject"].startswith(args.subject_prefix)]
        plan["subjects"] = {s: c for s, c in plan["subjects"].items() if s.startswith(args.subject_prefix)}
    plan["versions"].sort(key=lambda v: (v["id"] if v["id"] is not None else 1 << 62, v["subject"], v["version"] or 0))
    plan["source"] = args.input
    print(json.dumps(plan))
    return 0


if __name__ == "__main__":
    sys.exit(main())
