"""
Known CFK issues: the log messages / events of the CFK triage table of Confluent support, with what they mean and
what to do. Matched on the message and the `Caused by:` chain of every issue of the bundle (case-insensitive), so
a bundle that hits a known issue shows it on top of the report, with the KB / docs to read.

Public part: patterns, a short explanation and public links only (support.confluent.io KBs, docs.confluent.io).
Confluent support keeps the internal runbook of each entry in an optional private file, mounted by
playground analyze logs (PLAYGROUND_CFK_RUNBOOKS_FILE, default
reproduction-models/_miscellaneous/cfk-analysis/runbooks-internal.json), path in $CFK_RUNBOOKS_PRIVATE:

    {
      "links": {"<name>": [{"title": "...", "url": "https://..."}]},
      "runbooks": [{"name": "...", "title": "...", "pattern": "...", "advice": "...",
                    "links": [{"title": "...", "url": "..."}]}]
    }

"links" adds internal links to the entries below (by name), "runbooks" adds entries. Internal links are shown with
a 🔒 in the text digest, the HTML report and --json.

Patterns follow tools/report-common/known_causes.py: unbounded `.*` are written `.{0,N}`. "operator_info": True also
matches the lines of the operator logs without an ERROR / WARN level: the operator logs some of these states at INFO
("cluster not rollable from roll pre checks", "Migration current status … requeuing").
"""

import json
import os
import re
import sys
from typing import Dict, List, Optional

_SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3}

KB = "https://support.confluent.io/hc/en-us/articles/"
DOCS = "https://docs.confluent.io/operator/current/"

