"""
CFK Bundle Analyzer — problem statement and data to request.

--problem "<symptom, since when>": what the customer reports, matched against the analysis of the bundle
(deterministic: keywords and date formats, no LLM, same approach as tools/xstream-analyzer --problem). The components,
symptoms and dates of the text rank the issues that explain it first, the dates are checked against the time range of
the logs and the changes of the CRs, and a verdict says whether the bundle explains the problem.

data_to_request(): what to ask the customer for next, with why and the command to send: from the gaps of the bundle
(logs that start too late, restarted containers, no events, no operator log), from its findings (OOMKilled, Pending
pods, TLS…) and from the symptoms of the problem statement.
"""

import re
from datetime import datetime, timedelta
from typing import Dict, List, Optional

MONTHS = {m: i for i, m in enumerate(("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"), 1)}

# words of the problem statement -> component (analyzer.COMPONENTS), most specific first
COMPONENT_WORDS = (
    ("kraftcontroller", r"\bkraft ?controllers?\b|\bkraft\b|\bcontroller quorum\b|\bquorum\b"),
    ("zookeeper", r"\bzoo ?keeper\b|\bzk\b"),
    ("schemaregistry", r"\bschema[ -]?registry\b|\bsr\b"),
    ("ksqldb", r"\bksql(?:db)?\b"),
    ("controlcenter", r"\bcontrol[ -]?center\b|\bc3\b"),
    ("kafkarestproxy", r"\brest[ -]?proxy\b|\bkafka[ -]rest\b"),
    ("operator", r"\boperator\b|\bcfk\b|\breconcil"),
    ("connect", r"\bconnect(?:or|ors)?\b|\bsink\b|\bsource\b|\bkafka connect\b|\bworkers?\b"),
    ("kafka", r"\bbrokers?\b|\bkafka\b"),
)

