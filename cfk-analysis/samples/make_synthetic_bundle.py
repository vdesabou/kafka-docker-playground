#!/usr/bin/env python3
"""
Builds samples/cfk-support-bundle-synthetic.tar.gz, the sample of `playground analyze cfk-bundle --sample synthetic`.

A synthetic bundle in the layout of `kubectl confluent support-bundle` (namespace / cluster-resources, component
folders with their CR and logs, operator logs) that tells one story:

- kafka-2 crash-loops: its TLS certificate expired (SSLHandshakeException in its log, BackOff events), and its
  PersistentVolumeClaim is still pending (FailedScheduling)
- connect-0 was OOMKilled and restarted 6 times; the connector `orders-sink` has a FAILED task
- the configuration: kafka.properties, schemaregistry.properties and connect.properties of the <cr>-shared-config
  ConfigMaps, the configOverrides of the Connect CR, the configs of the Connector CR, and the config dumps of the
  logs (KafkaConfig, SchemaRegistryConfig, DistributedConfig, connector configs)
- schemaregistry-0 cannot authenticate to Kafka (SaslAuthenticationException)
- the operator logs reconcile errors for the Kafka CR, which stays PROVISIONING with 2/3 ready replicas
- cluster-details.txt (Kubernetes / CFK versions, images) and a `kubectl edit` of the Kafka CR the evening before,
  for the Environment and Recent changes sections (supported versions: no Compatibility issue)

The tarball is deterministic (sorted entries, fixed mtimes, gzip without timestamp): regenerating it gives the same bytes.

    python3 -I cfk-analysis/samples/make_synthetic_bundle.py cfk-analysis/samples/cfk-support-bundle-synthetic.tar.gz
"""

import gzip
import io
import sys
import tarfile

NS = "confluent"
T0 = "2026-10-14T08:00:00Z"

FILES = {}

FILES[f"{NS}/cluster-resources/events.yaml"] = f"""apiVersion: v1
kind: List
items:
- apiVersion: v1
  kind: Event
  type: Warning
  reason: BackOff
  message: Back-off restarting failed container kafka in pod kafka-2_{NS}
  count: 42
  involvedObject: {{kind: Pod, name: kafka-2, namespace: {NS}}}
  firstTimestamp: "{T0}"
  lastTimestamp: "2026-10-14T09:12:31Z"
- apiVersion: v1
  kind: Event
  type: Warning
  reason: FailedScheduling
  message: '0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims. preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling. PersistentVolumeClaim data0-kafka-2 pending'
  count: 7
  involvedObject: {{kind: Pod, name: kafka-2, namespace: {NS}}}
  firstTimestamp: "{T0}"
  lastTimestamp: "2026-10-14T08:20:02Z"
- apiVersion: v1
  kind: Event
  type: Warning
  reason: Unhealthy
  message: 'Readiness probe failed: HTTP probe failed with statuscode: 503'
  count: 18
  involvedObject: {{kind: Pod, name: schemaregistry-0, namespace: {NS}}}
  firstTimestamp: "{T0}"
  lastTimestamp: "2026-10-14T09:10:44Z"
- apiVersion: v1
  kind: Event
  type: Normal
  reason: Pulled
  message: Container image "confluentinc/cp-server:8.1.0" already present on machine
  count: 3
  involvedObject: {{kind: Pod, name: kafka-0, namespace: {NS}}}
  firstTimestamp: "{T0}"
  lastTimestamp: "{T0}"
"""


def pod(name, component, ready, restarts, waiting=None, last_terminated=None, image="confluentinc/cp-server:8.1.0"):
    state = (f"        waiting: {{reason: {waiting}, message: back-off 5m0s restarting failed container}}\n" if waiting
             else f"        running: {{startedAt: \"{T0}\"}}\n")
    last = (f"      lastState:\n        terminated: {{reason: {last_terminated[0]}, exitCode: {last_terminated[1]}, "
            f"finishedAt: \"2026-10-14T09:05:00Z\"}}\n" if last_terminated else "")
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
    containerStatuses:
    - name: {component}
      image: {image}
      ready: {str(ready).lower()}
      restartCount: {restarts}
      state:
{state}{last}"""


FILES[f"{NS}/cluster-resources/pods.yaml"] = "apiVersion: v1\nkind: List\nitems:\n" + "".join([
    pod("kafka-0", "kafka", True, 0),
    pod("kafka-1", "kafka", True, 0),
    pod("kafka-2", "kafka", False, 42, waiting="CrashLoopBackOff", last_terminated=("Error", 1)),
    pod("connect-0", "connect", True, 6, last_terminated=("OOMKilled", 137), image="confluentinc/cp-server-connect:8.1.0"),
    pod("schemaregistry-0", "schemaregistry", False, 0, image="confluentinc/cp-schema-registry:8.1.0"),
])

FILES[f"{NS}/cluster-details.txt"] = """buildDate: "2026-08-12T10:01:22Z"
gitVersion: v1.33.4
major: "1"
minor: "33"
platform: linux/amd64