RUNBOOKS = [
    {"name": "operator_cache_sync",
     "title": "CFK operator in a crash loop: caches not synced",
     "pattern": r"failed to wait for .{0,80}caches to sync|timed out waiting for cache to be synced",
     "advice": "the operator cannot list the resources it watches before its timeout: check its RBAC (ClusterRole / "
               "Role of the namespaces it watches), the installed CRDs against the operator version, and the API "
               "server load",
     "links": [{"title": "How to fix CFK operator pod in a crash loop", "url": KB + "7456942914964"},
               {"title": "How to troubleshoot operator deployment issue with Confluent for Kubernetes",
                "url": KB + "24547387707796"}]},
    {"name": "roll_blocked",
     "title": "Roll blocked by the pre-roll checks",
     "pattern": r"cluster not rollable from roll pre checks|brokers? reported under replicated partitions"
                r"|waiting for at-least one kafka pod availability",
     "operator_info": True,
     "advice": "CFK only rolls a healthy cluster: it waits for the under-replicated partitions to recover and for the "
               "pods to be Ready. When the pods can only become Ready with the change the roll would apply (expired "
               "certificate, authorizer that cannot start), the roll is deadlocked: fix that cause first",
     "links": []},
    {"name": "certificate_expired",
     "title": "Expired certificate",
     "pattern": r"CertificateExpiredException|CertPathValidatorException: validity check failed",
     "advice": "a certificate (or its CA) expired. Renewing the secret after expiry can leave the roll stuck: only the "
               "pods restarted with the new certificate can talk to each other, so look at which pods run the new one",
     "links": [{"title": "Manage TLS certificates", "url": DOCS + "co-network-encryption.html"}]},
    {"name": "jaas_context",
     "title": "Could not obtain JAAS context (KRaft, SASL/PLAIN with and without LDAP)",
     "pattern": r"Could not obtain JAAS context",
     "advice": "a SASL/PLAIN listener (file based users) and a SASL/PLAIN with LDAP listener get mixed JAAS configs: "
               "use jaasConfigPassThrough on the listener as the KB explains",
     "links": [{"title": "How to bypass the exception \"Could not obtain JAAS context\" in KRaft mode with CFK",
                "url": KB + "31693926274964"}]},
    {"name": "kraft_migration",
     "title": "ZooKeeper to KRaft migration (KRaftMigrationJob)",
     "pattern": r"Migration current status \S+/SubPhase|missing inter replication credentials",
     "operator_info": True,
     "advice": "follow the phase and sub-phase of the KRaftMigrationJob (status and operator log): the job requeues on "
               "the same sub-phase until its condition is met (roll complete, KRaftController healthy…). Check the "
               "KRaftController CR, its listeners and credentials, and the brokers roll",
     "links": [{"title": "Migrate from ZooKeeper to KRaft", "url": DOCS + "co-migrate-kraft.html"}]},
    {"name": "inconsistent_cluster_id",
     "title": "INCONSISTENT_CLUSTER_ID between KRaft controllers and brokers",
     "pattern": r"INCONSISTENT_CLUSTER_ID|setting kraft cluster id",
     "advice": "the controllers and the brokers have different cluster ids in their meta.properties (scale-up, storage "
               "class change, PV re-attached): compare the clusterID of the KRaftController and Kafka CR status with "
               "the meta.properties of each pod before changing anything",
     "links": []},
    {"name": "cluster_id_base64",
     "title": "KRaftController clusterId must be base64 encoded",
     "pattern": r"clusterId must be base64 encoded",
     "advice": "spec.clusterID of the KRaftController must be the 22 characters URL-safe base64 cluster id (no "
               "padding): use the cluster id of the existing Kafka cluster",
     "links": []},
    {"name": "license_secret",
     "title": "CFK license secret missing or malformed",
     "pattern": r"managed license secretRef .{0,80}does not contain|does not contain data license\.txt",
     "advice": "the license secret has no license.txt key: recreate it with the license in license.txt, global "
               "(operator Helm values) or per component (spec.license)",
     "links": [{"title": "Confluent Platform license with CFK", "url": DOCS + "co-license.html"}]},
    {"name": "authorizer_timeout",
     "title": "Authorizer did not start (MDS / RBAC broker startup)",
     "pattern": r"Authorizer did not start up within the timeout"
                r"|fatal error while waiting for all of the authorizer futures",
     "advice": "the broker exits because the authorizer cannot load (confluent.authorizer.init.timeout.ms). Two known "
               "causes with the same message: the MDS writer cannot bind LDAP (expired LDAP CA, wrong credentials), "
               "or partitions misclassified as stray. Check the LDAP errors of the lowest-ordinal broker first",
     "links": [{"title": "How to troubleshoot MDS Kafka Broker Startup Issues", "url": KB + "26698170020628"}]},
    {"name": "mds_endpoint_timeout",
     "title": "A component cannot call the MDS authorize endpoint (RBAC)",
     "pattern": r"Failed to send HTTP request to endpoint: \S{0,200}/security/1\.0/authorize",
     "advice": "look at the cause of the record. A timeout: the component discovered an MDS URL it cannot reach (often "
               "the external one), pin the internal endpoint with spec.dependencies.mds.endpoint and set "
               "confluent.metadata.enable.server.urls.refresh=false. A TLS handshake failure: its truststore does not "
               "trust the MDS certificate (spec.dependencies.mds.tls)",
     "links": []},
    {"name": "cluster_shrink",
     "title": "Cluster shrink workflow in progress",
     "pattern": r"Cluster is undergoing shrink workflow",
     "advice": "a scale down started the shrink workflow (partition reassignment before removing brokers): check its "
               "state in the Kafka CR conditions before changing the replicas again",
     "links": [{"title": "Scale Kafka clusters", "url": DOCS + "co-scale-cluster.html"}]},
    {"name": "release_version_used",
     "title": "KRaft controllers unreachable after kafka-features --release-version",
     "pattern": r"\[RaftManager id=\d+\].{0,200}UnknownHostException",
     "advice": "if the metadata version was upgraded with kafka-features ... --release-version (instead of the "
               "--metadata command CFK documents), kraft.version changed and the quorum looks for voters that do not "
               "resolve. Otherwise, check the DNS of the controller pods",
     "links": []},
    {"name": "pvc_resize_attached",
     "title": "PVC expansion refused while the disk is attached (Azure)",
     "pattern": r"cannot be resized to .{0,40}while it is attached to a running VM|ControllerResizeError",
     "advice": "a platform limit of the cloud disk (for example Azure managed disks past 4 TiB), not CFK: the disk "
               "must be detached (pod moved, node cordoned) for the resize to complete",
     "links": []},
    {"name": "pvc_shrink",
     "title": "PVC size cannot be reduced",
     "pattern": r"field can not be less than status\.capacity",
     "advice": "Kubernetes never shrinks a volume: the declared storage can only grow",
     "links": [{"title": "Scale storage", "url": DOCS + "co-scale-storage.html"}]},
    {"name": "auto_mirror_topic_delete",
     "title": "Reconciliation tries to delete auto-mirrored topics",
     "pattern": r"Auto-mirrored topic cannot be deleted",
     "advice": "with a wildcard auto.create.mirror.topics filter, older CFK versions try to delete the mirror topics "
               "and report the refusal as an error: noisy, mirroring keeps working",
     "links": []},
    {"name": "multi_attach",
     "title": "Volume Multi-Attach error",
     "pattern": r"Multi-Attach error for volume",
     "advice": "the volume is still attached to the previous node: a Kubernetes / storage provider issue, not CFK. It "
               "often clears in 10 to 15 minutes; otherwise the cluster admin detaches it",
     "links": []},
    {"name": "raft_metrics_jmx",
     "title": "Upgrade to CP 8.0: JMX reporter disabled (raft-metrics not found)",
     "pattern": r"InstanceNotFoundException: kafka\.server:type=raft-metrics",
     "advice": "with the telemetry reporter, CP 8.0 disables the JMX reporter CFK reads: set metric.reporters to "
               "include the JMX reporter in the KRaftController and Kafka CRs, as the upgrade notes explain",
     "links": [{"title": "Upgrade: disabled JMX reporter with the telemetry reporter in CP 8.0.0",
                "url": DOCS + "co-upgrade-overview.html#issue-disabled-jmx-reporter-when-using-telemetry-reporter-in-cp-8-0-0"}]},
    {"name": "roll_driver_secrets",
     "title": "Roll stuck: certificates directory not readable (directoryPathInContainer)",
     "pattern": r"unable to read directoryPathInContainer|invalid cert files at path"
                r"|unable to instantiate the kafka roll driver",
     "advice": "the operator cannot read the certificates the CR points to with directoryPathInContainer (Vault "
               "agent injection, Jolokia TLS without secretRef): give the operator access to them or use a secretRef",
     "links": []},
    {"name": "c3_basic_auth_format",
     "title": "Control Center: basic.txt secret in the wrong format",
     "pattern": r"basic\.txt in secretRef .{0,120}incorrect format",
     "advice": "each line of basic.txt must be username: password,<role1>,<role2>",
     "links": []},
    {"name": "kafka_not_running_state",
     "title": "Kafka CR status out of sync with its StatefulSet",
     "pattern": r"kafka cluster \[\S{1,80}\] not in running state",
     "advice": "compare status.replicas / readyReplicas of the Kafka CR with the StatefulSet: when the CR status is "
               "stale (0 replicas) while the pods run, the operator waits forever",
     "links": []},
    {"name": "telemetry_402",
     "title": "402 Payment Required with an OpenTelemetry Java agent",
     "pattern": r"402 Payment Required|this\.clientTelemetryReporter\" is null",
     "advice": "before looking at the license, check whether an OpenTelemetry Java agent is injected in the broker pods "
               "(instrumentation.opentelemetry.io/inject-java annotation, JAVA_TOOL_OPTIONS): a third-party agent",
     "links": []},
    {"name": "mrc_replication_listener",
     "title": "Brokers cannot reach their peers on the replication listener (9072)",
     "pattern": r"Connection to node -1 .{0,200}:9072\b.{0,40}could not be established",
     "advice": "expected for a few seconds while a broker restarts. When it lasts, and in a stretch (MRC) cluster that "
               "cannot bootstrap: the brokers resolve their peers through the replication Service, which only publishes "
               "Ready pods unless publishNotReadyAddresses: true",
     "links": []},
    {"name": "kafkatopic_stuck",
     "title": "KafkaTopic resource stuck or in error",
     "pattern": r"KafkaTopic/\S{1,120}.{0,80}(?:Terminating|ERROR)|metadata\.name: Invalid value",
     "advice": "a KafkaTopic CR stuck on its finalizer, in ERROR after a change made outside CFK, or with an invalid "
               "name. spec.replicas and spec.partitionCount cannot be changed through the CR",
     "links": [{"title": "Manage Kafka topics", "url": DOCS + "co-manage-topics.html"}]},
]


