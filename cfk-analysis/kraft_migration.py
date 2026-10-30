"""
ZooKeeper to KRaft migration of a CFK support bundle: one finding per KRaftMigrationJob (KMJ), with its phase and
sub-phase, how long it has been there (Warning events of the KMJ, "Migration current status <phase>/<sub-phase>: …,
requeuing" lines of the operator log), the last error, and the next steps of that sub-phase.

Phases and sub-phases of the KMJ (status.phase / status.subPhase), in order:
  SETUP -> MIGRATE -> DUAL-WRITE (waits for the finalize or rollback annotation) -> MoveToKRaftControllerOnly -> COMPLETE,
  RollbackToZk when a rollback is triggered, FAILURE.
Next steps from https://docs.confluent.io/operator/current/co-migrate-kraft.html and its known issues page.
"""

import re
from datetime import datetime
from typing import Dict, List, Optional

DOCS = "https://docs.confluent.io/operator/current/co-migrate-kraft.html"
KNOWN_ISSUES = "https://docs.confluent.io/operator/current/co-migrate-kraft-known-issues.html"
COMMANDS = "https://docs.confluent.io/operator/current/co-migrate-kraft-command-reference.html"

# "Migration current status SETUP/SubPhaseSetupEnsureIBPUpgradeComplete: kafka [kafka] in namespace [x] roll not
# complete yet, requeuing ..." (operator log, INFO)
STATUS_LINE_RE = re.compile(r'Migration current status ([\w-]+)/(\w+):?\s*(.{0,300}?)(?:"|\s*$)')
_TS_RE = re.compile(r'\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d')

# a sub-phase seen in the operator log for longer than this, or with this many Warning events, is stuck
STUCK_MINUTES = 30
STUCK_EVENTS = 10

_ROLL = ("the Kafka roll is not complete: look at the Kafka pods (Ready, restarts) and at the roll of the operator log "
         "(\"cluster not rollable from roll pre checks\", under-replicated partitions)")
_TRACE_DEADLOCK = ("before CFK 2.9.5 / 2.10.1 / 2.11.1, inter.broker.protocol.version together with "
                   "log4j.logger.org.apache.kafka.metadata.migration=TRACE in the Kafka CR deadlocks the roll: remove one "
                   "of them (known issues page)")
_KRC_HEALTH = ("the KRaftController pods are not Ready: look at the KRaftController CR status, its pods and logs, and "
               "at the error of the Warning events of the KRaftMigrationJob, which names the field to fix (listeners, "
               "credentials, dependencies)")
_RBAC = ("RBAC: the KRaftController principal must be a super user of Kafka and the Kafka principal a super user of the "
         "KRaftController (spec.authorization.superUsers of both CRs, known issues page)")