Operator Version: 0.1351.24

kafka:
 Application Image: confluentinc/cp-server:8.1.0
 Init Image: confluentinc/confluent-init-container:3.1.0

connect:
 Application Image: confluentinc/cp-server-connect:8.1.0
 Init Image: confluentinc/confluent-init-container:3.1.0

schemaregistry:
 Application Image: confluentinc/cp-schema-registry:8.1.0
 Init Image: confluentinc/confluent-init-container:3.1.0

CRD Name                                           || app-version          || chart-version
kafkas.platform.confluent.io                       || 3.1.0                || v0.1351.24
"""

FILES[f"{NS}/kafka/kafka.yaml"] = f"""apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: {NS}
  managedFields:
  - manager: kubectl-edit
    operation: Update
    apiVersion: platform.confluent.io/v1beta1
    time: "2026-10-13T18:42:10Z"
    fieldsType: FieldsV1
    fieldsV1: {{f:spec: {{f:tls: {{}}, f:podTemplate: {{}}}}}}
  - manager: manager
    operation: Update
    apiVersion: platform.confluent.io/v1beta1
    subresource: status
    time: "2026-10-14T08:01:00Z"
    fieldsType: FieldsV1
    fieldsV1: {{f:status: {{}}}}
spec:
  replicas: 3
  image: {{application: confluentinc/cp-server:8.1.0, init: confluentinc/confluent-init-container:3.1.0}}
  tls: {{secretRef: kafka-tls}}
status:
  phase: PROVISIONING
  replicas: 3
  readyReplicas: 2
  conditions:
  - type: platform.confluent.io/statefulset-ready
    status: "False"
    reason: StatefulSetNotReady
    message: 'statefulset kafka: 2/3 replicas ready'
    lastTransitionTime: "2026-10-14T08:01:00Z"
  - type: platform.confluent.io/garbage-collecting
    status: "False"
    reason: Garbage Collection not triggered
    message: Cluster is not being garbage collected
    lastTransitionTime: "2026-10-01T08:00:00Z"
"""

FILES[f"{NS}/connect/connect.yaml"] = f"""apiVersion: platform.confluent.io/v1beta1
kind: Connect
metadata:
  name: connect
  namespace: {NS}
spec:
  replicas: 1
  configOverrides:
    server:
      - consumer.max.poll.records=2000
    jvm:
      - -Xmx1536m
  podTemplate:
    resources: {{limits: {{memory: 2Gi}}, requests: {{memory: 2Gi}}}}
status:
  phase: RUNNING
  replicas: 1
  readyReplicas: 1
"""

FILES[f"{NS}/connect/connector-orders-sink.yaml"] = f"""apiVersion: platform.confluent.io/v1beta1
kind: Connector
metadata:
  name: orders-sink
  namespace: {NS}
spec:
  class: io.confluent.connect.jdbc.JdbcSinkConnector
  taskMax: 2
  connectClusterRef:
    name: connect
  configs:
    topics: orders
    connection.url: jdbc:postgresql://postgres.{NS}.svc.cluster.local:5432/shop
    connection.user: connect
    connection.password: s3cr3t-in-clear
    insert.mode: insert
    auto.create: "false"
    batch.size: "3000"
status:
  state: CREATED
  connectorState: RUNNING
  tasksReady: 1/2
  failedTasks:
    "1":
      id: 1
      state: FAILED
      workerId: connect-0.connect.{NS}.svc.cluster.local:8083
      trace: 'org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.'
