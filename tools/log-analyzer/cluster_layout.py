#!/usr/bin/env python3
"""
🗺️ 💽 The layout of a Kafka cluster from the outputs customers put in their bundles, read by playground analyze logs
(found by bundle_triage.py: kinds topic_describe and log_dirs):

- kafka-topics --describe: partitions and leaders per broker, partitions led by a replica that is not the preferred one
  (leader imbalance), offline, under-replicated and under min.insync.replicas partitions, topics with replication factor 1,
  a broker out of every ISR; the observers of a Multi-Region Cluster (Observers:) are counted apart, never as replicas
  missing from the ISR;
- kafka-log-dirs --describe (JSON): the disk used per broker and log dir, the log dirs with an error (offline), the skew
  of the disk usage between brokers, the biggest partitions and topics, the replicas being moved (future).

Python 3.8, stdlib only.

    python3 -I cluster_layout.py topics.txt log-dirs.txt     # JSON on stdout
"""

import json
import os
import re
import sys
from collections import Counter, OrderedDict, defaultdict
from typing import Dict, List, Optional, Tuple

# the observers of a Confluent Multi-Region Cluster are in Replicas and, until promoted, not in Isr:
# "Replicas: 1,2,3,4,5 Isr: 1,2,3 Offline: Observers: 4,5"
PARTITION_RE = re.compile(r"Topic:\s*(\S+)\s+(?:TopicId:\s*\S+\s+)?Partition:\s*(\d+)\s+Leader:\s*(\S+)\s+Replicas:\s*([\d,]*)\s+Isr:\s*([\d,]*)"
                          r"(?:\s+Offline:(?:[ \t]*([\d,]+))?)?(?:\s+Observers:(?:[ \t]*([\d,]+))?)?")
TOPIC_RE = re.compile(r"^Topic:\s*(\S+)\s.*?PartitionCount:\s*(\d+)\s+ReplicationFactor:\s*(\d+)(?:\s+Configs:\s*(.*))?$")
MIN_ISR_RE = re.compile(r"(?:^|,)\s*min\.insync\.replicas=(\d+)")

# leader.imbalance.per.broker.percentage of the brokers (default 10): above it, the controller moves the leaders back
IMBALANCE_PCT = 10
# a broker with this much more partitions / leaders / disk than the average of the brokers, and at least SKEW_MIN more
SKEW_RATIO = 1.25
SKEW_MIN = 5
DISK_SKEW_RATIO = 1.5
DISK_SKEW_MIN = 1024 ** 3
LISTED = 20


def _ids(text: str) -> List[int]:
    return [int(x) for x in text.split(",") if x.strip().lstrip("-").isdigit()]


# a kafka-log-dirs output is read whole (one JSON document) up to this size; a describe output is read line by line
MAX_LOG_DIRS_BYTES = 256 * 1024 * 1024


def open_text(path: str):
    import gzip
    opener = gzip.open if path.endswith(".gz") else open
    return opener(path, "rt", encoding="utf-8", errors="replace")


def read_text(path: str, limit: int = MAX_LOG_DIRS_BYTES) -> str:
    with open_text(path) as fh:
        return fh.read(limit)


def parse_describe(text) -> Tuple[Dict[str, dict], Dict[Tuple[str, int], dict]]:
    """topics {name: {partitions, rf, configs}} and partitions {(topic, p): {leader, replicas, isr, offline, observers}}.
    text: a string or an iterable of lines (an open file: a log of GBs with a describe output in it is not loaded)"""
    topics: Dict[str, dict] = OrderedDict()
    parts: Dict[Tuple[str, int], dict] = OrderedDict()
    for line in (text.splitlines() if isinstance(text, str) else text):
        line = line.rstrip()
        m = PARTITION_RE.search(line)
        if m:
            topic, p, leader, replicas, isr, offline, observers = m.groups()
            lid = int(leader) if leader.lstrip("-").isdigit() else -1
            parts[(topic, int(p))] = {"leader": lid, "replicas": _ids(replicas), "isr": _ids(isr),
                                      "offline": _ids(offline or ""), "observers": _ids(observers or "")}
            continue
        m = TOPIC_RE.match(line.strip())
        if m:
            name, n, rf, configs = m.groups()
            topics[name] = {"partitions": int(n), "rf": int(rf), "configs": (configs or "").strip()}
    return topics, parts


LOG_DIRS_START = re.compile(r'\{\s*"(?:version|brokers)"\s*:')


def parse_log_dirs(text: str) -> Optional[dict]:
    """the JSON of kafka-log-dirs --describe (after its "Querying brokers…" lines). Tried only where a document of it can
    start ({"version": or {"brokers":), at its offset (no copy of the rest of the text: a truncated output of tens of
    MB with a { at each partition took minutes)"""
    decoder = json.JSONDecoder()
    for m in LOG_DIRS_START.finditer(text):
        try:
            obj, _ = decoder.raw_decode(text, m.start())
        except ValueError:
            continue
        if isinstance(obj, dict) and isinstance(obj.get("brokers"), list):
            return obj
    return None


