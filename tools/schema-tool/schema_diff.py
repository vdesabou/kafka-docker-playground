#!/usr/bin/env python3
"""Field-level diff of two schemas (Avro, JSON Schema or Protobuf), for `playground schema diff`.

    python3 -I schema_diff.py --left v1.avsc --left-type AVRO --left-label "orders-value v1" \
        --right v2.avsc --right-type AVRO --right-label "orders-value v2" [--verdicts verdicts.json] [--json]

--verdicts is a JSON object {"BACKWARD": {"compatible": true, "messages": [...]}, ...} computed by the CLI against the
Schema Registry (the registry is the authority for compatibility); this script only explains *what* changed, with a
hint per change, and prints the verdict matrix it is given.

Exit code: 0 (also when the schemas differ), 2 on unreadable input.
"""

import argparse
import json
import re
import sys

AVRO_PRIMITIVES = {"null", "boolean", "int", "long", "float", "double", "bytes", "string"}
# reader type <- writer types it can read (Avro schema resolution)
AVRO_PROMOTIONS = {
    "long": {"int"},
    "float": {"int", "long"},
    "double": {"int", "long", "float"},
    "string": {"bytes"},
    "bytes": {"string"},
}


# --------------------------------------------------------------------------------------------- Avro


class AvroFlattener:
    """Flattens an Avro schema into {path: {"type": str, "default": ..., "has_default": bool, "doc": str}}."""

    def __init__(self):
        self.named = {}
        self.fields = {}
        self.records = {}

    def fullname(self, name, namespace):
        if "." in name or not namespace:
            return name
        return f"{namespace}.{name}"

    def type_repr(self, t, namespace, path, depth=0):
        if depth > 20:
            return "…"
        if isinstance(t, str):
            if t in AVRO_PRIMITIVES:
                return t
            full = self.fullname(t, namespace)
            return self.named.get(full, self.named.get(t, t))
        if isinstance(t, list):
            return "union[" + ", ".join(self.type_repr(x, namespace, path, depth + 1) for x in t) + "]"
        if isinstance(t, dict):
            kind = t.get("type")
            logical = t.get("logicalType")
            if kind == "record" or kind == "error":
                ns = t.get("namespace", namespace)
                full = self.fullname(t.get("name", "?"), ns)
                self.named[full] = f"record {full}"
                self.records[path or "<root>"] = full
                for f in t.get("fields", []):
                    fpath = f"{path}.{f['name']}" if path else f["name"]
                    entry = {
                        "type": self.type_repr(f.get("type"), ns, fpath, depth + 1),
                        "has_default": "default" in f,
                        "default": f.get("default"),
                    }
                    self.fields[fpath] = entry
                return f"record {full}"
            if kind == "enum":
                full = self.fullname(t.get("name", "?"), t.get("namespace", namespace))
                r = f"enum {full} {{{', '.join(t.get('symbols', []))}}}"
                self.named[full] = r
                return r
            if kind == "fixed":
                full = self.fullname(t.get("name", "?"), t.get("namespace", namespace))
                r = f"fixed {full}({t.get('size')})"
                if logical:
                    r += f" ({logical})"
                self.named[full] = r
                return r
            if kind == "array":
                return "array<" + self.type_repr(t.get("items"), namespace, f"{path}[]", depth + 1) + ">"
            if kind == "map":
                return "map<" + self.type_repr(t.get("values"), namespace, f"{path}{{}}", depth + 1) + ">"
            base = self.type_repr(kind, namespace, path, depth + 1)
            if logical:
                extra = ""
                if logical == "decimal":
                    extra = f" {t.get('precision')},{t.get('scale', 0)}"
                return f"{base} ({logical}{extra})"
            return base
        return str(t)


def avro_base_types(type_repr):
    """'union[null, string]' -> {'null', 'string'}; 'int' -> {'int'}"""
    if type_repr.startswith("union[") and type_repr.endswith("]"):
        return {x.strip() for x in type_repr[6:-1].split(",")}
    return {type_repr}


def avro_type_change_hint(old, new):
    old_set, new_set = avro_base_types(old), avro_base_types(new)
    if old_set <= new_set:
        return "widened (union extended): readers with the new schema read old data, readers with the old one may not read new data"
    if all(o in new_set or any(o in AVRO_PROMOTIONS.get(n, set()) for n in new_set) for o in old_set):
        return "promotion: the new schema reads old data (BACKWARD), not the other way round"
    return "incompatible type change for both directions unless the rule is NONE"