"""

FILES[f"{NS}/connect/cm/configmaps.yaml"] = f"""apiVersion: v1
kind: List
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: connect-shared-config
    namespace: {NS}
    annotations:
      platform.confluent.io/cr-name: connect
      platform.confluent.io/type: connect
  data:
    connect.properties: |
      bootstrap.servers=kafka.{NS}.svc.cluster.local:9071
      config.storage.topic={NS}.connect-configs
      consumer.max.poll.records=2000
      group.id={NS}.connect
      key.converter=org.apache.kafka.connect.storage.StringConverter
      listeners=http://0.0.0.0:8083
      offset.storage.topic={NS}.connect-offsets
      plugin.path=/usr/share/java,/usr/share/confluent-hub-components,/mnt/plugins
      ssl.truststore.location=/mnt/sslcerts/truststore.p12
      ssl.truststore.password=mystorepassword
      status.storage.topic={NS}.connect-status
      value.converter=io.confluent.connect.avro.AvroConverter
      value.converter.schema.registry.url=http://schemaregistry.{NS}.svc.cluster.local:8081
    jvm.config: |
      -Xmx1536m
      -XX:+UseG1GC
"""

FILES[f"{NS}/kafka/cm/configmaps.yaml"] = f"""apiVersion: v1
kind: List
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: kafka-shared-config
    namespace: {NS}
    annotations:
      platform.confluent.io/cr-name: kafka
      platform.confluent.io/type: kafka
  data:
    kafka.properties: |
      advertised.listeners=INTERNAL://${{POD_NAME}}.kafka.{NS}.svc.cluster.local:9071
      default.replication.factor=3
      listener.security.protocol.map=INTERNAL:SSL,CONTROLLER:SSL
      listeners=INTERNAL://:9071
      log.dirs=/mnt/data/data0/logs
      min.insync.replicas=2
      ssl.keystore.location=/mnt/sslcerts/keystore.p12
      ssl.keystore.password=mykeystorepassword
    jvm.config: |
      -Xmx4g
"""

FILES[f"{NS}/schemaregistry/cm/configmaps.yaml"] = f"""apiVersion: v1
kind: List
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: schemaregistry-shared-config
    namespace: {NS}
    annotations:
      platform.confluent.io/cr-name: schemaregistry
      platform.confluent.io/type: schemaregistry
  data:
    schemaregistry.properties: |
      kafkastore.bootstrap.servers=SASL_SSL://kafka.{NS}.svc.cluster.local:9071
      kafkastore.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="sr" password="sr-secret";
      kafkastore.sasl.mechanism=PLAIN
      kafkastore.security.protocol=SASL_SSL
      kafkastore.topic=_schemas_schemaregistry_{NS}
      listeners=http://0.0.0.0:8081
      schema.registry.group.id=id_schemaregistry_{NS}
"""

FILES[f"{NS}/kafka/logs/kafka-2.log"] = """[2026-10-14 09:12:20,114] INFO Starting the controller-mode broker (kafka.server.KafkaRaftServer)
[2026-10-14 09:12:20,530] INFO KafkaConfig values: 
	advertised.listeners = INTERNAL://kafka-2.kafka.confluent.svc.cluster.local:9071
	default.replication.factor = 3
	log.retention.hours = 168
	min.insync.replicas = 2
	node.id = 2
	ssl.keystore.password = [hidden]
	unclean.leader.election.enable = false (kafka.server.KafkaConfig)
[2026-10-14 09:12:24,902] ERROR [Controller id=2] Failed to connect to the quorum, retrying (org.apache.kafka.raft.KafkaRaftClient)
javax.net.ssl.SSLHandshakeException: PKIX path validation failed: java.security.cert.CertPathValidatorException: validity check failed
	at java.base/sun.security.ssl.Alert.createSSLException(Alert.java:130)
	at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:378)
Caused by: java.security.cert.CertificateExpiredException: NotAfter: Mon Oct 13 23:59:59 UTC 2026
	at java.base/sun.security.x509.CertificateValidity.valid(CertificateValidity.java:277)
[2026-10-14 09:12:29,903] ERROR [Controller id=2] Failed to connect to the quorum, retrying (org.apache.kafka.raft.KafkaRaftClient)
javax.net.ssl.SSLHandshakeException: PKIX path validation failed: java.security.cert.CertPathValidatorException: validity check failed
Caused by: java.security.cert.CertificateExpiredException: NotAfter: Mon Oct 13 23:59:59 UTC 2026
[2026-10-14 09:12:31,010] FATAL [KafkaRaftServer nodeId=2] Fatal error during broker startup. Prepare to shutdown (kafka.server.BrokerServer)
org.apache.kafka.common.errors.SslAuthenticationException: SSL handshake failed
"""

FILES[f"{NS}/connect/logs/connect-0.log"] = """[2026-10-14 09:00:30,118] INFO DistributedConfig values: 
	bootstrap.servers = [kafka.confluent.svc.cluster.local:9071]
	config.storage.topic = confluent.connect-configs
	connector.client.config.override.policy = All
	group.id = confluent.connect
	offset.flush.interval.ms = 10000
	scheduled.rebalance.max.delay.ms = 300000
	ssl.truststore.password = [hidden]
	task.shutdown.graceful.timeout.ms = 10000 (org.apache.kafka.common.config.AbstractConfig)