def human_size(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def analyze(sources: List[Tuple[str, str]]) -> Optional[dict]:
    """sources: (label, path) of the kafka-topics --describe and kafka-log-dirs outputs. None when none could be read"""
    topics: Dict[str, dict] = OrderedDict()
    parts: Dict[Tuple[str, int], dict] = OrderedDict()
    dirs: List[dict] = []
    read: List[str] = []
    describes = 0
    for label, path in sources:
        try:
            with open_text(path) as fh:
                t, p = parse_describe(fh)
            if p:
                topics.update(t)
                parts.update(p)
                read.append(label)
                describes += 1
                continue
            ld = parse_log_dirs(read_text(path))
        except (OSError, EOFError, ValueError):  # a truncated .gz, a file that is not gzip
            continue
        if ld:
            dirs.append(ld)
            read.append(label)
    if not parts and not dirs:
        return None
    res: dict = {"sources": read, "findings": []}
    findings = res["findings"]

    def add(sev: str, text: str) -> None:
        findings.append({"severity": sev, "text": text})

    # several outputs of the same kind (before / after, or two clusters: Replicator, MirrorMaker): the last one given wins
    # for a partition and for the disk of a broker, never summed
    if describes > 1 or len(dirs) > 1:
        add("INFO", f"{describes} kafka-topics --describe and {len(dirs)} kafka-log-dirs outputs merged, the last one given wins "
                    "for a partition and for the disk of a broker: of two clusters (Replicator, MirrorMaker), their broker ids "
                    "are mixed")

    brokers: Dict[int, dict] = defaultdict(lambda: {"replicas": 0, "observers": 0, "leaders": 0, "preferred": 0,
                                                    "not_preferred": 0, "in_isr": 0, "disk_bytes": None, "log_dirs": []})
    if parts:
        offline, urp, under_min, not_pref = [], [], [], []
        for (topic, p), x in parts.items():
            for b in x["replicas"]:
                brokers[b]["replicas"] += 1
            for b in x["observers"]:
                brokers[b]["observers"] += 1
            for b in x["isr"]:
                brokers[b]["in_isr"] += 1
            if x["replicas"]:
                brokers[x["replicas"][0]]["preferred"] += 1
            if x["leader"] < 0:
                offline.append(f"{topic}-{p}")
            else:
                brokers[x["leader"]]["leaders"] += 1
                if x["replicas"] and x["leader"] != x["replicas"][0]:
                    brokers[x["replicas"][0]]["not_preferred"] += 1
                    not_pref.append(f"{topic}-{p}")
            # the sync replicas missing from the ISR: an observer out of it is the normal state (asynchronous)
            if set(x["replicas"]) - set(x["observers"]) - set(x["isr"]):
                urp.append(f"{topic}-{p}")
            m = MIN_ISR_RE.search((topics.get(topic) or {}).get("configs") or "")
            if m and len(x["isr"]) < int(m.group(1)):
                under_min.append(f"{topic}-{p}")
        rf1 = sorted({t for (t, _), x in parts.items() if len(set(x["replicas"]) - set(x["observers"])) == 1})
        res.update(topics=len({t for t, _ in parts}), partitions=len(parts),
                   observer_partitions=sum(1 for x in parts.values() if x["observers"]), offline=offline[:LISTED], offline_count=len(offline),
                   under_replicated=urp[:LISTED], under_replicated_count=len(urp), under_min_isr=under_min[:LISTED],
                   under_min_isr_count=len(under_min), not_preferred_leader=not_pref[:LISTED], not_preferred_count=len(not_pref),
                   rf1_topics=rf1[:LISTED], rf1_count=len(rf1))
        if offline:
            add("CRITICAL", f"{len(offline)} partition(s) without leader (offline): {', '.join(offline[:5])}{' …' if len(offline) > 5 else ''}. "
                            "Producers and consumers of these partitions fail: bring the brokers of their replicas back")
        if under_min:
            add("HIGH", f"{len(under_min)} partition(s) under min.insync.replicas: {', '.join(under_min[:5])}{' …' if len(under_min) > 5 else ''}. "
                        "acks=all producers get NotEnoughReplicas")
        if urp:
            add("HIGH" if len(urp) * 10 >= len(parts) else "MEDIUM",
                f"{len(urp)} under-replicated partition(s) of {len(parts)}: {', '.join(urp[:5])}{' …' if len(urp) > 5 else ''}")
        for b, x in sorted(brokers.items()):
            # a broker that only hosts observers is in no ISR by design
            if x["replicas"] > x["observers"] and not x["in_isr"]:
                add("HIGH", f"broker {b} hosts {x['replicas'] - x['observers']} replica(s) but is in no ISR: down, fenced or not fetching")
        live = [b for b, x in brokers.items() if x["in_isr"]]
        if len(live) > 1:
            def skew(key: str, what: str) -> None:
                vals = {b: brokers[b][key] for b in live}
                avg = sum(vals.values()) / len(vals)
                top = max(vals, key=vals.get)
                low = min(vals, key=vals.get)
                if avg and vals[top] >= SKEW_RATIO * avg and vals[top] - vals[low] >= SKEW_MIN:
                    add("MEDIUM", f"{what} skew: broker {top} has {vals[top]:,}, broker {low} {vals[low]:,} (average {avg:.0f}): "
                                  + ("run a preferred leader election (playground topic elect-leader / kafka-leader-election) "
                                     "or check auto.leader.rebalance.enable" if key == "leaders" else
                                     "rebalance the replicas (Self-Balancing Clusters, Cruise Control or kafka-reassign-partitions)"))
            skew("leaders", "Leader")
            skew("replicas", "Partition")
        for b, x in sorted(brokers.items()):
            if x["preferred"] and 100 * x["not_preferred"] / x["preferred"] > IMBALANCE_PCT and x["not_preferred"] >= 2:
                add("MEDIUM", f"broker {b}: {x['not_preferred']} of the {x['preferred']} partitions it is the preferred leader of "
                              f"are led by another broker ({100 * x['not_preferred'] / x['preferred']:.0f}% > {IMBALANCE_PCT}% "
                              "leader.imbalance.per.broker.percentage): a preferred leader election moves them back")
        if rf1:
            add("MEDIUM", f"{len(rf1)} topic(s) with replication factor 1 (data lost with their broker): {', '.join(rf1[:5])}{' …' if len(rf1) > 5 else ''}")
    if dirs:
        sizes: Dict[Tuple[str, int], int] = {}
        topic_sizes: Counter = Counter()
        future = 0
        # the last output that has a broker gives its dirs (two snapshots of the same cluster are not added up)
        latest: Dict[int, dict] = {}
        for d in dirs:
            for br in d.get("brokers") or []:
                if isinstance(br, dict) and isinstance(br.get("broker"), int):
                    latest[br["broker"]] = br
        for b, br in sorted(latest.items()):
            total = 0
            for ld in [x for x in br.get("logDirs") or [] if isinstance(x, dict)]:
                plist = [x for x in ld.get("partitions") or [] if isinstance(x, dict)]
                used = sum(int(p.get("size") or 0) for p in plist if not p.get("isFuture"))
                future += sum(1 for p in plist if p.get("isFuture"))
                total += used
                brokers[b]["log_dirs"].append({"dir": ld.get("logDir"), "bytes": used, "partitions": len(plist),
                                               "error": ld.get("error")})
                if ld.get("error"):
                    add("HIGH", f"broker {b}: log dir {ld.get('logDir')} has an error ({ld['error']}): offline, its "
                                "partitions moved to other dirs or went offline")
                for p in plist:
                    if p.get("isFuture"):
                        continue
                    key = (str(p.get("partition") or ""), b)
                    sizes[key] = max(sizes.get(key, 0), int(p.get("size") or 0))
            brokers[b]["disk_bytes"] = total
        for (name, b), size in sizes.items():
            topic_sizes[name.rsplit("-", 1)[0]] += size
        res["biggest_partitions"] = [{"partition": n, "broker": b, "bytes": s} for (n, b), s in
                                     sorted(sizes.items(), key=lambda x: -x[1])[:10]]
        res["topics_by_size"] = [{"topic": t, "bytes": s} for t, s in topic_sizes.most_common(10)]
        res["future_replicas"] = future
        disks = {b: x["disk_bytes"] for b, x in brokers.items() if x["disk_bytes"] is not None}
        if len(disks) > 1:
            top, low = max(disks, key=disks.get), min(disks, key=disks.get)
            avg = sum(disks.values()) / len(disks)
            if avg and disks[top] >= DISK_SKEW_RATIO * avg and disks[top] - disks[low] >= DISK_SKEW_MIN:
                add("MEDIUM", f"Disk usage skew: broker {top} uses {human_size(disks[top])}, broker {low} {human_size(disks[low])} "
                              f"(average {human_size(avg)}): one broker fills first; rebalance the replicas")
        if future:
            add("INFO", f"{future} replica(s) being moved between log dirs or brokers (isFuture): a reassignment is in progress")
    res["brokers"] = [dict(x, id=b) for b, x in sorted(brokers.items())]
    order = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]
    findings.sort(key=lambda f: order.index(f["severity"]) if f["severity"] in order else 9)
    if not findings:
        add("OK", "Partitions, leaders and disk usage are balanced, no offline or under-replicated partition.")
    return res


def main() -> int:
    res = analyze([(os.path.basename(p), p) for p in sys.argv[1:]])
    print(json.dumps(res, indent=1))
    return 0 if res else 2


if __name__ == "__main__":
    sys.exit(main())