def diff_avro(left, right):
    a, b = AvroFlattener(), AvroFlattener()
    root_a = a.type_repr(left, None, "")
    root_b = b.type_repr(right, None, "")
    changes = []
    if root_a != root_b and not (root_a.startswith("record ") and root_b.startswith("record ")):
        changes.append({"op": "changed", "path": "<root>", "from": root_a, "to": root_b,
                        "hint": "the top-level type changed"})
    elif root_a != root_b:
        changes.append({"op": "renamed", "path": "<root>", "from": root_a, "to": root_b,
                        "hint": "the record full name changed: a reader matches records by name (add an alias)"})
    for path in sorted(set(a.fields) | set(b.fields), key=_path_key):
        fa, fb = a.fields.get(path), b.fields.get(path)
        if fa and not fb:
            if fa["has_default"]:
                hint = "removed, had a default: fine for BACKWARD and FORWARD"
            else:
                hint = "removed, had no default: old readers can't fill it from new data (breaks FORWARD)"
            changes.append({"op": "removed", "path": path, "from": fa["type"], "hint": hint})
        elif fb and not fa:
            if fb["has_default"]:
                hint = f"added with default {json.dumps(fb['default'])}: fine for BACKWARD and FORWARD"
            else:
                hint = "added without a default: the new schema can't read old data (breaks BACKWARD)"
            changes.append({"op": "added", "path": path, "to": fb["type"], "hint": hint,
                            "default": fb["default"] if fb["has_default"] else None})
        else:
            if fa["type"] != fb["type"]:
                if fa["type"].startswith("enum ") and fb["type"].startswith("enum "):
                    hint = _enum_hint(fa["type"], fb["type"])
                else:
                    hint = avro_type_change_hint(fa["type"], fb["type"])
                changes.append({"op": "type", "path": path, "from": fa["type"], "to": fb["type"], "hint": hint})
            if fa["has_default"] != fb["has_default"] or (fa["has_default"] and fa["default"] != fb["default"]):
                changes.append({
                    "op": "default", "path": path,
                    "from": json.dumps(fa["default"]) if fa["has_default"] else "(none)",
                    "to": json.dumps(fb["default"]) if fb["has_default"] else "(none)",
                    "hint": "default removed: this field can't be removed later without breaking FORWARD"
                    if not fb["has_default"] else "default added or changed: used when reading data without this field",
                })
    return changes


def _enum_hint(old, new):
    sym = lambda r: set(re.search(r"\{(.*)\}", r).group(1).split(", ")) if "{" in r else set()
    added, removed = sym(new) - sym(old), sym(old) - sym(new)
    parts = []
    if added:
        parts.append(f"symbols added {sorted(added)}: old readers fail on them unless the enum has a default")
    if removed:
        parts.append(f"symbols removed {sorted(removed)}: new readers fail on old data using them unless the enum has a default")
    return "; ".join(parts) or "enum changed"


def _path_key(p):
    return (p.count("."), p)


# --------------------------------------------------------------------------------------------- JSON Schema


def flatten_json_schema(schema):
    fields = {}
    required = {}

    def walk(node, path, depth=0):
        if not isinstance(node, dict) or depth > 20:
            return
        if "$ref" in node:
            fields.setdefault(path or "<root>", {})["ref"] = node["$ref"]
        props = node.get("properties", {})
        req = set(node.get("required", []))
        for name, sub in props.items():
            p = f"{path}.{name}" if path else name
            fields[p] = {"type": json_type_repr(sub), "required": name in req}
            walk(sub, p, depth + 1)
        if "items" in node and isinstance(node["items"], dict):
            walk(node["items"], f"{path}[]", depth + 1)
        required[path or "<root>"] = req
        for key in ("additionalProperties",):
            if key in node:
                fields.setdefault(f"{path or '<root>'}", {})
                fields[f"{path or '<root>'}"]["additionalProperties"] = node[key] if isinstance(node[key], bool) else "schema"

    walk(schema, "")
    return fields


def json_type_repr(node):
    if not isinstance(node, dict):
        return str(node)
    if "$ref" in node:
        return f"$ref {node['$ref']}"
    for comb in ("oneOf", "anyOf", "allOf"):
        if comb in node:
            return f"{comb}[" + ", ".join(json_type_repr(x) for x in node[comb]) + "]"
    t = node.get("type", "any")
    if isinstance(t, list):
        t = "|".join(t)
    if t == "array":
        t = "array<" + json_type_repr(node.get("items", {})) + ">"
    if "format" in node:
        t += f" ({node['format']})"
    if "enum" in node:
        t += " enum" + json.dumps(node["enum"])
    return t