# symptom -> (words of the problem statement, categories of the issues that explain it, data to request for it:
# (key, what, why, command)). The key lists once the same data asked for by a gap, a finding and a symptom
SYMPTOMS: Dict[str, tuple] = {
    "roll / upgrade stuck": (
        r"\broll(?:ing|out)?\b|\bupgrad|\bstuck\b.*\b(?:restart|update)|\bnot (?:rolling|updating|applied)\b|\bblock(?:ed)?[ -]reconcile",
        {"Rollout Issues", "Reconciliation Blocked", "Operator Issues", "Component Status", "Recent Changes",
         "Compatibility", "Finalizer Issues", "Pod Failures"},
        [("operator-log", "the operator log over the time of the roll", "the operator logs why it does not roll (pre-roll checks, reconcile errors)",
          "kubectl logs deployment/confluent-operator -n <operator namespace> --since=<duration> > operator.log"),
         ("cr-yaml", "the StatefulSet and the CR before and after the change", "what the CR asks for versus what runs",
          "kubectl get sts,<kind> <name> -n <namespace> -o yaml > after.yaml"),
         ("second-bundle", "a second support bundle once the roll is done or stuck again", "compared with this one: what changed, issues fixed / new",
          "kubectl confluent support-bundle --namespace <namespace>   # then: playground analyze logs -f before.tar.gz -f after.tar.gz")]),
    "crash / restarts": (
        r"\bcrash|\brestart|\bcrashloop|\bbackoff\b|\bback-off\b|\bkeeps? (?:dying|failing)\b|\bnot (?:starting|ready|coming up)\b|\bdown\b",
        {"Pod Failures", "Container Status", "Pod Status", "Health Check Issues", "Resource Issues", "Init Container Issues",
         "Image Issues", "Configuration", "Storage Issues", "Volume Issues"},
        [("previous-logs", "the log of each container before its last restart", "the crash itself is in the previous container, not in the current one",
          "kubectl logs <pod> -c <container> -n <namespace> --previous > <pod>-previous.log"),
         ("describe-pods", "the description of the pods", "last state, termination reason and exit code, probe failures",
          "kubectl describe pod <pod> -n <namespace>")]),
    "pending / scheduling": (
        r"\bpending\b|\bschedul|\bunschedulable\b|\bnode affinity\b|\btaint|\bno nodes?\b",
        {"Scheduling Issues", "Pod Status", "Volume Issues", "Storage Issues", "Resource Issues"},
        [("nodes", "the nodes and the volumes", "why the scheduler refuses the pod: capacity, taints, affinity, unbound PVC",
          "kubectl describe nodes > nodes.txt; kubectl get pvc,pv -n <namespace> -o wide")]),
    "memory / OOM": (
        r"\bmemory\b|\boom|\bout of memory\b|\bheap\b|\bgc\b|\bgarbage",
        {"Resource Issues", "Pod Failures", "Container Status"},
        [("heap", "the resources and JVM settings of the pods", "the heap must fit in the memory limit of the container",
          "kubectl get <kind> <name> -n <namespace> -o yaml   # spec.podTemplate.resources, configOverrides.jvm"),
         ("heap-dump", "a heap dump and the GC log of the JVM", "what fills the heap (playground analyze heap-dump / gc-logs)",
          "kubectl exec <pod> -n <namespace> -- jcmd 1 GC.heap_dump /tmp/heap.hprof && kubectl cp <namespace>/<pod>:/tmp/heap.hprof heap.hprof")]),
    "TLS / certificate": (
        r"\btls\b|\bssl\b|\bcert|\bhandshake\b|\btruststore\b|\bkeystore\b|\bpkix\b|\bx509\b",
        {"Certificate/TLS Issues", "JVM Truststore Issues", "Network Issues"},
        [("tls-chain", "the certificate chain served by the endpoint and its dates", "expired certificate, wrong SAN, missing CA",
          "openssl s_client -connect <host>:<port> -showcerts </dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName"),
         ("tls-secrets", "the TLS secrets and cert-manager Certificates", "which certificate the CRs use and when it was renewed",
          "kubectl get secret,certificate -n <namespace>; kubectl describe certificate <name> -n <namespace>")]),
    "auth / RBAC": (
        r"\bauth|\brbac\b|\bmds\b|\bldap\b|\bsasl\b|\bpermission|\bdenied\b|\bunauthori[sz]ed\b|\b40[13]\b|\bacl|\bprincipal\b|\bkerberos\b",
        {"Authentication Issues", "RBAC Issues", "MDS/RBAC Issues", "License Issues", "Certificate/TLS Issues"},
        [("mds", "the MDS log and the role bindings", "which principal is denied, on which resource",
          "kubectl logs kafka-0 -n <namespace> | grep -i -E 'mds|authoriz' ; kubectl get confluentrolebinding -n <namespace> -o yaml"),
         ("credentials", "the principal and credentials secret the failing component uses", "a wrong or rotated secret is the usual cause",
          "kubectl get <kind> <name> -n <namespace> -o yaml   # spec.authentication, spec.dependencies")]),
    "KRaft migration": (
        r"\bmigrat|\bzk to kraft\b|\bzookeeper to kraft\b|\bdual[- ]write\b|\bkraftmigrationjob\b",
        {"KRaft Migration", "KRaft Issues", "Zookeeper Issues", "Rollout Issues", "Operator Issues"},
        [("kraft-migration", "the KRaftMigrationJob and the KRaftController log", "the phase and sub-phase where the migration waits",
          "kubectl get kraftmigrationjob -n <namespace> -o yaml; kubectl logs kraftcontroller-0 -n <namespace> --since=<duration>"),
         ("kraft-quorum", "the state of the KRaft quorum", "a quorum without leader blocks the migration",
          "kubectl exec kafka-0 -n <namespace> -- kafka-metadata-quorum --bootstrap-controller <controller>:9074 describe --status")]),
    "connector failed": (
        r"\bconnector|\btask|\bsink\b|\bsource\b|\bdlq\b|\bdead letter\b|\bsmt\b|\bplugin",
        {"Connect Issues", "Plugin Issues", "Serialization Issues", "Kafka Issues", "Other Exceptions (Unclassified)",
         "Other Errors (Unclassified)", "Init Container Issues"},
        [("connector-status", "the status and config of the connector", "the trace of the failed task and the keys involved",
          "kubectl exec connect-0 -n <namespace> -- curl -s localhost:8083/connectors/<connector>/status; "
          "kubectl get connector <connector> -n <namespace> -o yaml"),
         ("connect-log", "the Connect worker log over the time of the failure", "the full stack trace and what the task did before",
          "kubectl logs connect-0 -n <namespace> --since=<duration> > connect-0.log")]),
    "slow / lag / hang": (
        r"\bslow|\blag\b|\blagging\b|\blatency\b|\bdelay|\bbehind\b|\bthroughput\b|\bhang|\bhung\b|\bfrozen\b|\bno (?:new )?(?:records?|data|messages?)\b",
        {"Connect Issues", "Replication Issues", "Kafka Issues", "Resource Issues", "Network Issues", "Health Check Issues"},
        [("thread-dumps", "3 thread dumps 5 seconds apart of the slow JVM", "where the threads wait (playground analyze thread-dump)",
          "for i in 1 2 3; do kubectl exec <pod> -n <namespace> -- jcmd 1 Thread.print > threads-$i.txt; sleep 5; done"),
         ("lag", "the consumer lag of the connector or application", "whether it makes progress at all",
          "kubectl exec kafka-0 -n <namespace> -- kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group <group>")]),
    "disk / storage": (
        r"\bdisk|\bstorage\b|\bvolume|\bpvc\b|\bno space\b|\bfull\b|\blog ?dirs?\b",
        {"Storage Issues", "Volume Issues", "Scheduling Issues"},
        [("volumes", "the volumes and their usage", "a full or unbound volume stops the broker",
          "kubectl get pvc -n <namespace>; kubectl exec <pod> -n <namespace> -- df -h /mnt/data")]),
    "network": (
        r"\bnetwork|\bdns\b|\bresolv|\btimeout|\btimed out\b|\bconnection refused\b|\bunreachable\b|\bload ?balancer\b|\bingress\b|\broute\b",
        {"Network Issues", "Kafka Issues", "Replication Issues", "Certificate/TLS Issues"},
        [("network-test", "a network test from the pod to the endpoint", "DNS, firewall, NetworkPolicy or load balancer",
          "kubectl exec <pod> -n <namespace> -- bash -c 'getent hosts <host>; timeout 5 bash -c \"</dev/tcp/<host>/<port>\" && echo open'"),
         ("services", "the services, endpoints and NetworkPolicies", "what the clients connect to",
          "kubectl get svc,endpoints,networkpolicy,ingress -n <namespace> -o wide")]),
}


