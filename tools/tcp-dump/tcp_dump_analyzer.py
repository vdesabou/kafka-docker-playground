#!/usr/bin/env python3
"""Analyze a network capture (.pcap / .pcapng) taken by 'playground debug tcp-dump' or sent by a customer.

Reads the TSV files that tools/tcp-dump/extract.sh writes with tshark (run in the nicolaka/netshoot image by
'playground analyze tcp-dump'), and reports: TCP conversations with their handshake time, refused, unanswered and
reset connections, retransmissions and zero windows, TLS handshakes and alerts, DNS errors, and the Kafka requests
by API with their response times and error codes. Prints a text digest (or JSON) and writes a self-contained HTML
report (inline SVG charts, works offline).

A hosts file (<ip> <name> per line, written next to the capture by 'playground debug tcp-dump') shows container
names instead of ip addresses.
"""

import argparse
import json
import os
import sys
from collections import Counter, OrderedDict, defaultdict
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# the look shared with the other reports (tools/report-common/report_html.py); no __pycache__ left in the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
import report_html  # noqa: E402

# ── Reference data ────────────────────────────────────────────────────────────

KAFKA_APIS = ("Produce Fetch ListOffsets Metadata LeaderAndIsr StopReplica UpdateMetadata ControlledShutdown OffsetCommit "
              "OffsetFetch FindCoordinator JoinGroup Heartbeat LeaveGroup SyncGroup DescribeGroups ListGroups SaslHandshake "
              "ApiVersions CreateTopics DeleteTopics DeleteRecords InitProducerId OffsetForLeaderEpoch AddPartitionsToTxn "
              "AddOffsetsToTxn EndTxn WriteTxnMarkers TxnOffsetCommit DescribeAcls CreateAcls DeleteAcls DescribeConfigs "
              "AlterConfigs AlterReplicaLogDirs DescribeLogDirs SaslAuthenticate CreatePartitions CreateDelegationToken "
              "RenewDelegationToken ExpireDelegationToken DescribeDelegationToken DeleteGroups ElectLeaders "
              "IncrementalAlterConfigs AlterPartitionReassignments ListPartitionReassignments OffsetDelete "
              "DescribeClientQuotas AlterClientQuotas DescribeUserScramCredentials AlterUserScramCredentials Vote "
              "BeginQuorumEpoch EndQuorumEpoch DescribeQuorum AlterPartition UpdateFeatures Envelope FetchSnapshot "
              "DescribeCluster DescribeProducers BrokerRegistration BrokerHeartbeat UnregisterBroker DescribeTransactions "
              "ListTransactions AllocateProducerIds ConsumerGroupHeartbeat").split()

# org.apache.kafka.common.protocol.Errors
KAFKA_ERRORS = {
    -1: "UNKNOWN_SERVER_ERROR", 1: "OFFSET_OUT_OF_RANGE", 2: "CORRUPT_MESSAGE", 3: "UNKNOWN_TOPIC_OR_PARTITION",
    4: "INVALID_FETCH_SIZE", 5: "LEADER_NOT_AVAILABLE", 6: "NOT_LEADER_OR_FOLLOWER", 7: "REQUEST_TIMED_OUT",
    8: "BROKER_NOT_AVAILABLE", 9: "REPLICA_NOT_AVAILABLE", 10: "MESSAGE_TOO_LARGE", 12: "OFFSET_METADATA_TOO_LARGE",
    13: "NETWORK_EXCEPTION", 14: "COORDINATOR_LOAD_IN_PROGRESS", 15: "COORDINATOR_NOT_AVAILABLE", 16: "NOT_COORDINATOR",
    17: "INVALID_TOPIC_EXCEPTION", 18: "RECORD_LIST_TOO_LARGE", 19: "NOT_ENOUGH_REPLICAS",
    20: "NOT_ENOUGH_REPLICAS_AFTER_APPEND", 21: "INVALID_REQUIRED_ACKS", 22: "ILLEGAL_GENERATION",
    23: "INCONSISTENT_GROUP_PROTOCOL", 24: "INVALID_GROUP_ID", 25: "UNKNOWN_MEMBER_ID", 26: "INVALID_SESSION_TIMEOUT",
    27: "REBALANCE_IN_PROGRESS", 28: "INVALID_COMMIT_OFFSET_SIZE", 29: "TOPIC_AUTHORIZATION_FAILED",
    30: "GROUP_AUTHORIZATION_FAILED", 31: "CLUSTER_AUTHORIZATION_FAILED", 32: "INVALID_TIMESTAMP",
    33: "UNSUPPORTED_SASL_MECHANISM", 34: "ILLEGAL_SASL_STATE", 35: "UNSUPPORTED_VERSION", 36: "TOPIC_ALREADY_EXISTS",
    37: "INVALID_PARTITIONS", 38: "INVALID_REPLICATION_FACTOR", 39: "INVALID_REPLICA_ASSIGNMENT", 40: "INVALID_CONFIG",
    41: "NOT_CONTROLLER", 42: "INVALID_REQUEST", 43: "UNSUPPORTED_FOR_MESSAGE_FORMAT", 44: "POLICY_VIOLATION",
    45: "OUT_OF_ORDER_SEQUENCE_NUMBER", 46: "DUPLICATE_SEQUENCE_NUMBER", 47: "INVALID_PRODUCER_EPOCH",
    48: "INVALID_TXN_STATE", 49: "INVALID_PRODUCER_ID_MAPPING", 50: "INVALID_TRANSACTION_TIMEOUT",
    51: "CONCURRENT_TRANSACTIONS", 53: "TRANSACTIONAL_ID_AUTHORIZATION_FAILED", 54: "SECURITY_DISABLED",
    56: "KAFKA_STORAGE_ERROR", 58: "SASL_AUTHENTICATION_FAILED", 59: "UNKNOWN_PRODUCER_ID",
    72: "LISTENER_NOT_FOUND", 74: "FENCED_LEADER_EPOCH", 75: "UNKNOWN_LEADER_EPOCH", 76: "UNSUPPORTED_COMPRESSION_TYPE",
    79: "MEMBER_ID_REQUIRED", 82: "FENCED_INSTANCE_ID", 87: "INVALID_RECORD", 89: "THROTTLING_QUOTA_EXCEEDED",
    90: "PRODUCER_FENCED", 100: "UNKNOWN_TOPIC_ID",
}
KAFKA_AUTH_ERRORS = {29, 30, 31, 33, 34, 53, 58}
# usual while a consumer group starts or rebalances, or while a client looks for a coordinator or a leader
KAFKA_BENIGN_ERRORS = {14, 15, 16, 25, 27, 79}