def diff_json_schema(left, right):
    a, b = flatten_json_schema(left), flatten_json_schema(right)
    changes = []
    for path in sorted(set(a) | set(b), key=_path_key):
        fa, fb = a.get(path, {}), b.get(path, {})
        if ("additionalProperties" in fa or "additionalProperties" in fb) and \
                fa.get("additionalProperties", True) != fb.get("additionalProperties", True):
            changes.append({"op": "additionalProperties", "path": path,
                            "from": str(fa.get("additionalProperties", "true (default)")),
                            "to": str(fb.get("additionalProperties", "true (default)")),
                            "hint": "open vs closed content model: decides whether added / removed properties are compatible"})
        if "type" in fa and "type" not in fb:
            changes.append({"op": "removed", "path": path, "from": fa["type"],
                            "hint": "removed: compatible only if the schemas are open (additionalProperties) in the right direction"})
        elif "type" in fb and "type" not in fa:
            hint = "added as required: old data doesn't have it" if fb.get("required") else "added as optional"
            changes.append({"op": "added", "path": path, "to": fb["type"], "hint": hint})
        elif "type" in fa and "type" in fb:
            if fa.get("type") != fb.get("type"):
                changes.append({"op": "type", "path": path, "from": fa["type"], "to": fb["type"],
                                "hint": "type changed: incompatible unless the new type is a superset (e.g. integer -> number)"})
            if fa.get("required") != fb.get("required") and "required" in fa and "required" in fb:
                changes.append({"op": "required", "path": path, "from": "required" if fa["required"] else "optional",
                                "to": "required" if fb["required"] else "optional",
                                "hint": "now required: old data may not have it" if fb["required"] else "now optional"})
    return changes


# --------------------------------------------------------------------------------------------- Protobuf

PROTO_FIELD = re.compile(
    r"^\s*(?:(optional|repeated|required)\s+)?([\w.]+|map\s*<[^>]+>)\s+(\w+)\s*=\s*(\d+)\s*(?:\[[^\]]*\])?\s*;")


def flatten_proto(text):
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    fields = {}
    reserved = {}
    stack = []
    for raw in re.split(r"(?<=[{};])", text):
        line = raw.strip()
        m = re.match(r"^(message|enum|oneof)\s+(\w+)\s*\{$", line)
        if m:
            stack.append((m.group(1), m.group(2)))
            continue
        if line.endswith("{"):
            stack.append(("other", ""))
            continue
        if line == "}":
            if stack:
                stack.pop()
            continue
        scope = ".".join(n for k, n in stack if k in ("message",))
        if line.startswith("reserved"):
            reserved.setdefault(scope, []).append(line.rstrip(";"))
            continue
        fm = PROTO_FIELD.match(line)
        if fm and stack and stack[-1][0] in ("message", "oneof"):
            label, ftype, name, number = fm.groups()
            fields[f"{scope}.{name}" if scope else name] = {
                "type": (label + " " if label else "") + re.sub(r"\s+", "", ftype),
                "number": int(number),
            }
        elif stack and stack[-1][0] == "enum":
            em = re.match(r"^(\w+)\s*=\s*(-?\d+)", line)
            if em:
                enum_name = f"{scope}.{stack[-1][1]}" if scope else stack[-1][1]
                fields[f"{enum_name}::{em.group(1)}"] = {"type": "enum value", "number": int(em.group(2))}
    return fields, reserved


