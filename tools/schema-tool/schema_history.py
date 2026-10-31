#!/usr/bin/env python3
"""Timeline of a Schema Registry from its _schemas topic, for `playground schema history`.

    python3 -I schema_history.py --file dump [--subject orders-value] [--since 2026-10-31T10:00:00 | --since-ms N]
        [--include-temporary] [--json]

The dump is either the output of `playground topic consume -t _schemas --json` (one JSON record per line, the CLI's
format), or of `kafka-console-consumer --topic _schemas --from-beginning --property print.key=true
--property print.timestamp=true` (`CreateTime:<ms>\t<key>\t<value>`), which is what a customer can send.

Records of the topic:
  SCHEMA          value = the version (deleted: true for a soft delete), null = permanent delete of that version
  DELETE_SUBJECT  soft delete of the whole subject (value.version = the last version deleted)
  CLEAR_SUBJECT   permanent delete of the whole subject (older registries)
  CONFIG          compatibility and other subject settings (subject null = global), null = setting removed
  MODE            READWRITE / READONLY / IMPORT (subject null = global), null = mode removed
  NOOP            written by the registry at startup, ignored

Exit code: 0, 2 on unreadable input.
"""

import argparse
import datetime
import json
import re
import sys

TEMPORARY_PREFIX = "playground-schema-check-"


def parse_line(line):
    """-> (timestamp_ms, key dict, value dict or None) or None"""
    line = line.strip()
    if not line:
        return None
    if line.startswith("{"):
        try:
            rec = json.loads(line)
        except ValueError:
            return None
        if "key" not in rec:
            return None
        key, value = rec.get("key"), rec.get("value")
        if isinstance(key, str):
            try:
                key = json.loads(key)
            except ValueError:
                return None
        if isinstance(value, str):
            try:
                value = json.loads(value) if value not in ("", "null") else None
            except ValueError:
                value = None
        return rec.get("timestamp"), key, value
    m = re.match(r"^(?:CreateTime|LogAppendTime):(-?\d+)\t(.*?)\t(.*)$", line)
    if m:
        try:
            key = json.loads(m.group(2))
        except ValueError:
            return None
        raw = m.group(3).strip()
        try:
            value = None if raw in ("null", "") else json.loads(raw)
        except ValueError:
            value = None
        return int(m.group(1)), key, value
    return None


def parse_since(text):
    m = re.match(r"^(\d+)\s*([smhd])$", text.strip())
    if m:
        seconds = int(m.group(1)) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]
        return int((datetime.datetime.now().timestamp() - seconds) * 1000)
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
        try:
            return int(datetime.datetime.strptime(text.strip(), fmt).timestamp() * 1000)
        except ValueError:
            pass
    return None


def fmt_ts(ms):
    if ms is None:
        return "?"
    return datetime.datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M:%S")


def setting_changes(old, new):
    """{'compatibilityLevel': 'FULL', ...} diff -> 'compatibilityLevel BACKWARD → FULL, normalize true'"""
    old = {k: v for k, v in (old or {}).items() if k != "subject"}
    new = {k: v for k, v in (new or {}).items() if k != "subject"}
    parts = []
    for k in sorted(set(old) | set(new)):
        if old.get(k) != new.get(k):
            label = "compatibility" if k == "compatibilityLevel" else k
            if k in old:
                parts.append(f"{label} {json.dumps(old[k]).strip(chr(34))} → {json.dumps(new.get(k)).strip(chr(34))}")
            else:
                parts.append(f"{label} {json.dumps(new.get(k)).strip(chr(34))}")
    return ", ".join(parts)


