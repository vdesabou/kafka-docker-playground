#!/usr/bin/env python3
"""
Builds samples/cfk-support-bundle-rollout.tar.gz, the sample of `playground analyze logs --sample cfk_rollout`.

A synthetic bundle in the layout of `kubectl confluent support-bundle` that tells one story: an upgrade of CP 7.4.1 to
7.9.10 (and of the CFK operator) that is half done.

- the namespace ResourceQuota is full: the new ReplicaSet of the operator Deployment cannot create its pod (FailedCreate
  ... exceeded quota), the previous operator pod keeps running
- KRaftController still has platform.confluent.io/block-reconcile: its CR asks for 7.9.10, its StatefulSet and pods
  still run 7.4.1
- Kafka: the annotation was removed, the "Reconcile is blocked." condition stayed; its StatefulSet has 7.9.10, 2/3
  replicas updated, kafka-1 (7.9.10) is not Ready, kafka-0 still runs 7.4.1
- Connect was not upgraded yet (7.4.1 asked, 7.4.1 runs): nothing to report
- the operator log covers the last 2h45m while its pod has run for 3 days, and the last change of the Kafka CR is
  before the start of that log
- the events are in event.yaml and, as kubectl text, in event.txt

With --after, it builds samples/cfk-support-bundle-rollout-after.tar.gz (`--sample cfk_rollout_after`), the same cluster
the next day, to compare the two (`playground analyze logs --sample cfk_rollout --sample cfk_rollout_after`): the quota
was raised and the new operator pod runs, block-reconcile was removed from the KRaftController (which rolled to
7.9.10), the Kafka roll is complete; the stale "Reconcile is blocked." conditions are still there, Connect still runs
7.4.1, and connect-1 restarted twice while the brokers rolled.

The tarballs are deterministic (sorted entries, fixed mtimes, gzip without timestamp): regenerating them gives the same
bytes.

Usage: python3 make_rollout_bundle.py cfk-support-bundle-rollout.tar.gz
       python3 make_rollout_bundle.py --after cfk-support-bundle-rollout-after.tar.gz
"""

import gzip
import io
import sys
import tarfile

NS = "confluent"
OLD, NEW = "7.4.1", "7.9.10"
REG = "confluentinc"
INIT_OLD, INIT_NEW = f"{REG}/confluent-init-container:2.6.1", f"{REG}/confluent-init-container:3.3.0"
QUOTA = ("exceeded quota: confluent-quota, requested: limits.cpu=4,limits.memory=16Gi,requests.cpu=4,requests.memory=16Gi, "
         "used: limits.cpu=76,limits.memory=208Gi,requests.cpu=76,requests.memory=208Gi, "
         "limited: limits.cpu=76,limits.memory=216Gi,requests.cpu=76,requests.memory=216Gi")
BLOCKED_CONDITION = """  - lastProbeTime: "2026-10-15T18:02:11Z"
    lastTransitionTime: "2026-10-15T18:02:11Z"
    message: Reconcile is blocked.
    reason: ReconcileIsBlocked
    status: "True"
    type: platform.confluent.io/block-reconcile
"""

FILES = {}

FILES[f"{NS}/cluster-details.txt"] = f"""buildDate: "2026-08-12T10:01:22Z"
gitVersion: v1.31.4
major: "1"
minor: "31"
platform: linux/amd64

Operator Version: 0.1718.10

kafka:
 Application Image: {REG}/cp-server:{NEW}
 Init Image: {INIT_NEW}

kraftcontroller:
 Application Image: {REG}/cp-server:{NEW}
 Init Image: {INIT_NEW}

connect:
 Application Image: {REG}/cp-server-connect:{OLD}
 Init Image: {INIT_OLD}

CRD Name                                           || app-version          || chart-version
kafkas.platform.confluent.io                       || 3.3.0                || v0.1718.10
"""


def cr(kind, name, image, init, annotations="", conditions="", phase="RUNNING", managed=""):
    return f"""apiVersion: platform.confluent.io/v1beta1
kind: {kind}
metadata:
  name: {name}
  namespace: {NS}
{annotations}{managed}spec:
  replicas: 3
  image:
    application: {image}
    init: {init}
status:
  phase: {phase}
  conditions:
{conditions}  - lastProbeTime: "2026-10-16T09:40:00Z"
    lastTransitionTime: "2026-10-16T09:40:00Z"
    message: Configuration is updated.
    reason: ConfigurationIsUpdated
    status: "True"
    type: platform.confluent.io/config-revision-hash
"""