def diff_proto(left, right):
    a, ra = flatten_proto(left)
    b, rb = flatten_proto(right)
    changes = []
    numbers_a = {(p.rsplit(".", 1)[0], f["number"]): p for p, f in a.items() if "::" not in p}
    for path in sorted(set(a) | set(b), key=_path_key):
        fa, fb = a.get(path), b.get(path)
        if fa and not fb:
            changes.append({"op": "removed", "path": path, "from": f"{fa['type']} = {fa['number']}",
                            "hint": "removed: fine on the wire if its number is reserved and never reused"})
        elif fb and not fa:
            reused = numbers_a.get((path.rsplit(".", 1)[0], fb["number"]))
            hint = "added: fine, old readers skip unknown fields"
            if reused and reused != path and "::" not in path:
                hint = f"❌ added with number {fb['number']}, which was {reused}: reusing a field number corrupts old data"
            changes.append({"op": "added", "path": path, "to": f"{fb['type']} = {fb['number']}", "hint": hint})
        else:
            if fa["number"] != fb["number"]:
                changes.append({"op": "number", "path": path, "from": str(fa["number"]), "to": str(fb["number"]),
                                "hint": "field number changed: on the wire it is a different field (breaks both directions)"})
            if fa["type"] != fb["type"]:
                changes.append({"op": "type", "path": path, "from": fa["type"], "to": fb["type"],
                                "hint": "type changed: only a few wire-compatible changes are safe (int32/int64/uint32…, string/bytes)"})
    return changes


# --------------------------------------------------------------------------------------------- main

ICONS = {"added": "➕", "removed": "➖", "type": "✏️ ", "default": "✏️ ", "renamed": "✏️ ", "changed": "✏️ ",
         "required": "✏️ ", "number": "✏️ ", "additionalProperties": "✏️ "}
# with two schemas, the *_TRANSITIVE rules give the same verdict as their non transitive version
RULES = ["BACKWARD", "FORWARD", "FULL"]


def format_messages(messages):
    """the reasons of a registry verdict, without the oldSchema / oldSchemaVersion / validateFields entries"""
    out = []
    for m in messages:
        if m.startswith("{oldSchema") or m.startswith("{validateFields"):
            continue
        found = re.search(r'errorType:"([^"]+)", description:"([^"]*)"', m)
        out.append(f"{found.group(1)}: {found.group(2)}" if found else m)
    return out


def load(path, schema_type):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if schema_type == "PROTOBUF":
        return text
    return json.loads(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--left", required=True)
    ap.add_argument("--left-type", default="AVRO")
    ap.add_argument("--left-label", default="left")
    ap.add_argument("--right", required=True)
    ap.add_argument("--right-type", default="AVRO")
    ap.add_argument("--right-label", default="right")
    ap.add_argument("--verdicts")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    try:
        left = load(args.left, args.left_type)
        right = load(args.right, args.right_type)
    except (OSError, ValueError) as e:
        print(f"❌ can't read the schemas: {e}", file=sys.stderr)
        return 2

    if args.left_type != args.right_type:
        changes = [{"op": "changed", "path": "<root>", "from": args.left_type, "to": args.right_type,
                    "hint": "the schema type changed: never compatible"}]
    elif args.left_type == "PROTOBUF":
        changes = diff_proto(left, right)
    elif args.left_type == "JSON":
        changes = diff_json_schema(left, right)
    else:
        changes = diff_avro(left, right)

    # the fields of an added or removed record are part of that change, not changes of their own
    whole = [c["path"] for c in changes if c["op"] in ("added", "removed")]
    changes = [c for c in changes
               if not any(c["path"].startswith(w + ".") or c["path"].startswith(w + "[]") for w in whole)]

    verdicts = {}
    if args.verdicts:
        with open(args.verdicts, encoding="utf-8") as f:
            verdicts = json.load(f)

    if args.json:
        print(json.dumps({"left": args.left_label, "right": args.right_label, "schema_type": args.right_type,
                          "identical": not changes, "changes": changes, "verdicts": verdicts}, indent=2))
        return 0

    print(f"🔀 {args.left_label}  →  {args.right_label}  ({args.right_type})")
    if not changes:
        print("   no field-level change (formatting, doc or order only)")
    for c in changes:
        icon = ICONS.get(c["op"], "•")
        if c["op"] == "added":
            what = f"{c['path']}: {c['to']}"
        elif c["op"] == "removed":
            what = f"{c['path']}: {c['from']}"
        else:
            what = f"{c['path']} {c['op']}: {c['from']} → {c['to']}"
        print(f"   {icon} {what}")
        print(f"      💡 {c['hint']}")
    if verdicts:
        print("")
        print(f"🛡️  Verdict of the Schema Registry for {args.right_label} after {args.left_label}:")
        for rule in RULES:
            v = verdicts.get(rule)
            if v is None:
                continue
            mark = "✅" if v.get("compatible") else "❌"
            print(f"   {mark} {rule}")
            if not v.get("compatible"):
                for msg in format_messages(v.get("messages", []))[:3]:
                    print(f"      {msg}")
        print("   ✅ NONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