# sub-phase -> (what it waits for, next steps)
SUB_PHASES = {
    "SubPhaseSetupPreChecks": ("the validation of the Kafka, ZooKeeper and KRaftController CRs",
                               ["the error of the Warning events of the KRaftMigrationJob says which check fails: fix the "
                                "CR it names (dependencies, names, versions)"]),
    "SubPhaseSetupDeriveIBPVersion": ("the inter-broker protocol (IBP) version to migrate with",
                                      ["with a custom image, CFK cannot derive the IBP from the tag: set "
                                       "platform.confluent.io/kraft-migration-ibp-version"]),
    "SubPhaseSetupAddMigrationAnnotation": ("the migration annotations on the CRs", []),
    "SubPhaseSetupCheckHealthyKafka": ("a healthy Kafka cluster",
                                       ["every Kafka pod must be Ready, with no under-replicated partition"]),
    "SubPhaseSetupCheckKafkaVersion": ("a Kafka version that supports the migration",
                                       ["check the Confluent Platform version of the Kafka CR against the migration docs"]),
    "SubPhaseSetupEnsureKRaftControllerExists": ("the KRaftController CR of spec.dependencies",
                                                 ["create the KRaftController CR (with "
                                                  "platform.confluent.io/kraft-migration-hold-krc-creation: \"true\"), "
                                                  "or fix its name / namespace in the KRaftMigrationJob"]),
    "SubPhaseSetupTriggerIBPUpgrade": ("the start of the Kafka roll that sets the IBP", [_ROLL]),
    "SubPhaseSetupEnsureIBPUpgradeComplete": ("the end of the Kafka roll that sets the IBP", [_ROLL, _TRACE_DEADLOCK]),
    "SubPhaseSetupFetchKafkaClusterId": ("the cluster id of Kafka for the KRaftController",
                                         ["spec.clusterID of the KRaftController must be the cluster id of Kafka"]),
    "SubPhaseSetupFetchKafkaZookeeperEndpoint": ("the ZooKeeper endpoint of the KRaftController",
                                                 ["the migration ZooKeeper dependency of the KRaftController (endpoint) "
                                                  "must be set"]),
    "SubPhaseSetupMutateKRaftController": ("the migration configuration of the KRaftController", []),
    "SubPhaseSetupKRaftControllerHealthy": ("Ready KRaftController pods", [_KRC_HEALTH, _RBAC]),
    "SubPhaseSetupCheckKraftControllerVersion": ("a KRaftController version that matches Kafka",
                                                 ["the KRaftController and Kafka CRs must run the same CP version"]),
    "SubPhaseMigrateTriggerKafkaMigration": ("the start of the Kafka roll with the migration configuration", [_ROLL]),
    "SubPhaseMigrateEnsureKafkaRollComplete": ("the end of the Kafka roll with the migration configuration", [_ROLL]),
    "SubPhaseMigrateMonitorMigrationProgress": ("the copy of the ZooKeeper metadata by the KRaft controllers",
                                                ["look at the KRaftController logs (org.apache.kafka.metadata.migration)",
                                                 "ZooKeeper digest authentication with zookeeper.set.acl=true: "
                                                 "MigrationClientAuthException / NoAuth in the KRaft logs, add the JAAS "
                                                 "override of the known issues page to the KRaftController",
                                                 _RBAC]),
    "SubPhaseMigrationDualWrite": ("the validation of the cluster, then the finalize (or rollback) annotation",
                                   ["expected pause: validate the cluster, then finalize with kubectl confluent cluster "
                                    "kraft-migration finalize (annotation "
                                    "platform.confluent.io/kraft-migration-trigger-finalize-to-kraft=true), or roll back "
                                    "with kubectl confluent cluster kraft-migration rollback"]),
    "SubPhaseRollbackToZkWaitForManualNodeRemovalFromZk": (
        "the manual removal of the /controller and /migration znodes of ZooKeeper",
        ["remove the /controller and /migration znodes with zookeeper-shell, then annotate the KRaftMigrationJob with "
         "platform.confluent.io/continue-kraft-migration-post-zk-node-removal=true"]),
    "SubPhaseRollbackToZkFromSetupWaitForManualNodeRemovalFromZk": (
        "the manual removal of the /controller and /migration znodes of ZooKeeper",
        ["remove the /controller and /migration znodes with zookeeper-shell, then annotate the KRaftMigrationJob with "
         "platform.confluent.io/continue-kraft-migration-post-zk-node-removal=true"]),
}
# the Kafka / KRaftController rolls of the other sub-phases (MoveToKRaftController…, RollbackToZk…)
_ROLL_SUB_PHASE_RE = re.compile(r'Roll|MigrationModeRemoval|ZkRemoval|ProcessRole|Overrides|Annotation|Deps', re.IGNORECASE)

COMMON_STEPS = [
    "kubectl get kraftmigrationjob <name> -n <namespace> -o jsonpath='{.status.phase}/{.status.subPhase}' "
    "(or kubectl confluent cluster kraft-migration status)",
    "kubectl get events -n <namespace> --field-selector involvedObject.kind=KRaftMigrationJob, and "
    "\"Migration current status\" in the operator log: the reason of each requeue",
    "the Kafka, ZooKeeper and KRaftController CRs are locked during the migration: a change applied to them (GitOps "
    "included) is not taken into account until the lock is released (platform.confluent.io/kraft-migration-release-cr-lock, "
    "see the docs)",
]


def _parse_ts(value) -> Optional[datetime]:
    if not value:
        return None
    m = _TS_RE.search(str(value))
    if not m:
        return None
    try:
        return datetime.strptime(m.group(0).replace('T', ' '), '%Y-%m-%d %H:%M:%S')
    except ValueError:
        return None


