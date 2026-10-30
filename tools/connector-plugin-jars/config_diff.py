#!/usr/bin/env python3
"""Configuration keys of a connector that change between two versions of its plugin.

Reads two config/validate documents (written by ConfigDump.java for each version) and lists the keys added, removed,
and the keys whose default, type, importance, valid values or documentation changed. With --config (the connector
config of the customer, JSON), only the keys it sets are kept, and a key it sets that is removed is flagged.
Prints a JSON document on stdout.
"""
import argparse
import json
import sys

COMPARED = ["default_value", "type", "importance", "valid_values", "required"]


def definitions(path):
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    return {c["definition"]["name"]: c["definition"] for c in doc.get("configs", [])}


def load_config(path):
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    # {"name": ..., "config": {...}} as well as a bare config
    if isinstance(doc, dict) and isinstance(doc.get("config"), dict):
        doc = doc["config"]
    if not isinstance(doc, dict):
        raise SystemExit(f"❌ {path} is not a connector configuration (JSON object)")
    return doc


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--old", required=True)
    p.add_argument("--new", required=True)
    p.add_argument("--config", help="connector configuration (JSON) of the customer")
    p.add_argument("--with-docs", action="store_true", help="also report the keys whose documentation changed")
    a = p.parse_args()

    old, new = definitions(a.old), definitions(a.new)
    config = load_config(a.config) if a.config else None

    added, removed, changed = [], [], []
    for name in sorted(set(old) | set(new)):
        if config is not None and name not in config:
            continue
        o, n = old.get(name), new.get(name)
        if o is None:
            added.append({"key": name, "type": n["type"], "default_value": n["default_value"], "importance": n["importance"],
                          "documentation": n["documentation"]})
        elif n is None:
            removed.append({"key": name, "type": o["type"], "default_value": o["default_value"]})
        else:
            fields = {f: {"from": o.get(f), "to": n.get(f)} for f in COMPARED if o.get(f) != n.get(f)}
            if a.with_docs and (o.get("documentation") or "") != (n.get("documentation") or ""):
                fields["documentation"] = {"from": o.get("documentation"), "to": n.get("documentation")}
            if fields:
                changed.append({"key": name, "changes": fields})

    result = {"nb_keys_old": len(old), "nb_keys_new": len(new), "added": added, "removed": removed, "changed": changed}
    if config is not None:
        result["config_keys"] = len(config)
        # keys of the customer config that the new version doesn't know (framework keys excepted: not in a plugin's ConfigDef)
        framework = ("connector.class", "tasks.max", "name", "key.converter", "value.converter", "header.converter",
                     "transforms", "predicates", "errors.", "topics", "topics.regex", "config.action.reload",
                     "consumer.override.", "producer.override.", "admin.override.", "topic.creation.", "exactly.once.support",
                     "transaction.boundary", "offsets.storage.topic")
        result["unknown_in_new"] = sorted(k for k in config if k not in new
                                          and not any(k == f or (f.endswith(".") and k.startswith(f)) for f in framework)
                                          and not k.startswith(("key.converter.", "value.converter.", "header.converter.", "transforms.", "predicates.")))
    json.dump(result, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