TLS_ALERTS = {
    0: "close_notify", 10: "unexpected_message", 20: "bad_record_mac", 22: "record_overflow", 40: "handshake_failure",
    42: "bad_certificate", 43: "unsupported_certificate", 44: "certificate_revoked", 45: "certificate_expired",
    46: "certificate_unknown", 47: "illegal_parameter", 48: "unknown_ca", 49: "access_denied", 50: "decode_error",
    51: "decrypt_error", 70: "protocol_version", 71: "insufficient_security", 80: "internal_error",
    86: "inappropriate_fallback", 90: "user_canceled", 109: "missing_extension", 110: "unsupported_extension",
    112: "unrecognized_name", 113: "bad_certificate_status_response", 115: "unknown_psk_identity",
    116: "certificate_required", 120: "no_application_protocol",
}
TLS_ALERT_HINTS = {
    "unknown_ca": "the peer does not trust the certificate authority: add the CA to its truststore",
    "certificate_unknown": "the certificate was rejected (often the CA is not in the truststore, or the hostname does not match)",
    "bad_certificate": "the certificate is invalid for the peer (hostname, key usage, or a client certificate it rejects)",
    "certificate_expired": "a certificate of the chain has expired",
    "handshake_failure": "no common protocol version or cipher suite, or a client certificate is required and missing",
    "protocol_version": "the TLS versions do not overlap (for example TLSv1.2 only against TLSv1.3 only)",
    "certificate_required": "the server requires a client certificate (mTLS) and the client sent none",
    "decrypt_error": "a signature or a key check failed during the handshake",
    "unrecognized_name": "the server does not know the name sent in SNI",
    "insufficient_security": "the cipher suites offered are below what the server accepts",
}
DNS_RCODES = {1: "FORMERR", 2: "SERVFAIL", 3: "NXDOMAIN", 4: "NOTIMP", 5: "REFUSED"}

SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "OK"]
SEVERITY_ICONS = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🟢", "INFO": "ℹ️", "OK": "✅"}

# chart colours: categorical slots 1 and 2 of the reference palette (validated: CVD ΔE 24.7, contrast >= 3:1)
SERIES_1 = "#2a78d6"
SERIES_2 = "#eb6834"


# ── Input ─────────────────────────────────────────────────────────────────────

def read_tsv(path: str) -> List[List[str]]:
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [line.rstrip("\n").split("\t") for line in fh if line.strip()]


def read_frames(path: str) -> set:
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as fh:
        return {int(x) for x in fh.read().split() if x.isdigit()}


def read_hosts(path: Optional[str]) -> Dict[str, str]:
    hosts: Dict[str, str] = {}
    if path and os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                parts = line.split()
                if len(parts) >= 2 and not line.startswith("#"):
                    hosts.setdefault(parts[0], parts[1])
    return hosts


def read_info(path: str) -> Dict[str, str]:
    info: Dict[str, str] = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if ":" in line:
                    k, v = line.split(":", 1)
                    info[k.strip()] = v.strip()
    return info


def flag(v: str) -> bool:
    return v in ("1", "True", "true")


def to_int(v: str, default: Optional[int] = None) -> Optional[int]:
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def to_float(v: str, default: Optional[float] = None) -> Optional[float]:
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def percentile(values: List[float], p: float) -> Optional[float]:
    if not values:
        return None
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round(p / 100 * (len(s) - 1)))))
    return s[k]


# ── Analysis ──────────────────────────────────────────────────────────────────

