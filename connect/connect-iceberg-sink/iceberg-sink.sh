#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground topic create -t control-iceberg 

log "Sending messages to topic payments"
playground topic produce -t payments --nb-messages $(wc -l <"../../connect/connect-iceberg-sink/data/transactions.json") --value ../../connect/connect-iceberg-sink/data/transactions.json

log "Creating Iceberg sink connector"
playground connector create-or-update --connector iceberg-sink  << EOF
{
  "tasks.max": "1",
  "topics": "payments",
  "connector.class": "org.apache.iceberg.connect.IcebergSinkConnector",
  "iceberg.catalog.s3.endpoint": "http://minio:9000",
  "iceberg.catalog.s3.secret-access-key": "minioadmin",
  "iceberg.catalog.s3.access-key-id": "minioadmin",
  "iceberg.catalog.s3.path-style-access": "true",
  "iceberg.catalog.uri": "http://rest:8181",
  "iceberg.catalog.warehouse": "s3://warehouse/",
  "iceberg.catalog.client.region": "eu-west-1",
  "iceberg.catalog.type": "rest",
  "iceberg.control.commit.interval-ms": "1000",
  "iceberg.tables.auto-create-enabled": "true",
  "iceberg.tables": "orders.payments",
  "value.converter.schemas.enable": "false",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "schemas.enable": "false"
}
EOF

# https://github.com/apache/iceberg/issues/12507

# [2025-08-13 13:08:47,143] ERROR [iceberg-sink|worker] Failed to start connector iceberg-sink (org.apache.kafka.connect.runtime.Worker:425)
# java.lang.NoClassDefFoundError: org/apache/iceberg/IcebergBuild
# 	at org.apache.iceberg.connect.IcebergSinkConfig.version(IcebergSinkConfig.java:109) ~[iceberg-kafka-connect-1.9.1.jar:?]
# 	at org.apache.iceberg.connect.IcebergSinkConnector.version(IcebergSinkConnector.java:37) ~[iceberg-kafka-connect-1.9.1.jar:?]
# 	at org.apache.kafka.connect.runtime.WorkerConnector$ConnectorMetricsGroup.<init>(WorkerConnector.java:502) ~[connect_runtime_runtime-project.jar:?]
# 	at org.apache.kafka.connect.runtime.WorkerConnector.<init>(WorkerConnector.java:103) ~[connect_runtime_runtime-project.jar:?]
# 	at org.apache.kafka.connect.runtime.Worker.startConnector(Worker.java:411) ~[connect_runtime_runtime-project.jar:?]
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.startConnector(DistributedHerder.java:2172) ~[connect_runtime_runtime-project.jar:?]
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.lambda$getConnectorStartingCallable$46(DistributedHerder.java:2178) ~[connect_runtime_runtime-project.jar:?]
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:317) ~[?:?]
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1144) ~[?:?]
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:642) ~[?:?]
# 	at java.base/java.lang.Thread.run(Thread.java:1583) [?:?]
# Caused by: java.lang.ClassNotFoundException: org.apache.iceberg.IcebergBuild
# 	... 11 more

sleep 30

playground connector show-lag --max-wait 300

if [ -z "$GITHUB_RUN_NUMBER" ]
then
  # doesn't work on github actions
  # not running with github actions
  log "You can open the jupyter lab at http://localhost:8888/lab/tree/notebooks and use the sample notebook in notebooks/iceberg.ipynb to query the table"

  log "Verify data is in Iceberg"
  docker exec -i spark-iceberg spark-sql << EOF
SELECT *
FROM orders.payments
LIMIT 10;
EOF
fi