def build_events(records, include_temporary):
    events = []
    versions = {}          # (subject, version) -> {"id", "deleted", "type"}
    configs = {}           # subject or None -> dict
    modes = {}             # subject or None -> mode
    for ts, key, value in records:
        kt = key.get("keytype")
        subject = key.get("subject")
        if subject and subject.startswith(TEMPORARY_PREFIX) and not include_temporary:
            # still tracked for the ids, never shown
            pass
        ev = None
        if kt == "SCHEMA":
            k = (subject, key.get("version"))
            before = versions.get(k)
            if value is None:
                sid = before["id"] if before else None
                versions.pop(k, None)
                still_used = sid is not None and any(v["id"] == sid for v in versions.values())
                ev = {"type": "hard_delete_version", "icon": "💀", "version": k[1], "id": sid,
                      "text": f"permanently deleted v{k[1]}" + (f" (id {sid})" if sid is not None else ""),
                      "id_still_resolves": still_used}
                if sid is not None and not still_used:
                    ev["text"] += f": ❌ id {sid} no longer resolves, records written with it can't be deserialized"
            else:
                sid, deleted, stype = value.get("id"), bool(value.get("deleted")), value.get("schemaType", "AVRO")
                versions[k] = {"id": sid, "deleted": deleted, "type": stype}
                if deleted:
                    ev = {"type": "soft_delete_version", "icon": "🧟", "version": k[1], "id": sid,
                          "text": f"soft deleted v{k[1]} (id {sid}): the id still resolves"}
                elif before and before.get("deleted"):
                    ev = {"type": "undelete_version", "icon": "♻️", "version": k[1], "id": sid,
                          "text": f"v{k[1]} (id {sid}) live again"}
                elif before and before.get("id") == sid:
                    continue
                else:
                    extra = ""
                    if before and before.get("id") != sid:
                        extra = f" (replaces id {before.get('id')}: IMPORT mode or forced id)"
                    others = sorted({s for (s, _v), x in versions.items() if x["id"] == sid and s != subject})
                    if others and not extra:
                        extra = f" (same schema as {', '.join(o for o in others if not o.startswith(TEMPORARY_PREFIX)) or 'a temporary subject'})"
                    ev = {"type": "register", "icon": "⏺️", "version": k[1], "id": sid, "schema_type": stype,
                          "text": f"registered v{k[1]} (id {sid}, {stype}){extra}"}
        elif kt == "DELETE_SUBJECT":
            last = (value or {}).get("version")
            live = [v for (s, v), x in versions.items() if s == subject and not x["deleted"] and (last is None or v <= last)]
            for (s, v), x in versions.items():
                if s == subject and (last is None or v <= last):
                    x["deleted"] = True
            ev = {"type": "soft_delete_subject", "icon": "🧟",
                  "text": f"soft deleted the subject (versions {', '.join(map(str, sorted(live))) or 'up to ' + str(last)}): the ids still resolve"}
        elif kt == "CLEAR_SUBJECT":
            gone = [k for k in versions if k[0] == subject]
            ids = {versions[k]["id"] for k in gone}
            for k in gone:
                versions.pop(k)
            lost = sorted(i for i in ids if not any(v["id"] == i for v in versions.values()))
            ev = {"type": "hard_delete_subject", "icon": "💀",
                  "text": "permanently deleted the subject" + (f": ❌ ids {lost} no longer resolve" if lost else "")}
        elif kt == "CONFIG":
            before = configs.get(subject)
            if value is None:
                configs.pop(subject, None)
                if before is None:
                    continue
                ev = {"type": "config_removed", "icon": "🛡️",
                      "text": "subject-level settings removed: the global ones apply" if subject else "global settings removed"}
            else:
                changes = setting_changes(before, value)
                configs[subject] = value
                if not changes:
                    continue
                ev = {"type": "config", "icon": "🛡️", "text": changes, "settings": {k: v for k, v in value.items() if k != "subject"}}
        elif kt == "MODE":
            before = modes.get(subject)
            if value is None:
                modes.pop(subject, None)
                ev = {"type": "mode_removed", "icon": "🔏", "text": f"mode removed (was {before})" if before else "mode removed"}
            else:
                mode = value.get("mode")
                modes[subject] = mode
                ev = {"type": "mode", "icon": "🔏", "text": f"mode {before} → {mode}" if before else f"mode {mode}"}
        elif kt in ("NOOP", None):
            continue
        else:
            ev = {"type": kt.lower(), "icon": "•", "text": f"{kt} {json.dumps(value)[:200]}"}
        if ev is None:
            continue
        ev["timestamp"] = ts
        ev["date"] = fmt_ts(ts)
        ev["subject"] = subject
        ev["temporary"] = bool(subject and subject.startswith(TEMPORARY_PREFIX))
        events.append(ev)
    # an id tombstoned then registered again later (the registry does that when a soft-deleted schema is registered
    # again) keeps resolving: say so instead of "no longer resolves"
    for i, ev in enumerate(events):
        if ev["type"] == "hard_delete_version" and ev["id"] is not None and not ev["id_still_resolves"]:
            later = next((x for x in events[i + 1:] if x["type"] == "register" and x["id"] == ev["id"]), None)
            if later:
                ev["id_still_resolves"] = True
                ev["text"] = (f"permanently deleted v{ev['version']} (id {ev['id']}): the id is registered again "
                              f"by {later['subject']} v{later['version']} at {later['date'][11:]}")
    return events, versions, configs, modes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--subject")
    ap.add_argument("--since", help="12h, 30m, 2d, or a date: 2026-10-31, 2026-10-31T10:00, '2026-10-31 10:00:00'")
    ap.add_argument("--include-temporary", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    try:
        with open(args.file, encoding="utf-8", errors="replace") as f:
            records = [r for r in (parse_line(l) for l in f) if r]
    except OSError as e:
        print(f"❌ can't read {args.file}: {e}", file=sys.stderr)
        return 2
    if not records:
        print("❌ no _schemas record found in the input (expected `playground topic consume -t _schemas --json` "
              "or kafka-console-consumer with print.key=true and print.timestamp=true)", file=sys.stderr)
        return 2

    since_ms = None
    if args.since:
        since_ms = parse_since(args.since)
        if since_ms is None:
            print(f"❌ --since {args.since}: expected 12h, 30m, 2d or a date (2026-10-31, 2026-10-31T10:00)", file=sys.stderr)
            return 2
    args.since_ms = since_ms

    events, versions, configs, modes = build_events(records, args.include_temporary)
    shown = [e for e in events
             if (args.include_temporary or not e["temporary"])
             and (not args.subject or e["subject"] == args.subject)
             and (args.since_ms is None or (e["timestamp"] or 0) >= args.since_ms)]

    lost_ids = sorted({e["id"] for e in events if e["type"] == "hard_delete_version" and not e["id_still_resolves"]
                       and e["id"] is not None and (not args.subject or e["subject"] == args.subject)
                       and not e["temporary"]}
                      - {v["id"] for v in versions.values()})
    summary = {
        "records": len(records),
        "events": len(shown),
        "registrations": sum(1 for e in shown if e["type"] == "register"),
        "soft_deletes": sum(1 for e in shown if e["type"].startswith("soft_delete")),
        "permanent_deletes": sum(1 for e in shown if e["type"].startswith("hard_delete")),
        "setting_changes": sum(1 for e in shown if e["type"] in ("config", "config_removed", "mode", "mode_removed")),
        "ids_no_longer_resolving": lost_ids,
        "global_settings": {k: v for k, v in (configs.get(None) or {}).items() if k != "subject"},
        "global_mode": modes.get(None),
    }

    if args.json:
        print(json.dumps({"summary": summary, "events": shown}, indent=2))
        return 0

    if not shown:
        print("no event" + (f" for subject {args.subject}" if args.subject else "") + " in the selected window")
    current_day = None
    for e in shown:
        day = e["date"][:10]
        if day != current_day:
            print(f"📅 {day}")
            current_day = day
        who = e["subject"] if e["subject"] else "🌍 global"
        print(f"   {e['date'][11:]}  {e['icon']} {who}: {e['text']}")
    print("")
    print(f"🧭 {summary['events']} events from {summary['records']} records: {summary['registrations']} registrations, "
          f"{summary['soft_deletes']} soft deletes, {summary['permanent_deletes']} permanent deletes, "
          f"{summary['setting_changes']} setting changes")
    if lost_ids:
        print(f"   ❌ ids that no longer resolve: {', '.join(map(str, lost_ids))} (consumers fail on the records written with them: "
              f"'Error retrieving Avro schema for id N' / 40403)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