def _compile(entries: List[Dict]) -> List[Dict]:
    compiled = []
    for entry in entries:
        try:
            compiled.append(dict(entry, _re=re.compile(entry["pattern"], re.IGNORECASE)))
        except (KeyError, re.error) as e:
            print(f"warning: CFK runbook {entry.get('name', '?')} ignored: {e}", file=sys.stderr)
    return compiled


class Catalog:
    """Public runbooks, merged with the private file when there is one"""

    def __init__(self, private_file: Optional[str] = None):
        entries = [dict(e, internal_links=[]) for e in RUNBOOKS]
        self.private_file = None
        private_file = private_file if private_file is not None else os.environ.get("CFK_RUNBOOKS_PRIVATE")
        if private_file and os.path.isfile(private_file):
            try:
                with open(private_file, encoding="utf-8") as f:
                    private = json.load(f)
                by_name = {e["name"]: e for e in entries}
                for name, links in (private.get("links") or {}).items():
                    if name in by_name and isinstance(links, list):
                        by_name[name]["internal_links"] += [l for l in links if isinstance(l, dict) and l.get("url")]
                for extra in private.get("runbooks") or []:
                    if isinstance(extra, dict) and extra.get("name") and extra.get("pattern"):
                        entries.append(dict(extra, links=[], internal_links=list(extra.get("links") or [])))
                self.private_file = private_file
            except (OSError, ValueError, AttributeError) as e:
                print(f"warning: cannot read the private CFK runbooks {private_file}: {e}", file=sys.stderr)
        self.entries = _compile(entries)
        self.by_name = {e["name"]: e for e in self.entries}
        info = [e["pattern"] for e in self.entries if e.get("operator_info")]
        self.operator_info_re = re.compile("|".join(f"(?:{p})" for p in info), re.IGNORECASE) if info else None

    def match(self, text: str) -> List[str]:
        """Names of the runbooks whose pattern is in the text"""
        return [e["name"] for e in self.entries if e["_re"].search(text)]

    def summarize(self, issues: List[Dict]) -> List[Dict]:
        """Matched runbooks, worst severity first, with the number of issues and occurrences of each and the first
        issue as example"""
        found: Dict[str, Dict] = {}
        for issue in issues:
            for name in issue.get("runbooks") or []:
                entry = self.by_name.get(name)
                if entry is None:
                    continue
                hit = found.get(name)
                if hit is None:
                    hit = found[name] = {
                        "name": name, "title": entry.get("title", name), "advice": entry.get("advice", ""),
                        "links": entry.get("links") or [], "internal_links": entry.get("internal_links") or [],
                        "severity": issue.get("severity", "low"), "issues": 0, "occurrences": 0,
                        "example": {k: issue.get(k) for k in ("message", "file", "line_number", "component") if issue.get(k)},
                    }
                hit["issues"] += 1
                hit["occurrences"] += issue.get("count", 1)
                if _SEVERITY_ORDER.get(issue.get("severity"), 9) < _SEVERITY_ORDER.get(hit["severity"], 9):
                    hit["severity"] = issue["severity"]
        return sorted(found.values(), key=lambda h: (_SEVERITY_ORDER.get(h["severity"], 9), -h["occurrences"]))