def _dates(text: str, ref: datetime) -> List[datetime]:
    """Dates (with their time when given) of the problem statement; ref: the collection time of the bundle"""
    out = []
    time_rx = r"(?:[ T,]+(?:at\s+)?(\d{1,2}):(\d{2}))?"
    for m in re.finditer(rf"\b(\d{{4}})-(\d{{2}})-(\d{{2}}){time_rx}", text):
        out.append((int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4), m.group(5)))
    mon = r"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?"
    for m in re.finditer(rf"\b(?<!:)(\d{{1,2}})(?:st|nd|rd|th)?(?:\s+of)?[\s-]+{mon}(?:[\s,-]+(\d{{4}}))?{time_rx}", text, re.I):
        out.append((int(m.group(3) or ref.year), MONTHS[m.group(2).lower()[:3]], int(m.group(1)), m.group(4), m.group(5)))
    for m in re.finditer(rf"\b{mon}\s+(\d{{1,2}})(?:st|nd|rd|th)?\b(?![:.]\d)(?:,?\s+(\d{{4}}))?{time_rx}", text, re.I):
        out.append((int(m.group(3) or ref.year), MONTHS[m.group(1).lower()[:3]], int(m.group(2)), m.group(4), m.group(5)))
    parsed = []
    for y, mo, d, hh, mm in out:
        try:
            parsed.append(datetime(y, mo, d, int(hh or 0), int(mm or 0)))
        except ValueError:
            continue
    for word, days in (("today", 0), ("yesterday", 1)):
        m = re.search(rf"\b{word}\b{time_rx}", text, re.I)
        if m:
            day = ref - timedelta(days=days)
            parsed.append(datetime(day.year, day.month, day.day, int(m.group(1) or 0), int(m.group(2) or 0)))
    m = re.search(r"\b(\d+)\s*(minute|hour|day)s?\s+ago\b", text, re.I)
    if m:
        unit = {"minute": "minutes", "hour": "hours", "day": "days"}[m.group(2).lower()]
        parsed.append((ref - timedelta(**{unit: int(m.group(1))})).replace(second=0, microsecond=0))
    return sorted(set(parsed))