def statefulset(name, image, ready, updated, current, update):
    return f"""apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {name}
  namespace: {NS}
spec:
  replicas: 3
  serviceName: {name}
  selector: {{matchLabels: {{app: {name}}}}}
  template:
    spec:
      containers:
      - name: {name}
        image: {image}
status:
  replicas: 3
  readyReplicas: {ready}
  updatedReplicas: {updated}
  currentRevision: {current}
  updateRevision: {update}
"""


def pod(name, component, image, ready, started, restarts=0):
    return f"""- apiVersion: v1
  kind: Pod
  metadata:
    name: {name}
    namespace: {NS}
    labels: {{app: {component}, platform.confluent.io/type: {component}}}
  spec:
    containers:
    - name: {component}
      image: {image}
  status:
    phase: Running
    startTime: "{started}"
    containerStatuses:
    - name: {component}
      image: {image}
      ready: {str(ready).lower()}
      restartCount: {restarts}
      state: {{running: {{startedAt: "{started}"}}}}
"""


FILES[f"{NS}/cluster-resources/kraftcontroller/kraftcontroller.yaml"] = cr(
    "KRaftController", "kraftcontroller", f"{REG}/cp-server:{NEW}", INIT_NEW,
    annotations="  annotations:\n    platform.confluent.io/block-reconcile: \"true\"\n", conditions=BLOCKED_CONDITION)
FILES[f"{NS}/cluster-resources/kraftcontroller/statefulset.yaml"] = statefulset(
    "kraftcontroller", f"{REG}/cp-server:{OLD}", 3, 3, "kraftcontroller-7c9d", "kraftcontroller-7c9d")

FILES[f"{NS}/cluster-resources/kafka/kafka.yaml"] = cr(
    "Kafka", "kafka", f"{REG}/cp-server:{NEW}", INIT_NEW, conditions=BLOCKED_CONDITION,
    managed="""  managedFields:
  - manager: kubectl-client-side-apply
    operation: Update
    time: "2026-10-16T05:31:12Z"
    fieldsV1:
      f:spec:
        f:image: {}
""")
FILES[f"{NS}/cluster-resources/kafka/statefulset.yaml"] = statefulset(
    "kafka", f"{REG}/cp-server:{NEW}", 2, 2, "kafka-d8d5865d5", "kafka-5ccfbb6954")

FILES[f"{NS}/cluster-resources/connect/connect.yaml"] = cr(
    "Connect", "connect", f"{REG}/cp-server-connect:{OLD}", INIT_OLD, conditions=BLOCKED_CONDITION)
FILES[f"{NS}/cluster-resources/connect/statefulset.yaml"] = statefulset(
    "connect", f"{REG}/cp-server-connect:{OLD}", 2, 2, "connect-5f6b", "connect-5f6b").replace("replicas: 3", "replicas: 2")

FILES[f"{NS}/cluster-resources/pods.yaml"] = "apiVersion: v1\nkind: List\nitems:\n" + "".join([
    pod("kraftcontroller-0", "kraftcontroller", f"{REG}/cp-server:{OLD}", True, "2026-10-13T16:05:00Z"),
    pod("kraftcontroller-1", "kraftcontroller", f"{REG}/cp-server:{OLD}", True, "2026-10-13T16:06:00Z"),
    pod("kraftcontroller-2", "kraftcontroller", f"{REG}/cp-server:{OLD}", True, "2026-10-13T16:07:00Z"),
    pod("kafka-0", "kafka", f"{REG}/cp-server:{OLD}", True, "2026-10-13T16:10:00Z"),
    pod("kafka-1", "kafka", f"{REG}/cp-server:{NEW}", False, "2026-10-16T05:40:00Z", restarts=1),
    pod("kafka-2", "kafka", f"{REG}/cp-server:{NEW}", True, "2026-10-16T05:35:00Z"),
    pod("connect-0", "connect", f"{REG}/cp-server-connect:{OLD}", True, "2026-10-13T16:20:00Z"),
    pod("connect-1", "connect", f"{REG}/cp-server-connect:{OLD}", True, "2026-10-13T16:21:00Z"),
    pod("confluent-operator-6b7f54d485-gs6hj", "confluent-operator", f"{REG}/confluent-operator:0.1514.13", True,
        "2026-10-13T16:00:00Z"),
])