def analyze(data_dir: str, hosts: Dict[str, str], top: int) -> dict:
    def name(ip: str) -> str:
        return hosts.get(ip, ip) if ip else "?"

    info = read_info(os.path.join(data_dir, "info.txt"))
    packets = read_tsv(os.path.join(data_dir, "packets.tsv"))
    retrans = read_frames(os.path.join(data_dir, "retransmissions.txt"))
    dupacks = read_frames(os.path.join(data_dir, "duplicate_acks.txt"))
    zerowins = read_frames(os.path.join(data_dir, "zero_windows.txt"))

    res: dict = {"packets": len(packets), "bytes": 0, "duration_s": 0.0, "start": None, "end": None,
                 "truncated_packets": 0, "snaplen": None, "findings": []}
    limit = info.get("Packet size limit", "")
    if "file hdr:" in limit:
        res["snaplen"] = to_int(limit.split("file hdr:")[1].split()[0])

    frames: Dict[int, dict] = {}
    protocols: Counter = Counter()
    streams: Dict[str, dict] = OrderedDict()
    timeline: Dict[int, dict] = defaultdict(lambda: {"packets": 0, "bytes": 0, "resets": 0, "retransmissions": 0})
    t0 = None
    for row in packets:
        row += [""] * (19 - len(row))
        (num, epoch, length, cap_len, ip_src, ip_dst, ip6_src, ip6_dst, stream, sport, dport,
         usport, udport, syn, ack, rst, fin, tcp_len, proto) = row[:19]
        n = to_int(num)
        t = to_float(epoch)
        if n is None or t is None:
            continue
        t0 = t if t0 is None else t0
        src, dst = ip_src or ip6_src, ip_dst or ip6_dst
        length_i = to_int(length, 0)
        frames[n] = {"t": t, "src": src, "dst": dst, "syn": flag(syn)}
        res["bytes"] += length_i
        if to_int(cap_len, 0) < length_i:
            res["truncated_packets"] += 1
        protocols[proto or "?"] += 1
        sec = int(t - t0)
        timeline[sec]["packets"] += 1
        timeline[sec]["bytes"] += length_i
        is_retrans = n in retrans and not flag(syn)
        if is_retrans:
            timeline[sec]["retransmissions"] += 1
        if not stream:
            continue
        s = streams.get(stream)
        if s is None:
            s = streams[stream] = {"stream": int(stream), "a": src, "a_port": sport, "b": dst, "b_port": dport,
                                   "frames": 0, "bytes": 0, "start": t, "end": t, "syn": None, "synack": None,
                                   "syn_count": 0, "resets": [], "fin": False, "retransmissions": 0,
                                   "zero_windows": 0, "payload_frames": 0}
        s["frames"] += 1
        s["bytes"] += length_i
        s["end"] = t
        if to_int(tcp_len, 0) > 0:
            s["payload_frames"] += 1
        if flag(syn) and not flag(ack):
            s["syn_count"] += 1
            if s["syn"] is None:
                # the client is the side that sends the SYN
                s["syn"] = t
                s["a"], s["a_port"], s["b"], s["b_port"] = src, sport, dst, dport
        elif flag(syn) and flag(ack) and s["synack"] is None:
            s["synack"] = t
        if flag(rst):
            s["resets"].append({"from": src, "port": sport, "to": dst, "to_port": dport, "t": t})
            timeline[sec]["resets"] += 1
        if flag(fin):
            s["fin"] = True
        if is_retrans:
            s["retransmissions"] += 1
        if n in zerowins:
            s["zero_windows"] += 1
    if frames:
        times = [f["t"] for f in frames.values()]
        res["start"] = datetime.fromtimestamp(min(times)).strftime("%Y-%m-%d %H:%M:%S")
        res["end"] = datetime.fromtimestamp(max(times)).strftime("%Y-%m-%d %H:%M:%S")
        res["duration_s"] = round(max(times) - min(times), 3)

    # ── TCP connections ──
    conversations = []
    refused: Counter = Counter()
    unanswered: Counter = Counter()
    aborted: Counter = Counter()
    for s in streams.values():
        # seen mid-connection (no SYN): the server is the side of the listening port, the client uses an ephemeral one
        if s["syn"] is None and to_int(s["a_port"], 0) < to_int(s["b_port"], 0):
            s["a"], s["a_port"], s["b"], s["b_port"] = s["b"], s["b_port"], s["a"], s["a_port"]
        server = f"{name(s['b'])}:{s['b_port']}"
        client = f"{name(s['a'])}:{s['a_port']}"
        handshake_ms = round((s["synack"] - s["syn"]) * 1000, 2) if s["syn"] is not None and s["synack"] is not None else None
        status = "established" if s["synack"] is not None else ("seen mid-connection" if s["syn"] is None else "")
        if s["syn"] is not None and s["synack"] is None:
            if any(r["from"] == s["b"] for r in s["resets"]):
                status = "refused"
                refused[server] += 1
            else:
                status = "no answer"
                unanswered[server] += 1
        elif s["resets"]:
            status = "reset"
            for r in s["resets"]:
                aborted[f"{name(r['from'])} → {name(r['to'])}:{r['to_port']}"] += 1
        elif s["fin"]:
            status = "closed"
        conversations.append({
            "client": client, "server": server, "frames": s["frames"], "bytes": s["bytes"],
            "start_s": round(s["start"] - t0, 3) if t0 is not None else 0, "duration_s": round(s["end"] - s["start"], 3),
            "handshake_ms": handshake_ms, "status": status, "syn_retries": max(0, s["syn_count"] - 1),
            "retransmissions": s["retransmissions"], "zero_windows": s["zero_windows"]})
    conversations.sort(key=lambda c: -c["bytes"])
    res["conversations_total"] = len(conversations)
    res["conversations"] = conversations[:max(top * 3, 30)]
    res["connections"] = {
        "opened": sum(1 for s in streams.values() if s["syn"] is not None),
        "established": sum(1 for c in conversations if c["status"] in ("established", "reset", "closed") and c["handshake_ms"] is not None),
        "refused": [{"server": k, "count": v} for k, v in refused.most_common(top)],
        "no_answer": [{"server": k, "count": v} for k, v in unanswered.most_common(top)],
        "reset": [{"direction": k, "count": v} for k, v in aborted.most_common(top)],
    }
    handshakes = [c["handshake_ms"] for c in conversations if c["handshake_ms"] is not None]
    res["handshake_ms"] = {"count": len(handshakes), "p50": percentile(handshakes, 50), "p95": percentile(handshakes, 95),
                           "max": max(handshakes) if handshakes else None}
    res["resets"] = sum(len(s["resets"]) for s in streams.values())

    # ── retransmissions ──
    # a SYN sent again is a connection attempt without answer (reported as such), not a data retransmission
    retrans = {n for n in retrans if not frames.get(n, {}).get("syn")}
    payload = sum(s["payload_frames"] for s in streams.values())
    res["retransmissions"] = len(retrans)
    res["retransmission_rate_pct"] = round(100 * len(retrans) / payload, 2) if payload else 0.0
    res["duplicate_acks"] = len(dupacks)
    res["zero_windows"] = len(zerowins)
    by_pair: Counter = Counter()
    zw_by: Counter = Counter()
    for n in retrans:
        f = frames.get(n)
        if f:
            by_pair[f"{name(f['src'])} → {name(f['dst'])}"] += 1
    for n in zerowins:
        f = frames.get(n)
        if f:
            zw_by[name(f["src"])] += 1
    res["retransmissions_by_pair"] = [{"pair": k, "count": v} for k, v in by_pair.most_common(top)]
    res["zero_windows_by_receiver"] = [{"receiver": k, "count": v} for k, v in zw_by.most_common(top)]

    # ── TLS ──
    sni: Counter = Counter()
    alerts: Counter = Counter()
    encrypted_records = 0
    for row in read_tsv(os.path.join(data_dir, "tls.tsv")):
        row += [""] * (7 - len(row))
        num, hs_type, server_name, level, desc, content_type, _version = row[:7]
        f = frames.get(to_int(num, -1), {})
        if "1" in hs_type.split(","):
            sni[(server_name or "(no SNI)") + " → " + name(f.get("dst", ""))] += 1
        if "23" in content_type.split(","):
            encrypted_records += 1
        if desc:
            for lvl, d in zip(level.split(","), desc.split(",")):
                code = to_int(d)
                alerts[(name(f.get("src", "")), name(f.get("dst", "")), "fatal" if lvl == "2" else "warning",
                        TLS_ALERTS.get(code, f"alert {d}"))] += 1
    res["tls"] = {
        "client_hellos": [{"server": k, "count": v} for k, v in sni.most_common(top)],
        "alerts": [{"from": k[0], "to": k[1], "level": k[2], "alert": k[3], "count": v,
                    "hint": TLS_ALERT_HINTS.get(k[3], "")} for k, v in alerts.most_common(top * 2)],
        "encrypted_records": encrypted_records,
    }

    # ── DNS ──
    dns_errors: Counter = Counter()
    dns_slow = []
    queries = 0
    for row in read_tsv(os.path.join(data_dir, "dns.tsv")):
        row += [""] * (5 - len(row))
        _num, response, qname, rcode, dns_time = row[:5]
        if not flag(response):
            queries += 1
            continue
        code = to_int(rcode, 0)
        if code:
            dns_errors[(qname.split(",")[0], DNS_RCODES.get(code, f"rcode {code}"))] += 1
        elapsed = to_float(dns_time)
        if elapsed is not None and elapsed >= 1:
            dns_slow.append({"name": qname.split(",")[0], "seconds": round(elapsed, 3)})
    res["dns"] = {"queries": queries, "errors": [{"name": k[0], "rcode": k[1], "count": v} for k, v in dns_errors.most_common(top)],
                  "slow": sorted(dns_slow, key=lambda x: -x["seconds"])[:top]}

    # ── Kafka ──
    requests: Dict[int, dict] = {}
    responses = []
    for row in read_tsv(os.path.join(data_dir, "kafka.tsv")):
        row += [""] * (7 - len(row))
        num, api_keys, versions, _corr, request_frame, errors, client_ids = row[:7]
        n = to_int(num)
        if n is None:
            continue
        api = to_int(api_keys.split(",")[0])
        if request_frame:
            responses.append({"frame": n, "request_frame": to_int(request_frame.split(",")[0]), "api": api,
                              "errors": [to_int(e) for e in errors.split(",") if to_int(e) not in (None, 0)]})
        elif api is not None:
            requests[n] = {"api": api, "version": to_int(versions.split(",")[0]), "client": client_ids.split(",")[0]}
    per_api: Dict[str, dict] = OrderedDict()
    clients: Counter = Counter()

    def api_name(key: Optional[int]) -> str:
        return KAFKA_APIS[key] if key is not None and 0 <= key < len(KAFKA_APIS) else f"api {key}"

    for r in requests.values():
        a = per_api.setdefault(api_name(r["api"]), {"api": api_name(r["api"]), "requests": 0, "responses": 0,
                                                    "latencies_ms": [], "errors": Counter()})
        a["requests"] += 1
        if r["client"]:
            clients[r["client"]] += 1
    for resp in responses:
        req = requests.get(resp["request_frame"])
        key = api_name(req["api"] if req else resp["api"])
        a = per_api.setdefault(key, {"api": key, "requests": 0, "responses": 0, "latencies_ms": [], "errors": Counter()})
        a["responses"] += 1
        if req and resp["frame"] in frames and resp["request_frame"] in frames:
            a["latencies_ms"].append((frames[resp["frame"]]["t"] - frames[resp["request_frame"]]["t"]) * 1000)
        for e in resp["errors"]:
            a["errors"][e] += 1
    kafka_apis = []
    for a in sorted(per_api.values(), key=lambda x: -x["requests"]):
        lat = a["latencies_ms"]
        kafka_apis.append({
            "api": a["api"], "requests": a["requests"], "responses": a["responses"],
            "p50_ms": round(percentile(lat, 50), 2) if lat else None, "p95_ms": round(percentile(lat, 95), 2) if lat else None,
            "max_ms": round(max(lat), 2) if lat else None,
            "errors": [{"code": c, "name": KAFKA_ERRORS.get(c, f"error {c}"), "count": n} for c, n in a["errors"].most_common()]})
    res["kafka"] = {"requests": len(requests), "responses": len(responses), "apis": kafka_apis,
                    "clients": [{"client_id": k, "requests": v} for k, v in clients.most_common(top)]}

    res["http"] = analyze_http(data_dir, frames, name, t0, top)

    res["protocols"] = [{"protocol": k, "packets": v} for k, v in protocols.most_common(top)]
    last_sec = max(timeline) if timeline else -1
    res["timeline"] = [{"second": s, **timeline[s]} if s in timeline else
                       {"second": s, "packets": 0, "bytes": 0, "resets": 0, "retransmissions": 0} for s in range(last_sec + 1)]
    res["hosts"] = [{"ip": k, "name": v} for k, v in hosts.items()]
    res["findings"] = findings(res)
    return res