def _ts(value) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.strptime(str(value).replace("T", " ").replace("Z", "")[:19], "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def _fmt(d: datetime) -> str:
    return d.strftime("%Y-%m-%d %H:%M") if (d.hour or d.minute) else d.strftime("%Y-%m-%d")


def _instances(results: Dict) -> Dict[str, str]:
    """CR / pod names of the bundle -> component, to find them in the problem statement"""
    names = {}
    for i in results.get("issues") or []:
        if i.get("instance") and i.get("component"):
            names[i["instance"]] = i["component"]
    for c in results.get("timeline") or []:
        if c.get("instance") and c.get("component"):
            names[c["instance"]] = c["component"]
            names[c["name"]] = c["component"]
    return {n: c for n, c in names.items() if len(n) >= 4}


def parse(text: str, results: Dict) -> Dict:
    """Components, CR names, symptoms and dates of a free-text problem statement"""
    ref = _ts(results.get("collected")) or datetime.now()
    components, instances = [], []
    for name, component in sorted(_instances(results).items(), key=lambda kv: -len(kv[0])):
        if re.search(rf"(?<![\w-]){re.escape(name)}(?![\w-])", text, re.I):
            instances.append(name)
            if component not in components:
                components.append(component)
    for component, rx in COMPONENT_WORDS:
        if component not in components and re.search(rx, text, re.I):
            components.append(component)
    symptoms = [name for name, (rx, _, _) in SYMPTOMS.items() if re.search(rx, text, re.I)]
    # "stuck" alone (the connector is stuck) is a hang; "roll stuck", "migration stuck" are their own symptom
    if not symptoms and re.search(r"\bstuck\b", text, re.I):
        symptoms.append("slow / lag / hang")
    return {"text": text, "components": components, "instances": instances, "symptoms": symptoms,
            "dates": _dates(text, ref)}


def _issue_time(issue: Dict) -> tuple:
    return _ts(issue.get("first_seen") or issue.get("timestamp")), _ts(issue.get("timestamp"))


def _near(issue: Dict, dates: List[datetime]) -> bool:
    """the issue happened on the day of the problem (from 12 hours before to 1 day after)"""
    first, last = _issue_time(issue)
    if not first and not last:
        return False
    first, last = first or last, last or first
    return any(first - timedelta(days=1) <= d <= last + timedelta(hours=12) for d in dates)


def correlate(results: Dict, problem: Dict) -> Dict:
    """Marks the issues that match the problem (issue['problem_match']: why), and returns the 🎯 section: verdict, facts
    on the dates (log coverage, changes before), issues that explain it"""
    components = set(problem["components"])
    instances = set(problem["instances"])
    wanted = set()
    for s in problem["symptoms"]:
        wanted |= SYMPTOMS[s][1]
    dates = problem["dates"]
    matched = []
    for issue in results.get("issues") or []:
        if issue.get("transient") or issue.get("category") == "Bundle Coverage":
            continue
        why = []
        if instances and issue.get("instance") in instances:
            why.append(f"instance {issue['instance']}")
        elif components and issue.get("component") in components:
            why.append(f"component {issue['component']}")
        if wanted and issue.get("category") in wanted:
            why.append(f"symptom ({issue['category']})")
        if dates and _near(issue, dates):
            why.append("date")
        # a component alone is not enough when symptoms were given, a date alone never is
        strong = ("symptom" in " ".join(why) and (not components or any(w.startswith(("component", "instance")) for w in why))) \
            or (not wanted and any(w.startswith(("component", "instance")) for w in why))
        if strong:
            issue["problem_match"] = ", ".join(why)
            matched.append(issue)
    order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
    matched.sort(key=lambda i: (order.get(i.get("severity"), 4), "date" not in i["problem_match"], -i.get("count", 1)))

    facts = []
    windows = (results.get("coverage") or {}).get("log_windows") or []
    uncovered = []
    for d in dates:
        day_end = d + (timedelta(days=1) if not (d.hour or d.minute) else timedelta(minutes=1))
        covering = [w for w in windows if (_ts(w.get("first")) or datetime.max) < day_end and (_ts(w.get("last")) or datetime.min) >= d]
        if windows and not covering:
            first = min(w["first"] for w in windows)
            last = max(w["last"] for w in windows)
            facts.append(f"❌ no log of the bundle covers {_fmt(d)}: they go from {first} to {last}")
            uncovered.append(d)
        elif covering:
            late = [w for w in windows if w not in covering and (_ts(w.get("first")) or datetime.min) > d]
            facts.append(f"✅ {len(covering)} log(s) cover {_fmt(d)}"
                         + (f"; {len(late)} start after it ({', '.join(w.get('pod') or w['file'] for w in late[:4])})" if late else ""))
        changes = [c for c in results.get("timeline") or []
                   if (t := _ts(c.get("time"))) and d - timedelta(hours=24) <= t <= day_end]
        for c in changes[:6]:
            facts.append(f"🕒 change on {c['time'].replace('T', ' ').replace('Z', '')}: {c['kind']}/{c['name']} {c['what']}")
    if components:
        found = {i.get("component") for i in results.get("issues") or [] if not i.get("transient")}
        missing = [c for c in problem["components"] if c not in found]
        if missing:
            facts.append(f"ℹ️ no issue for {', '.join(missing)} in the bundle")

    serious = [i for i in matched if i.get("severity") in ("critical", "high", "medium")]
    if serious:
        verdict = ("explained", f"🎯 {len(serious)} issue(s) of the bundle match the problem: start with "
                                f"{serious[0]['category']} ({serious[0].get('component', 'other')})")
    elif matched:
        verdict = ("partly explained", f"🔎 only {len(matched)} low issue(s) match the problem: the bundle may not show the cause")
    elif uncovered:
        verdict = ("not covered", "🤷 not explained by this bundle: its logs do not cover the date of the problem, "
                                  "see 📥 Data to request")
    else:
        verdict = ("not explained", "🤷 not explained by this bundle: no issue matches the components and symptoms of the "
                                    "problem, see 📥 Data to request")
    return {"text": problem["text"], "components": problem["components"], "instances": problem["instances"],
            "symptoms": problem["symptoms"], "dates": [_fmt(d) for d in dates], "verdict": verdict[0],
            "verdict_text": verdict[1], "facts": facts,
            "matching_issues": [{k: i.get(k) for k in ("severity", "category", "component", "instance", "message", "file",
                                                       "line_number", "timestamp", "problem_match")} for i in matched[:8]],
            "nb_matching_issues": len(matched)}


def data_to_request(results: Dict, problem: Optional[Dict] = None) -> List[Dict]:
    """What to ask the customer for next: [{what, why, command, source}], source: bundle (a gap of the bundle), finding (an
    issue of the bundle) or problem (a symptom of --problem)"""
    out: List[Dict] = []
    seen = set()

    def add(key, what, why, command, source):
        if key not in seen:
            seen.add(key)
            out.append({"what": what, "why": why, "command": command, "source": source})

    coverage = results.get("coverage") or {}
    windows = coverage.get("log_windows") or []
    issues = [i for i in results.get("issues") or [] if not i.get("transient")]
    categories = {i.get("category") for i in issues}
    dates = [d for d in (problem or {}).get("dates") or []]

    # logs that start after the date of the problem, or too late (Bundle Coverage finding)
    if dates:
        late = [w for w in windows if (_ts(w.get("first")) or datetime.min) > min(dates)]
        if late:
            pods = ", ".join(sorted({w.get("pod") or w["file"] for w in late})[:6])
            collected = _ts(results.get("collected")) or datetime.now()
            since = max(1, int((collected - min(dates)).total_seconds() // 3600) + 1)
            add("logs-since", f"the logs of {pods} from before {_fmt(min(dates))}",
                "their log in the bundle starts after the date of the problem",
                f"kubectl logs <pod> -n <namespace> --since={since}h > <pod>.log   # or the export of the log aggregator for that time",
                "bundle")
    if "Bundle Coverage" in categories:
        add("logs-since", "the full logs of the pods whose log starts too late",
            "the bundle keeps the end of each log: what happened before is not in it (🕰️ Log coverage)",
            "kubectl logs <pod> -n <namespace> --since=<duration> > <pod>.log", "bundle")
    # restarted containers: the crash is in the previous container
    restarted = sorted({c["name"] for c in results.get("timeline") or []
                        if c.get("kind") == "Pod" and re.search(r"terminated|restart", c.get("what", ""))})
    if restarted:
        logs = {w.get("pod") for w in windows if "previous" in w.get("file", "").lower()}
        missing = [p for p in restarted if p not in logs]
        if missing:
            add("previous-logs", f"the log before the last restart of {', '.join(missing[:6])}",
                "the container restarted: the error that stopped it is in the previous container, not in the bundle",
                "kubectl logs <pod> -c <container> -n <namespace> --previous > <pod>-previous.log", "bundle")
    # events: none, or all younger than the problem (events expire after 1 hour by default)
    event_times = [t for i in issues if "event" in (i.get("file") or "").lower() for t in [_ts(i.get("first_seen") or i.get("timestamp"))] if t]
    if not coverage.get("events"):
        add("events", "the Kubernetes events of the namespace", "the bundle has no event (they expire after 1 hour by default)",
            "kubectl get events -n <namespace> --sort-by=.lastTimestamp > events.txt   # right after the problem happens again",
            "bundle")
    elif dates and event_times and min(event_times) > max(dates):
        add("events", "the Kubernetes events at the time of the problem",
            f"the oldest event of the bundle ({min(event_times):%Y-%m-%d %H:%M}) is after the problem: events expire after 1 hour by default",
            "kubectl get events -n <namespace> --sort-by=.lastTimestamp > events.txt   # right after the problem happens again",
            "bundle")
    # no operator log
    if not any(re.search(r"(^|/)operator(/|$)|confluent-operator", w.get("file", "")) for w in windows) \
            and "operator" not in (coverage.get("layout") or []):
        add("operator-log", "the CFK operator log", "the bundle has no operator log: how the operator reconciled the CRs is not in it",
            "kubectl logs deployment/confluent-operator -n <operator namespace> --since=<duration> > operator.log", "bundle")

    # from the findings of the bundle
    if any(i.get("category") == "Resource Issues" and re.search(r"oom", i.get("message", ""), re.I) for i in issues):
        add("heap", "the resources and JVM settings of the OOMKilled pods, a heap dump",
            "a container was OOMKilled: is the heap larger than the memory limit, or does something fill it?",
            "kubectl get <kind> <name> -n <namespace> -o yaml   # spec.podTemplate.resources, configOverrides.jvm; "
            "kubectl exec <pod> -n <namespace> -- jcmd 1 GC.heap_dump /tmp/heap.hprof", "finding")
    if "Scheduling Issues" in categories:
        add("nodes", "the nodes and the volumes", "a pod cannot be scheduled (capacity, taints, affinity, unbound PVC)",
            "kubectl describe nodes > nodes.txt; kubectl get pvc,pv -n <namespace> -o wide", "finding")
    if categories & {"Certificate/TLS Issues", "JVM Truststore Issues"}:
        add("tls-chain", "the certificate chain served by the endpoint and its dates", "TLS errors in the bundle: expired certificate, wrong SAN, missing CA",
            "openssl s_client -connect <host>:<port> -showcerts </dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName",
            "finding")
    if "Connect Issues" in categories:
        add("connector-status", "the status and config of the failed connectors", "the trace of the failed task and the keys involved",
            "kubectl exec connect-0 -n <namespace> -- curl -s localhost:8083/connectors/<connector>/status", "finding")

    # from the symptoms of the problem statement
    for s in (problem or {}).get("symptoms") or []:
        for key, what, why, command in SYMPTOMS[s][2]:
            add(key, what, why, command, "problem")
    return out