EVENTS = [
    ("FailedCreate", "ReplicaSet", "confluent-operator-78f46f99dc",
     f'Error creating: pods "confluent-operator-78f46f99dc-h45zb" is forbidden: {QUOTA}', 930,
     "2026-10-16T05:30:40Z", "2026-10-16T09:44:40Z"),
    ("Unhealthy", "Pod", "kafka-1", "Readiness probe failed: dial tcp 10.128.4.17:9071: connect: connection refused", 251,
     "2026-10-16T05:41:10Z", "2026-10-16T09:44:50Z"),
]
_EVENTS_YAML = "apiVersion: v1\nkind: List\nitems:\n" + "".join(
    f"""- apiVersion: v1
  kind: Event
  type: Warning
  reason: {reason}
  message: '{message}'
  count: {count}
  involvedObject: {{kind: {kind}, name: {name}, namespace: {NS}}}
  firstTimestamp: "{first}"
  lastTimestamp: "{last}"
""" for reason, kind, name, message, count, first, last in EVENTS)
_EVENTS_TXT = "LAST SEEN   TYPE      REASON         OBJECT                                     MESSAGE\n" + "".join(
    f"{age:<11} Warning   {reason:<14} {kind}/{name:<35} {message}\n"
    for age, (reason, kind, name, message, _, _, _) in zip(("20s", "10s"), EVENTS))

FILES[f"{NS}/event.yaml"] = _EVENTS_YAML
FILES[f"{NS}/event.txt"] = _EVENTS_TXT

FILES[f"{NS}/cluster-resources/kafka/logs/kafka-1.log"] = f"""[2026-10-16 05:40:12,004] INFO Kafka version: {NEW}-ce (org.apache.kafka.common.utils.AppInfoParser)
[2026-10-16 05:40:31,551] WARN [RaftManager id=1] Connection to node 9991 (kraftcontroller-0.kraftcontroller.{NS}.svc.cluster.local/10.128.2.11:9074) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-10-16 09:44:48,120] ERROR [BrokerLifecycleManager id=1] Shutting down because we were unable to register with the controller quorum. (kafka.server.BrokerLifecycleManager)
"""

FILES["operator/confluent-operator-6b7f54d485-gs6hj.log"] = "".join(
    f'{{"level":"INFO","time":"2026-10-16T{h}:{m}:00.000Z","name":"kafka","caller":"roll/roll_handler.go:119",'
    f'"msg":"cluster not rollable from roll pre checks","namespace":"{NS}"}}\n'
    f'{{"level":"INFO","time":"2026-10-16T{h}:{m}:01.000Z","name":"kraftcontroller","caller":"log/log.go:49",'
    f'"msg":"reconcile is blocked","name":"kraftcontroller","namespace":"{NS}",'
    f'"annotation":"platform.confluent.io/block-reconcile"}}\n'
    for h in ("07", "08", "09") for m in ("00", "15", "30", "45"))


def events_files(events):
    return {
        f"{NS}/event.yaml": "apiVersion: v1\nkind: List\nitems:\n" + "".join(
            f"""- apiVersion: v1
  kind: Event
  type: Warning
  reason: {reason}
  message: '{message}'
  count: {count}
  involvedObject: {{kind: {kind}, name: {name}, namespace: {NS}}}
  firstTimestamp: "{first}"
  lastTimestamp: "{last}"
""" for reason, kind, name, message, count, first, last in events),
        f"{NS}/event.txt": "LAST SEEN   TYPE      REASON         OBJECT                                     MESSAGE\n" + "".join(
            f"{age:<11} Warning   {reason:<14} {kind}/{name:<35} {message}\n"
            for age, (reason, kind, name, message, _, _, _) in zip(("20s", "10s", "5s"), events)),
    }