def body_text(hex_body: str, limit: int = 600) -> str:
    """The body of an HTTP message (hex from tshark) as text, or a size for a binary one."""
    hex_body = hex_body.split(",")[0]
    if not hex_body:
        return ""
    try:
        raw = bytes.fromhex(hex_body)
    except ValueError:
        return ""
    printable = sum(1 for b in raw if 32 <= b < 127 or b in (9, 10, 13))
    if raw and printable / len(raw) < 0.85:
        return f"({len(raw)}+ bytes, binary)"
    text = raw.decode("utf-8", errors="replace")
    return text if len(text) <= limit else text[:limit] + "…"


def analyze_http(data_dir: str, frames: Dict[int, dict], name, t0: Optional[float], top: int) -> dict:
    requests: Dict[int, dict] = {}
    responses = []
    for row in read_tsv(os.path.join(data_dir, "http.tsv")):
        row += [""] * (10 - len(row))
        num, method, uri, host, code, phrase, request_in, http_time, content_type, body = row[:10]
        n = to_int(num)
        if n is None:
            continue
        f = frames.get(n, {})
        if method:
            requests[n] = {"method": method.split(",")[0], "uri": uri.split(",")[0], "host": host.split(",")[0],
                           "client": name(f.get("src", "")), "server": name(f.get("dst", "")), "body": body,
                           "content_type": content_type.split(",")[0], "t": f.get("t")}
        elif code:
            elapsed = to_float(http_time.split(",")[0])
            responses.append({"request_in": to_int(request_in.split(",")[0]), "code": to_int(code.split(",")[0], 0),
                              "phrase": phrase.split(",")[0], "time_ms": round(elapsed * 1000, 2) if elapsed is not None else None,
                              "body": body, "content_type": content_type.split(",")[0], "t": f.get("t")})

    def endpoint(req: dict) -> Tuple[str, str]:
        return (req["host"] or req["server"], f"{req['method']} {req['uri'].split('?')[0]}")

    endpoints: Dict[Tuple[str, str], dict] = OrderedDict()
    for req in requests.values():
        e = endpoints.setdefault(endpoint(req), {"server": endpoint(req)[0], "endpoint": endpoint(req)[1], "requests": 0,
                                                 "statuses": Counter(), "latencies_ms": [], "no_response": 0})
        e["requests"] += 1
    statuses: Counter = Counter()
    error_groups: Dict[Tuple, dict] = OrderedDict()
    answered = set()
    for resp in responses:
        statuses[resp["code"]] += 1
        req = requests.get(resp["request_in"])
        if not req:
            continue
        answered.add(resp["request_in"])
        e = endpoints[endpoint(req)]
        e["statuses"][resp["code"]] += 1
        if resp["time_ms"] is not None:
            e["latencies_ms"].append(resp["time_ms"])
        if resp["code"] >= 400:
            key = endpoint(req) + (resp["code"],)
            g = error_groups.get(key)
            if g is None:
                g = error_groups[key] = {
                    "server": key[0], "endpoint": key[1], "code": resp["code"], "phrase": resp["phrase"], "count": 0,
                    "first_s": round(req["t"] - t0, 3) if req["t"] is not None and t0 is not None else None,
                    "client": req["client"], "time_ms": resp["time_ms"], "uri": req["uri"],
                    "request_content_type": req["content_type"], "request_body": body_text(req["body"]),
                    "response_content_type": resp["content_type"], "response_body": body_text(resp["body"])}
            g["count"] += 1
    for n, req in requests.items():
        if n not in answered:
            endpoints[endpoint(req)]["no_response"] += 1

    rows = []
    for e in sorted(endpoints.values(), key=lambda x: -x["requests"]):
        lat = e["latencies_ms"]
        rows.append({"server": e["server"], "endpoint": e["endpoint"], "requests": e["requests"],
                     "statuses": [{"code": c, "count": k} for c, k in sorted(e["statuses"].items())],
                     "no_response": e["no_response"],
                     "p50_ms": round(percentile(lat, 50), 2) if lat else None, "p95_ms": round(percentile(lat, 95), 2) if lat else None,
                     "max_ms": round(max(lat), 2) if lat else None})
    # a sample of a successful exchange, to see what the client sends
    sample = None
    for resp in responses:
        req = requests.get(resp["request_in"])
        if req and resp["code"] < 400:
            sample = {"server": endpoint(req)[0], "endpoint": endpoint(req)[1], "uri": req["uri"], "code": resp["code"],
                      "phrase": resp["phrase"], "request_content_type": req["content_type"], "request_body": body_text(req["body"]),
                      "response_content_type": resp["content_type"], "response_body": body_text(resp["body"])}
            break
    return {"requests": len(requests), "responses": len(responses),
            "statuses": [{"code": c, "count": k} for c, k in sorted(statuses.items())],
            "endpoints": rows[:top * 2], "errors": sorted(error_groups.values(), key=lambda g: (-(g["code"] // 100), -g["count"]))[:top * 2],
            "no_response": sum(e["no_response"] for e in endpoints.values()), "sample": sample}


def findings(res: dict) -> List[dict]:
    out: List[dict] = []

    def add(sev, text):
        out.append({"severity": sev, "text": text})

    conn = res["connections"]
    for r in conn["refused"]:
        add("HIGH", f"{r['count']} connection attempt(s) to {r['server']} refused (the SYN was answered with a reset): "
                    "nothing listens on that port, or a firewall rejects the connection. Check the host and port in the configuration.")
    for r in conn["no_answer"]:
        add("HIGH", f"{r['count']} connection attempt(s) to {r['server']} got no answer (SYN without SYN/ACK): "
                    "the host is down or unreachable, a firewall drops the packets, or the address is wrong.")
    for r in conn["reset"][:5]:
        add("MEDIUM", f"{r['count']} reset(s) {r['direction']} on established connection(s): a peer closed the "
                      "connection abruptly (process stopped, idle timeout of a proxy or load balancer, protocol error).")
    rate = res["retransmission_rate_pct"]
    if res["retransmissions"] >= 5 and rate >= 1:
        worst = res["retransmissions_by_pair"][0]["pair"] if res["retransmissions_by_pair"] else ""
        add("HIGH" if rate >= 5 else "MEDIUM",
            f"{rate}% of the TCP segments were retransmitted ({res['retransmissions']}), mostly {worst}: packet loss on "
            "the path (network, overloaded host, MTU issue). Expect higher latency and timeouts.")
    for z in res["zero_windows_by_receiver"][:3]:
        add("MEDIUM", f"{z['receiver']} advertised a zero TCP window {z['count']} time(s): it reads slower than the "
                      "data arrives (busy application, GC pauses, full buffers).")
    for a in res["tls"]["alerts"]:
        if a["alert"] == "close_notify":
            continue
        hint = f" Likely: {a['hint']}." if a["hint"] else ""
        add("HIGH" if a["level"] == "fatal" else "LOW",
            f"TLS {a['level']} alert {a['alert']} sent by {a['from']} to {a['to']} ({a['count']}x).{hint}")
    for d in res["dns"]["errors"]:
        add("MEDIUM", f"DNS {d['rcode']} for {d['name']} ({d['count']}x): the name does not resolve from this container.")
    for d in res["dns"]["slow"][:3]:
        add("LOW", f"DNS answer for {d['name']} took {d['seconds']}s.")
    for a in res["kafka"]["apis"]:
        for e in a["errors"]:
            if e["code"] in KAFKA_AUTH_ERRORS:
                add("HIGH", f"Kafka {a['api']}: {e['count']} response(s) with {e['name']}: check the ACLs / RBAC role "
                            "bindings and the credentials of the client.")
            elif e["code"] in KAFKA_BENIGN_ERRORS:
                add("INFO", f"Kafka {a['api']}: {e['count']} response(s) with {e['name']}, usual while a consumer group "
                            "starts or rebalances, or while a client looks for its coordinator.")
            else:
                add("MEDIUM", f"Kafka {a['api']}: {e['count']} response(s) with {e['name']}.")
        # Fetch responses wait up to fetch.max.wait.ms on purpose: their time is not a latency
        if a["api"] not in ("Fetch", "JoinGroup", "SyncGroup") and a["p95_ms"] is not None and a["p95_ms"] >= 1000:
            add("MEDIUM", f"Kafka {a['api']} responses are slow: p95 {a['p95_ms']} ms, max {a['max_ms']} ms.")
    for g in res["http"]["errors"]:
        what = f"HTTP {g['code']} {g['phrase']} from {g['server']} for {g['endpoint']} ({g['count']}x)"
        answer = f" Response: {g['response_body'][:160]}" if g["response_body"] else ""
        if g["code"] >= 500:
            add("HIGH", f"{what}: the server failed to process the request.{answer}")
        elif g["code"] == 429:
            add("MEDIUM", f"{what}: the client is rate limited, it sends faster than the API allows (retry with backoff, Retry-After).{answer}")
        elif g["code"] in (401, 403, 407):
            add("HIGH", f"{what}: authentication or authorization refused, check the credentials, token or scopes of the client.{answer}")
        else:
            add("MEDIUM", f"{what}: the server rejected the request (URL, method, headers or body).{answer}")
    for e in res["http"]["endpoints"]:
        if e["p95_ms"] is not None and e["p95_ms"] >= 1000:
            add("MEDIUM", f"HTTP {e['endpoint']} on {e['server']} is slow: p95 {e['p95_ms']} ms, max {e['max_ms']} ms.")
    if res["http"]["no_response"]:
        add("LOW", f"{res['http']['no_response']} HTTP request(s) without a response in the capture (the capture ended "
                   "first, the client timed out, or the connection was reset).")
    if res["truncated_packets"]:
        add("INFO", f"{res['truncated_packets']} packet(s) are truncated (snapshot length {res['snaplen']} bytes): "
                    "TLS and Kafka decoding can be partial.")
    if res["tls"]["encrypted_records"] and not res["kafka"]["requests"]:
        add("INFO", f"{res['tls']['encrypted_records']} TLS application data record(s): that traffic is encrypted, only "
                    "the handshakes and the alerts sent before encryption are visible (TLS 1.3 encrypts the later alerts too).")
    if not any(f["severity"] in ("CRITICAL", "HIGH", "MEDIUM", "LOW") for f in out):
        add("OK", "No refused or unanswered connection, reset, retransmission burst, TLS alert, DNS error, HTTP error or "
                  "Kafka error (other than the usual consumer group ones) in the capture.")
    out.sort(key=lambda f: SEVERITY_ORDER.index(f["severity"]))
    return out


# ── Text report ───────────────────────────────────────────────────────────────

def fmt_bytes(n: int) -> str:
    for unit in ("bytes", "kB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1024
    return str(n)


def fmt_ms(v: Optional[float]) -> str:
    return "-" if v is None else f"{v:g} ms"


def text_report(res: dict, title: str, top: int) -> str:
    lines = [f"🦈 {title}: {res['packets']} packets, {fmt_bytes(res['bytes'])} over {res['duration_s']}s"
             + (f" ({res['start']} → {res['end']})" if res["start"] else "")]

    def hdr(t):
        lines.append("")
        lines.append(t)

    hdr("🔎 Findings")
    for f in res["findings"]:
        lines.append(f"   {SEVERITY_ICONS.get(f['severity'], '')} {f['severity']}: {f['text']}")
    c = res["connections"]
    hdr(f"🔌 TCP: {res['conversations_total']} conversation(s), {c['opened']} connection(s) opened, "
        f"{res['resets']} reset(s), {res['retransmissions']} retransmission(s) ({res['retransmission_rate_pct']}%), "
        f"{res['zero_windows']} zero window(s)")
    if res["handshake_ms"]["count"]:
        h = res["handshake_ms"]
        lines.append(f"   handshake (SYN → SYN/ACK): p50 {fmt_ms(h['p50'])}, p95 {fmt_ms(h['p95'])}, max {fmt_ms(h['max'])}")
    hdr("🔝 Top TCP conversations (by bytes)")
    for conv in res["conversations"][:top]:
        lines.append(f"   {conv['client']} → {conv['server']}   {conv['frames']} frames, {fmt_bytes(conv['bytes'])}, "
                     f"over {conv['duration_s']}s, {conv['status'] or '-'}")
    if not res["conversations"]:
        lines.append("   none")
    if res["tls"]["client_hellos"] or res["tls"]["alerts"]:
        hdr("🔐 TLS")
        for h in res["tls"]["client_hellos"]:
            lines.append(f"   {h['count']} handshake(s) {h['server']}")
        for a in res["tls"]["alerts"]:
            lines.append(f"   {a['count']} {a['level']} alert {a['alert']}: {a['from']} → {a['to']}")
    if res["dns"]["queries"]:
        hdr(f"🌐 DNS: {res['dns']['queries']} query(ies)")
        for d in res["dns"]["errors"]:
            lines.append(f"   {d['count']} {d['rcode']}: {d['name']}")
        if not res["dns"]["errors"]:
            lines.append("   no error")
    if res["kafka"]["requests"]:
        hdr(f"📨 Kafka: {res['kafka']['requests']} request(s), {res['kafka']['responses']} response(s)")
        for a in res["kafka"]["apis"][:top]:
            errs = ", ".join(f"{e['name']} x{e['count']}" for e in a["errors"])
            lines.append(f"   {a['requests']:>6}  {a['api']:<18} p50 {fmt_ms(a['p50_ms']):>10}  p95 {fmt_ms(a['p95_ms']):>10}"
                         + (f"  errors: {errs}" if errs else ""))
    if res["http"]["requests"]:
        codes = ", ".join(f"{x['code']} x{x['count']}" for x in res["http"]["statuses"])
        hdr(f"🌍 HTTP: {res['http']['requests']} request(s), {res['http']['responses']} response(s) ({codes or 'no response'})")
        for e in res["http"]["endpoints"][:top]:
            st = ", ".join(f"{x['code']} x{x['count']}" for x in e["statuses"])
            lines.append(f"   {e['requests']:>6}  {e['endpoint']} on {e['server']}   p50 {fmt_ms(e['p50_ms'])}, p95 {fmt_ms(e['p95_ms'])}"
                         + (f"   {st}" if st else "") + (f", {e['no_response']} without response" if e["no_response"] else ""))
        for g in res["http"]["errors"][:top]:
            lines.append(f"   ❌ {g['code']} {g['phrase']} x{g['count']}: {g['endpoint']} on {g['server']}")
            if g["request_body"]:
                lines.append(f"      request:  {g['request_body'][:200]}")
            if g["response_body"]:
                lines.append(f"      response: {g['response_body'][:200]}")
    return "\n".join(lines)


# ── HTML report (same look as analyze thread-dump / gc-logs) ─────────────────

_HTML_CSS = report_html.style("""
.st.established,.st.closed{background:#dcfce7;color:#15803d}.st.refused,.st.no-answer{background:#fee2e2;color:#dc2626}
.st.reset{background:#ffedd5;color:#c2410c}
""")


def _e(s) -> str:
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;"))


def nice_max(v: float) -> int:
    """Axis maximum: an even integer of the form 1, 2, 2.5, 3, 4, 5, 6 or 8 x 10^n, so that the middle tick is an integer too."""
    if v <= 2:
        return 2
    magnitude = 10 ** (len(str(int(v))) - 1)
    for m in (1, 2, 2.5, 3, 4, 5, 6, 8, 10):
        top = int(m * magnitude)
        if top >= v and top % 2 == 0:
            return top
    return int(10 * magnitude)


def svg_columns(timeline: List[dict], series: List[Tuple[str, str, str]], unit: str) -> str:
    """Columns per second; several series side by side in each second (never stacked on two scales)."""
    if not timeline:
        return "<p>ℹ️ No packet.</p>"
    W, H, L, B, T = 600, 190, 44, 26, 8
    pw, ph = W - L - 10, H - B - T
    mx = nice_max(max((p[key] for p in timeline for key, _, _ in series), default=0))
    n = len(timeline)
    slot = pw / n
    bw = max(1.0, (slot - 2) / len(series))
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" role="img">']
    for frac in (0, 0.5, 1):
        y = T + ph * (1 - frac)
        out.append(f'<line x1="{L}" x2="{W - 10}" y1="{y:.1f}" y2="{y:.1f}" stroke="#e2e8f0" stroke-width="1"/>'
                   f'<text x="{L - 6}" y="{y + 3:.1f}" font-size="10" fill="#64748b" text-anchor="end">{int(mx * frac)}</text>')
    for i, p in enumerate(timeline):
        for j, (key, label, color) in enumerate(series):
            v = p[key]
            if not v:
                continue
            h = max(1.5, ph * v / mx)
            x = L + i * slot + 1 + j * bw
            out.append(f'<rect x="{x:.1f}" y="{T + ph - h:.1f}" width="{bw:.1f}" height="{h:.1f}" rx="1" fill="{color}">'
                       f'<title>second {p["second"]}: {v} {_e(label)}{unit}</title></rect>')
    step = max(1, n // 10)
    for i in range(0, n, step):
        out.append(f'<text x="{L + i * slot + slot / 2:.1f}" y="{H - 8}" font-size="10" fill="#64748b" text-anchor="middle">{i}s</text>')
    out.append("</svg>")
    return "".join(out)


def svg_hbars(rows: List[Tuple[str, float, str]], fmt) -> str:
    if not rows:
        return "<p>ℹ️ No TCP conversation.</p>"
    W, rowh, L = 600, 22, 300
    H = 10 + rowh * len(rows)
    mx = max(v for _, v, _ in rows) or 1
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" role="img">']
    for i, (lab, v, tip) in enumerate(rows):
        y = 5 + i * rowh
        w = (W - L - 80) * v / mx
        out.append(f'<text x="{L - 6}" y="{y + 14}" font-size="10" fill="#334155" text-anchor="end">{_e(lab[:52])}</text>'
                   f'<rect x="{L}" y="{y + 3}" width="{max(1, w):.1f}" height="15" rx="2" fill="{SERIES_1}"><title>{_e(tip)}</title></rect>'
                   f'<text x="{L + w + 5:.1f}" y="{y + 14}" font-size="10" fill="#475569">{_e(fmt(v))}</text>')
    out.append("</svg>")
    return "".join(out)


def html_verdict(res: dict) -> Tuple[str, str]:
    sevs = [f["severity"] for f in res["findings"]]
    n_high = sevs.count("CRITICAL") + sevs.count("HIGH")
    n_med = sevs.count("MEDIUM")
    if n_high:
        first = next(f["text"] for f in res["findings"] if f["severity"] in ("CRITICAL", "HIGH"))
        first = first.split(": ")[0].split(" (")[0]
        return "danger", f"🚨 {n_high} high finding{'s' if n_high > 1 else ''}" + (f", {n_med} medium" if n_med else "") + f": start with {first}."
    if n_med:
        return "warn", f"⚠️ {n_med} thing{'s' if n_med > 1 else ''} to look at, nothing high."
    return "ok", f"✅ Nothing alarming in the {res['packets']} packets of the capture."


def html_report(res: dict, title: str) -> str:
    def kpi(label, val, unit, cls=""):
        return (f'<div class="kpi-card {cls}"><div class="kpi-label">{_e(label)}</div>'
                f'<div class="kpi-value">{_e(val)}</div><div class="kpi-unit">{_e(unit)}</div></div>')

    c = res["connections"]
    failed = sum(r["count"] for r in c["refused"]) + sum(r["count"] for r in c["no_answer"])
    tls_fatal = sum(a["count"] for a in res["tls"]["alerts"] if a["level"] == "fatal")
    kafka_errors = sum(e["count"] for a in res["kafka"]["apis"] for e in a["errors"] if e["code"] not in KAFKA_BENIGN_ERRORS)
    http_errors = sum(g["count"] for g in res["http"]["errors"])
    kpis = "".join([
        kpi("📦 Packets", res["packets"], f"{fmt_bytes(res['bytes'])} over {res['duration_s']}s"),
        kpi("🔌 TCP conversations", res["conversations_total"], f"{c['opened']} opened in the capture"),
        kpi("🚫 Failed connections", failed, "refused or unanswered", "danger" if failed else "ok"),
        kpi("🛑 Resets", res["resets"], "RST segments", "warn" if res["resets"] else "ok"),
        kpi("🔁 Retransmissions", f"{res['retransmission_rate_pct']}%", f"{res['retransmissions']} segments",
            "ok" if res["retransmissions"] < 5 else "danger" if res["retransmission_rate_pct"] >= 5 else "warn" if res["retransmission_rate_pct"] >= 1 else "ok"),
        kpi("🔐 TLS fatal alerts", tls_fatal, f"{sum(h['count'] for h in res['tls']['client_hellos'])} handshakes", "danger" if tls_fatal else "ok"),
        kpi("🌐 DNS errors", sum(d["count"] for d in res["dns"]["errors"]), f"{res['dns']['queries']} queries",
            "warn" if res["dns"]["errors"] else "ok"),
        kpi("📨 Kafka errors", kafka_errors, f"{res['kafka']['requests']} requests decoded", "warn" if kafka_errors else "ok"),
        kpi("🌍 HTTP errors", http_errors, f"{res['http']['requests']} requests decoded",
            "danger" if any(g["code"] >= 500 or g["code"] in (401, 403) for g in res["http"]["errors"]) else "warn" if http_errors else "ok"),
    ])
    recs = "".join(f'<div class="rec-card {f["severity"].lower()}"><span class="rec-badge {f["severity"].lower()}">'
                   f'{SEVERITY_ICONS.get(f["severity"], "")} {_e(f["severity"])}</span><span class="rec-text">{_e(f["text"])}</span></div>'
                   for f in res["findings"])

    charts = ["<div class='charts-grid'>",
              f"<div class='chart-card'><h2>📈 Packets per second</h2>{svg_columns(res['timeline'], [('packets', 'packets', SERIES_1)], '')}</div>"]
    if res["resets"] or res["retransmissions"]:
        legend = (f"<div class='legend'><i style='background:{SERIES_1}'></i>resets"
                  f"<i style='background:{SERIES_2}'></i>retransmissions</div>")
        charts.append(f"<div class='chart-card'><h2>⚠️ Resets and retransmissions per second</h2>{legend}"
                      + svg_columns(res["timeline"], [("resets", "resets", SERIES_1), ("retransmissions", "retransmissions", SERIES_2)], "")
                      + "</div>")
    conv_rows = [(f"{x['client']} → {x['server']}", x["bytes"], f"{x['frames']} frames, {fmt_bytes(x['bytes'])}, {x['status']}")
                 for x in res["conversations"][:12]]
    charts.append(f"<div class='chart-card'><h2>🔝 Top TCP conversations (bytes)</h2>{svg_hbars(conv_rows, lambda v: fmt_bytes(int(v)))}</div>")
    charts.append("</div>")

    def st(s):
        return f"<span class='st {_e(s.replace(' ', '-'))}'>{_e(s or '-')}</span>"

    sections = []
    rows = "".join(f"<tr><td class='mono'>{_e(x['client'])}</td><td class='mono'>{_e(x['server'])}</td><td>{st(x['status'])}</td>"
                   f"<td class='num'>{x['frames']}</td><td class='num'>{_e(fmt_bytes(x['bytes']))}</td><td class='num'>{x['start_s']}s</td>"
                   f"<td class='num'>{x['duration_s']}s</td><td class='num'>{_e(fmt_ms(x['handshake_ms']))}</td>"
                   f"<td class='num'>{x['retransmissions'] or ''}</td><td class='num'>{x['syn_retries'] or ''}</td></tr>"
                   for x in res["conversations"])
    tcp_section = ""
    if rows:
        h = res["handshake_ms"]
        hs = f" · handshake p50 {fmt_ms(h['p50'])}, p95 {fmt_ms(h['p95'])}" if h["count"] else ""
        tcp_section = (f"<div class='table-card'><h2>🔌 TCP conversations ({res['conversations_total']}{_e(hs)})</h2><table><tr><th>Client</th><th>Server</th>"
                        "<th>Status</th><th class='num'>Frames</th><th class='num'>Bytes</th><th class='num'>Start</th><th class='num'>Duration</th>"
                       f"<th class='num'>Handshake</th><th class='num'>Retrans.</th><th class='num'>SYN retries</th></tr>{rows}</table></div>")
    if c["refused"] or c["no_answer"] or c["reset"]:
        rows = "".join(f"<tr><td>{st('refused')}</td><td class='mono'>{_e(r['server'])}</td><td class='num'>{r['count']}</td></tr>" for r in c["refused"])
        rows += "".join(f"<tr><td>{st('no answer')}</td><td class='mono'>{_e(r['server'])}</td><td class='num'>{r['count']}</td></tr>" for r in c["no_answer"])
        rows += "".join(f"<tr><td>{st('reset')}</td><td class='mono'>{_e(r['direction'])}</td><td class='num'>{r['count']}</td></tr>" for r in c["reset"])
        sections.append(f"<div class='table-card'><h2>🚫 Failed and reset connections</h2><table><tr><th>What</th><th>Where</th><th class='num'>Count</th></tr>{rows}</table></div>")
    if res["tls"]["client_hellos"] or res["tls"]["alerts"]:
        rows = "".join(f"<tr><td>handshake</td><td class='mono'>{_e(x['server'])}</td><td></td><td class='num'>{x['count']}</td></tr>" for x in res["tls"]["client_hellos"])
        rows += "".join(f"<tr><td>{_e(a['level'])} alert <b>{_e(a['alert'])}</b></td><td class='mono'>{_e(a['from'])} → {_e(a['to'])}</td>"
                        f"<td>{_e(a['hint'])}</td><td class='num'>{a['count']}</td></tr>" for a in res["tls"]["alerts"])
        sections.append(f"<div class='table-card'><h2>🔐 TLS</h2><table><tr><th>What</th><th>Where</th><th>Likely cause</th><th class='num'>Count</th></tr>{rows}</table></div>")
    if res["kafka"]["requests"]:
        rows = "".join(f"<tr><td>{_e(a['api'])}</td><td class='num'>{a['requests']}</td><td class='num'>{a['responses']}</td>"
                       f"<td class='num'>{_e(fmt_ms(a['p50_ms']))}</td><td class='num'>{_e(fmt_ms(a['p95_ms']))}</td><td class='num'>{_e(fmt_ms(a['max_ms']))}</td>"
                       f"<td>{_e(', '.join(e['name'] + ' ×' + str(e['count']) for e in a['errors']))}</td></tr>" for a in res["kafka"]["apis"])
        clients = ", ".join(f"{_e(x['client_id'])} ({x['requests']})" for x in res["kafka"]["clients"])
        sections.append("<div class='table-card'><h2>📨 Kafka requests</h2><table><tr><th>API</th><th class='num'>Requests</th><th class='num'>Responses</th>"
                        f"<th class='num'>p50</th><th class='num'>p95</th><th class='num'>Max</th><th>Error codes</th></tr>{rows}</table>"
                        f"<p class='legend' style='margin-top:10px'>Response time = response − request, as seen from the capture. "
                        f"Fetch responses wait up to fetch.max.wait.ms on purpose. Clients: {clients or '-'}</p></div>")
    if res["http"]["requests"]:
        def status(c):
            cls = "refused" if c >= 500 else "reset" if c >= 400 else "established"
            return f"<span class='st {cls}'>{c}</span>"

        def exchange(x):
            def part(label, ctype, body):
                return (f"<p class='legend' style='margin:8px 0 4px'>{label}{(' · ' + _e(ctype)) if ctype else ''}</p>"
                        f"<pre>{_e(body) if body else '(no body)'}</pre>")
            return part("Request", x["request_content_type"], x["request_body"]) + part("Response", x["response_content_type"], x["response_body"])

        rows = "".join(f"<tr><td class='mono'>{_e(e['server'])}</td><td class='mono'>{_e(e['endpoint'])}</td><td class='num'>{e['requests']}</td>"
                       f"<td>{' '.join(status(x['code']) + ' ×' + str(x['count']) for x in e['statuses'])}</td>"
                       f"<td class='num'>{e['no_response'] or ''}</td><td class='num'>{_e(fmt_ms(e['p50_ms']))}</td>"
                       f"<td class='num'>{_e(fmt_ms(e['p95_ms']))}</td><td class='num'>{_e(fmt_ms(e['max_ms']))}</td></tr>"
                       for e in res["http"]["endpoints"])
        errors = "".join(f"<details{' open' if i == 0 else ''}><summary>{status(g['code'])} {_e(g['phrase'])} ×{g['count']} — <span class='mono'>{_e(g['endpoint'])}</span> on {_e(g['server'])}"
                         f" (first at {g['first_s']}s, from {_e(g['client'])}, answered in {_e(fmt_ms(g['time_ms']))})</summary>"
                         f"<p class='mono' style='margin-top:6px'>{_e(g['uri'])}</p>{exchange(g)}</details>" for i, g in enumerate(res["http"]["errors"]))
        sample = res["http"]["sample"]
        sample_html = (f"<details><summary>{status(sample['code'])} {_e(sample['phrase'])} — sample exchange: <span class='mono'>{_e(sample['endpoint'])}</span> on {_e(sample['server'])}</summary>"
                       f"<p class='mono' style='margin-top:6px'>{_e(sample['uri'])}</p>{exchange(sample)}</details>") if sample else ""
        sections.append("<div class='table-card'><h2>🌍 HTTP requests</h2><table><tr><th>Server</th><th>Endpoint</th><th class='num'>Requests</th>"
                        "<th>Status codes</th><th class='num'>No response</th><th class='num'>p50</th><th class='num'>p95</th><th class='num'>Max</th></tr>"
                        f"{rows}</table>"
                        + (f"<h2 style='margin-top:16px'>❌ Error responses</h2>{errors}" if errors else "")
                        + (f"<h2 style='margin-top:16px'>🔍 What the client sends</h2>{sample_html}" if sample_html else "")
                        + "<p class='legend' style='margin-top:10px'>Bodies are cut to their first 600 characters (1000 bytes captured per message). "
                          "Open the capture in Wireshark (Follow → HTTP Stream) for the whole exchanges.</p></div>")
    if res["dns"]["queries"]:
        rows = "".join(f"<tr><td>{_e(d['rcode'])}</td><td class='mono'>{_e(d['name'])}</td><td class='num'>{d['count']}</td></tr>" for d in res["dns"]["errors"])
        rows += "".join(f"<tr><td>slow ({d['seconds']}s)</td><td class='mono'>{_e(d['name'])}</td><td class='num'>1</td></tr>" for d in res["dns"]["slow"])
        sections.append(f"<div class='table-card'><h2>🌐 DNS ({res['dns']['queries']} queries)</h2>"
                        + (f"<table><tr><th>What</th><th>Name</th><th class='num'>Count</th></tr>{rows}</table>" if rows else "<p>✅ No DNS error.</p>")
                        + "</div>")
    # the conversations come after the protocol sections: they are long, and the findings point to the sections above
    sections.append(tcp_section)
    rows = "".join(f"<tr><td>{_e(p['protocol'])}</td><td class='num'>{p['packets']}</td></tr>" for p in res["protocols"])
    hosts = "".join(f"<tr><td class='mono'>{_e(h['ip'])}</td><td>{_e(h['name'])}</td></tr>" for h in res["hosts"])
    sections.append(f"<div class='table-card'><h2>🧬 Protocols</h2><table><tr><th>Protocol</th><th class='num'>Packets</th></tr>{rows}</table>"
                    + (f"<details style='margin-top:12px'><summary>🏷️ Names used for the ip addresses ({len(res['hosts'])})</summary>"
                       f"<table><tr><th>IP</th><th>Name</th></tr>{hosts}</table></details>" if hosts else "")
                    + "</div>")

    v_cls, v_text = html_verdict(res)
    meta = [f"&#128196; {_e(title)}", f"{_e(res['start'] or '?')} → {_e(res['end'] or '?')}",
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"]
    return ("<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>Network capture report — {_e(title)}</title>{_HTML_CSS}</head><body><div class='page'>"
            "<div class='header'><h1>🦈 Network Capture Analysis</h1><div class='header-meta'>"
            + "".join(f"<span>{m}</span>" for m in meta) + "</div></div>"
            + f"<div class='verdict {v_cls}'>{_e(v_text)}</div>"
            + f"<div class='kpi-grid'>{kpis}</div>"
            + "<div class='section-title'>🔎 Findings</div>" + f"<div class='recs-list'>{recs}</div>"
            + "".join(charts) + "".join(sections)
            + "<div class='footer'>🛠️ Generated by playground analyze tcp-dump (self-contained, no external resource). "
            "Open the capture with Wireshark for the packets themselves.</div>"
            "</div></body></html>")


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", required=True, help="folder written by extract.sh")
    ap.add_argument("--title", default="capture", help="name of the capture, for the reports")
    ap.add_argument("--hosts", help="hosts file: <ip> <name> per line")
    ap.add_argument("--json", action="store_true", help="Output JSON")
    ap.add_argument("--html-out", metavar="PATH", help="Write a self-contained HTML report")
    ap.add_argument("--top", type=int, default=10, metavar="N", help="Rows per section (default: 10)")
    args = ap.parse_args()

    top = max(1, args.top)
    res = analyze(args.data, read_hosts(args.hosts), top)
    if not res["packets"]:
        msg = f"No packet in {args.title}: check the capture filter, and that the traffic happened during the capture."
        if args.json:
            print(json.dumps({"error": msg}, indent=2))
        else:
            print(f"❌ {msg}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps({"capture": args.title, **res}, indent=2, default=str))
    else:
        print(text_report(res, args.title, top))
    if args.html_out:
        with open(args.html_out, "w", encoding="utf-8") as fh:
            fh.write(html_report(res, args.title))
    return 0


if __name__ == "__main__":
    sys.exit(main())
