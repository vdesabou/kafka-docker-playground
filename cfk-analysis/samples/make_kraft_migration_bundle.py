#!/usr/bin/env python3
"""
Builds samples/cfk-support-bundle-kraft-migration.tar.gz, the sample of
`playground analyze logs --sample cfk_kraft_migration`.

A synthetic bundle in the layout of `kubectl confluent support-bundle` that tells one story: the ZooKeeper to KRaft
migration of a CP 7.9 cluster (CFK 3.3.0) is stuck in SETUP/SubPhaseSetupKRaftControllerHealthy for 3 days. The
KRaftController has no replication listener of its own, so it borrows the internal listener of Kafka, whose secret
has no inter-broker credentials: the operator refuses to render it (InputError events on the KRaftMigrationJob,
"Migration current status … requeuing" in the operator log) and no KRaftController pod is ever created. Kafka and
ZooKeeper are healthy.

The tarball is deterministic (sorted entries, fixed mtimes, gzip without timestamp): regenerating it gives the same bytes.

Usage: python3 make_kraft_migration_bundle.py cfk-support-bundle-kraft-migration.tar.gz
"""

import gzip
import io
import sys
import tarfile

NS = "datastreaming"
IMAGE = "confluentinc/cp-server:7.9.2"
INIT = "confluentinc/confluent-init-container:3.3.0"

FILES = {}

FILES[f"{NS}/cluster-details.txt"] = f"""buildDate: "2026-08-12T10:01:22Z"
gitVersion: v1.31.4
major: "1"
minor: "31"
platform: linux/amd64

Operator Version: 0.1718.10

kafka:
 Application Image: {IMAGE}
 Init Image: {INIT}

zookeeper:
 Application Image: confluentinc/cp-zookeeper:7.9.2
 Init Image: {INIT}

kraftcontroller:
 Application Image: {IMAGE}
 Init Image: {INIT}

CRD Name                                           || app-version          || chart-version
kafkas.platform.confluent.io                       || 3.3.0                || v0.1718.10
"""

FILES[f"{NS}/kraftmigrationjob/kraftmigrationjob.yaml"] = f"""apiVersion: platform.confluent.io/v1beta1
kind: KRaftMigrationJob
metadata:
  name: kraftmigrationjob
  namespace: {NS}
spec:
  dependencies:
    kafka: {{name: kafka, namespace: {NS}}}
    zookeeper: {{name: zookeeper, namespace: {NS}}}
    kRaftController: {{name: kraftcontroller, namespace: {NS}}}
status:
  phase: SETUP
  subPhase: SubPhaseSetupKRaftControllerHealthy
  ibpVersion: "3.9"
  kafkaClusterId: hJ7mXx2gTQe0aBcDeFgHiQ
"""

FILES[f"{NS}/kraftcontroller/kraftcontroller.yaml"] = f"""apiVersion: platform.confluent.io/v1beta1
kind: KRaftController
metadata:
  name: kraftcontroller
  namespace: {NS}
  annotations:
    platform.confluent.io/kraft-migration-hold-krc-creation: "false"
spec:
  replicas: 3
  clusterID: hJ7mXx2gTQe0aBcDeFgHiQ
  image: {{application: "{IMAGE}", init: "{INIT}"}}
  dataVolumeCapacity: 10Gi
  dependencies:
    migration:
      zookeeper: {{endpoint: "zookeeper.{NS}.svc.cluster.local:2181/kafka"}}
status:
  phase: PROVISIONING
"""

FILES[f"{NS}/kafka/kafka.yaml"] = f"""apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: {NS}
spec:
  replicas: 3
  image: {{application: "{IMAGE}", init: "{INIT}"}}
  dataVolumeCapacity: 100Gi
  listeners:
    internal:
      authentication: {{type: plain, jaasConfig: {{secretRef: confluent-plain-users-json}}}}
status:
  phase: RUNNING
  replicas: 3
  readyReplicas: 3
"""

FILES[f"{NS}/zookeeper/zookeeper.yaml"] = f"""apiVersion: platform.confluent.io/v1beta1
kind: Zookeeper
metadata:
  name: zookeeper
  namespace: {NS}
spec:
  replicas: 3
  image: {{application: "confluentinc/cp-zookeeper:7.9.2", init: "{INIT}"}}
status:
  phase: RUNNING
  replicas: 3
  readyReplicas: 3
"""

FILES[f"{NS}/cluster-resources/events.yaml"] = f"""apiVersion: v1
kind: List
items:
- apiVersion: v1
  kind: Event
  type: Warning
  reason: InputError
  message: 'kraftcontroller [kraftcontroller]: missing inter replication credentials in secret confluent-plain-users-json of the internal listener'
  count: 7851
  involvedObject: {{kind: KRaftMigrationJob, name: kraftmigrationjob, namespace: {NS}}}
  firstTimestamp: "2026-10-13T16:16:02Z"
  lastTimestamp: "2026-10-16T09:20:41Z"
"""

FILES["operator/confluent-operator-6b7f54d485-gs6hj.log"] = "".join(
    f'{{"level":"INFO","time":"2026-10-16T{h}:{m}:00.000Z","name":"kraftmigrationjob","caller":"log/log.go:49",'
    f'"msg":"Migration current status SETUP/SubPhaseSetupKRaftControllerHealthy: kraftcontroller [kraftcontroller] in '
    f'namespace [{NS}] not created yet, requeuing ...","name":"kraftmigrationjob","namespace":"{NS}"}}\n'
    f'{{"level":"ERROR","time":"2026-10-16T{h}:{m}:00.100Z","name":"kraftcontroller","caller":"log/log.go:53",'
    f'"msg":"apply failed","name":"kraftcontroller","namespace":"{NS}","error":"missing inter replication credentials '
    f'in secret confluent-plain-users-json of the internal listener"}}\n'
    for h in ("07", "08", "09") for m in ("00", "15", "30", "45"))


def main(out_path: str) -> int:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for name in sorted(FILES):
            data = FILES[name].encode("utf-8")
            info = tarfile.TarInfo(f"cfk-support-bundle-kraft-migration/{name}")
            info.size, info.mtime, info.mode, info.uid, info.gid, info.uname, info.gname = len(data), 1791964800, 0o644, 0, 0, "", ""
            tar.addfile(info, io.BytesIO(data))
    with open(out_path, "wb") as f:
        with gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0, compresslevel=9) as gz:
            gz.write(buf.getvalue())
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    sys.exit(main(sys.argv[1]))