[2026-10-14 09:01:10,250] INFO [orders-sink|worker] SinkConnectorConfig values: 
	config.action.reload = restart
	connector.class = io.confluent.connect.jdbc.JdbcSinkConnector
	errors.tolerance = none
	key.converter = null
	name = orders-sink
	tasks.max = 2
	topics = [orders]
	value.converter = null (org.apache.kafka.common.config.AbstractConfig)
[2026-10-14 09:01:11,980] INFO [orders-sink|task-1] JdbcSinkConfig values: 
	auto.create = false
	batch.size = 3000
	connection.password = [hidden]
	connection.url = jdbc:postgresql://postgres.confluent.svc.cluster.local:5432/shop
	connection.user = connect
	insert.mode = insert
	max.retries = 10 (org.apache.kafka.common.config.AbstractConfig)
[2026-10-14 09:01:12,400] INFO [orders-sink|task-1] Attempting to open connection #1 to PostgreSql (io.confluent.connect.jdbc.util.CachedConnectionProvider)
[2026-10-14 09:04:58,771] ERROR [orders-sink|task-1] WorkerSinkTask{id=orders-sink-1} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:632)
Caused by: java.sql.SQLException: Exception chain:
java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "orders" ("id","amount") VALUES (1042,NULL) was aborted: ERROR: null value in column "amount" violates not-null constraint
[2026-10-14 09:04:59,002] ERROR [orders-sink|task-1] java.lang.OutOfMemoryError: Java heap space (org.apache.kafka.connect.runtime.WorkerTask)
java.lang.OutOfMemoryError: Java heap space
	at java.base/java.util.Arrays.copyOf(Arrays.java:3537)
"""

FILES[f"{NS}/schemaregistry/logs/schemaregistry-0.log"] = """[2026-10-14 09:10:40,551] INFO Starting Schema Registry (io.confluent.kafka.schemaregistry.rest.SchemaRegistryMain)
[2026-10-14 09:10:41,020] INFO SchemaRegistryConfig values: 
	kafkastore.bootstrap.servers = [SASL_SSL://kafka.confluent.svc.cluster.local:9071]
	kafkastore.sasl.jaas.config = [hidden]
	kafkastore.sasl.mechanism = PLAIN
	kafkastore.timeout.ms = 500
	leader.eligibility = true
	mode.mutability = true (io.confluent.kafka.schemaregistry.rest.SchemaRegistryConfig)
[2026-10-14 09:10:44,113] ERROR Error starting the schema registry (io.confluent.kafka.schemaregistry.rest.SchemaRegistryRestApplication)
io.confluent.kafka.schemaregistry.exceptions.SchemaRegistryInitializationException: Error initializing kafka store while initializing schema registry
Caused by: org.apache.kafka.common.errors.SaslAuthenticationException: Authentication failed during authentication due to invalid credentials with SASL mechanism PLAIN
"""

FILES["operator/confluent-operator-7d9c8b6f5-x2x7k.log"] = """{"level":"info","ts":"2026-10-14T09:00:01Z","logger":"kafka","msg":"reconciling","name":"kafka","namespace":"confluent"}
{"level":"error","ts":"2026-10-14T09:00:03Z","logger":"kafka","msg":"Reconciler error","name":"kafka","namespace":"confluent","error":"failed to reconcile statefulset kafka: 2/3 replicas ready, pod kafka-2 in CrashLoopBackOff"}
{"level":"error","ts":"2026-10-14T09:05:03Z","logger":"kafka","msg":"Reconciler error","name":"kafka","namespace":"confluent","error":"failed to reconcile statefulset kafka: 2/3 replicas ready, pod kafka-2 in CrashLoopBackOff"}
"""


def main(out_path: str) -> int:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for name in sorted(FILES):
            data = FILES[name].encode("utf-8")
            info = tarfile.TarInfo(f"cfk-support-bundle/{name}")
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