def after_files():
    """The same cluster the next day (see the docstring)"""
    files = dict(FILES)
    del files["operator/confluent-operator-6b7f54d485-gs6hj.log"]
    files[f"{NS}/cluster-resources/kraftcontroller/kraftcontroller.yaml"] = cr(
        "KRaftController", "kraftcontroller", f"{REG}/cp-server:{NEW}", INIT_NEW, conditions=BLOCKED_CONDITION,
        managed="""  managedFields:
  - manager: kubectl-annotate
    operation: Update
    time: "2026-10-16T14:02:30Z"
    fieldsV1:
      f:metadata:
        f:annotations: {}
""")
    files[f"{NS}/cluster-resources/kraftcontroller/statefulset.yaml"] = statefulset(
        "kraftcontroller", f"{REG}/cp-server:{NEW}", 3, 3, "kraftcontroller-8e1f", "kraftcontroller-8e1f")
    files[f"{NS}/cluster-resources/kafka/statefulset.yaml"] = statefulset(
        "kafka", f"{REG}/cp-server:{NEW}", 3, 3, "kafka-5ccfbb6954", "kafka-5ccfbb6954")
    files[f"{NS}/cluster-resources/pods.yaml"] = "apiVersion: v1\nkind: List\nitems:\n" + "".join([
        pod("kraftcontroller-0", "kraftcontroller", f"{REG}/cp-server:{NEW}", True, "2026-10-16T14:12:00Z"),
        pod("kraftcontroller-1", "kraftcontroller", f"{REG}/cp-server:{NEW}", True, "2026-10-16T14:09:00Z"),
        pod("kraftcontroller-2", "kraftcontroller", f"{REG}/cp-server:{NEW}", True, "2026-10-16T14:06:00Z"),
        pod("kafka-0", "kafka", f"{REG}/cp-server:{NEW}", True, "2026-10-16T14:31:00Z"),
        pod("kafka-1", "kafka", f"{REG}/cp-server:{NEW}", True, "2026-10-16T14:20:00Z", restarts=1),
        pod("kafka-2", "kafka", f"{REG}/cp-server:{NEW}", True, "2026-10-16T05:35:00Z"),
        pod("connect-0", "connect", f"{REG}/cp-server-connect:{OLD}", True, "2026-10-13T16:20:00Z"),
        pod("connect-1", "connect", f"{REG}/cp-server-connect:{OLD}", True, "2026-10-16T14:40:00Z", restarts=2),
        pod("confluent-operator-78f46f99dc-k2lpq", "confluent-operator", f"{REG}/confluent-operator:0.1718.10", True,
            "2026-10-16T13:55:00Z"),
    ])
    files.update(events_files([
        ("BackOff", "Pod", "connect-1", "Back-off restarting failed container connect in pod connect-1", 4,
         "2026-10-16T14:33:00Z", "2026-10-16T14:39:00Z"),
    ]))
    files[f"{NS}/cluster-resources/kafka/logs/kafka-1.log"] = f"""[2026-10-16 14:20:12,004] INFO Kafka version: {NEW}-ce (org.apache.kafka.common.utils.AppInfoParser)
[2026-10-16 14:21:02,551] INFO [BrokerServer id=1] Transition from STARTING to STARTED (kafka.server.BrokerServer)
[2026-10-17 09:44:48,120] INFO [GroupCoordinator 1]: Preparing to rebalance group connect-cluster (kafka.coordinator.group.GroupCoordinator)
"""
    files["operator/confluent-operator-78f46f99dc-k2lpq.log"] = "".join(
        f'{{"level":"INFO","time":"2026-10-17T{h}:{m}:00.000Z","name":"kafka","caller":"roll/roll_handler.go:88",'
        f'"msg":"cluster is healthy","namespace":"{NS}"}}\n'
        for h in ("07", "08", "09") for m in ("00", "15", "30", "45"))
    return files


def main(out_path: str, after: bool = False) -> int:
    files = after_files() if after else FILES
    folder = "cfk-support-bundle-rollout-after" if after else "cfk-support-bundle-rollout"
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for name in sorted(files):
            data = files[name].encode("utf-8")
            info = tarfile.TarInfo(f"{folder}/{name}")
            info.size, info.mtime, info.mode, info.uid, info.gid, info.uname, info.gname = len(data), 1791964800, 0o644, 0, 0, "", ""
            tar.addfile(info, io.BytesIO(data))
    with open(out_path, "wb") as f:
        with gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0, compresslevel=9) as gz:
            gz.write(buf.getvalue())
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    after = "--after" in args
    args = [a for a in args if a != "--after"]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    sys.exit(main(args[0], after))