def _duration(first: Optional[datetime], last: Optional[datetime]) -> str:
    if not first or not last or last < first:
        return ""
    minutes = int((last - first).total_seconds() // 60)
    days, hours = minutes // (24 * 60), minutes % (24 * 60) // 60
    if days:
        return f"{days} day(s) {hours} hour(s)" if hours else f"{days} day(s)"
    if hours:
        return f"{hours} hour(s) {minutes % 60} minute(s)" if minutes % 60 else f"{hours} hour(s)"
    return f"{minutes} minute(s)"


def steps_for(sub_phase: str) -> List[str]:
    """Next steps of a sub-phase, then the common ones"""
    known = SUB_PHASES.get(sub_phase)
    if known:
        steps = list(known[1])
    elif _ROLL_SUB_PHASE_RE.search(sub_phase or ''):
        steps = [_ROLL]
    else:
        steps = []
    return steps + COMMON_STEPS


def finding(name: str, status: Dict, events: List[Dict], log_status: Dict) -> Optional[Dict]:
    """The finding of one KRaftMigrationJob, None when it is COMPLETE without errors.
    status: status of the CR (may be empty when the bundle has no KMJ CR); events: Warning events of the KMJ
    ({reason, message, count, first, last}); log_status: (phase, sub-phase) -> {count, first, last, reason} of the
    "Migration current status" lines of the operator log"""
    phase = str(status.get('phase') or '')
    sub_phase = str(status.get('subPhase') or '')
    latest_log = max(log_status.items(), key=lambda kv: kv[1]['last'] or datetime.min, default=None)
    if not phase and latest_log:
        phase, sub_phase = latest_log[0]
    if not phase:
        return None
    event_count = sum(e.get('count') or 1 for e in events)
    input_errors = sum(e.get('count') or 1 for e in events if e.get('reason') == 'InputError')
    if phase.upper() == 'COMPLETE' and not events:
        return None

    # time spent in this sub-phase: requeue lines of the operator log for it, else the Warning events
    seen = log_status.get((phase, sub_phase)) or {}
    firsts = [t for t in [seen.get('first')] + [e.get('first') for e in events] if t]
    lasts = [t for t in [seen.get('last')] + [e.get('last') for e in events] if t]
    first, last = min(firsts, default=None), max(lasts, default=None)
    duration = _duration(first, last)
    stuck_long = first and last and (last - first).total_seconds() >= STUCK_MINUTES * 60

    waits_for = (SUB_PHASES.get(sub_phase) or ("", []))[0]
    if phase.upper() == 'FAILURE':
        severity, verdict = 'critical', 'failed'
    elif phase.upper() == 'DUAL-WRITE' and not input_errors:
        severity, verdict = 'low', 'waiting for the finalize or rollback annotation (expected pause)'
    elif input_errors or event_count >= STUCK_EVENTS or stuck_long:
        severity, verdict = 'high', 'stuck'
    else:
        severity, verdict = 'medium', 'in progress'

    message = f"KRaftMigrationJob/{name} {verdict} in {phase}/{sub_phase or '?'}"
    if waits_for and verdict != 'waiting for the finalize or rollback annotation (expected pause)':
        message += f", waiting for {waits_for}"
    facts = []
    if duration:
        facts.append(f"for {duration} ({first:%Y-%m-%d %H:%M} to {last:%Y-%m-%d %H:%M})")
    if seen.get('count'):
        facts.append(f"{seen['count']} requeue(s) in the operator log")
    if input_errors:
        facts.append(f"{input_errors} InputError event(s)")
    elif event_count:
        facts.append(f"{event_count} Warning event(s)")
    if facts:
        message += ": " + ", ".join(facts)
    # the error the operator gives for this sub-phase: the most frequent Warning event, else the requeue reason
    top = max(events, key=lambda e: e.get('count') or 1, default=None)
    if top:
        message += f". Last error: {top.get('reason')}: {str(top.get('message'))[:400]}"
    elif seen.get('reason'):
        message += f". Operator: {seen['reason'][:400]}"
    return {
        'severity': severity,
        'message': message,
        'phase': phase,
        'sub_phase': sub_phase,
        'next_steps': steps_for(sub_phase),
        'docs': [DOCS, KNOWN_ISSUES, COMMANDS],
    }
