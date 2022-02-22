#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# if version_gt $TAG_BASE "5.9.0"; then
#      log "Hbase does not support JDK 11, see https://hbase.apache.org/book.html#java"
#      # known_issue https://github.com/vdesabou/kafka-docker-playground/issues/907
#      exit 107
# fi

PROJECT=${1:-vincent-de-saboulin-lab}
INSTANCE=${2:-test-instance}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-88854-connect-centralized-license-not-working.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Deleting instance, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $INSTANCE --project $PROJECT  << EOF
Y
EOF
set -e
log "Create a BigTable Instance and Database"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances create $INSTANCE --project $PROJECT --cluster $INSTANCE --cluster-zone=us-east1-c --display-name="playground-bigtable-instance" --instance-type=DEVELOPMENT

log "Sending messages to topic stats"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic stats --property parse.key=true --property key.separator=, --property key.schema='{"type" : "string", "name" : "id"}' --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"users","type":{"name":"columnfamily","type":"record","fields":[{"name": "name", "type": "string"},{"name": "friends", "type": "string"}]}}]}' << EOF
"simple-key-1", {"users": {"name":"Bob","friends": "1000"}}
"simple-key-2", {"users": {"name":"Jess","friends": "10000"}}
"simple-key-3", {"users": {"name":"John","friends": "10000"}}
EOF


log "Creating GCP BigTbale Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcp.bigtable.BigtableSinkConnector",
               "tasks.max" : "1",
               "topics" : "stats",
               "auto.create" : "true",
               "gcp.bigtable.credentials.path": "/tmp/keyfile.json",
               "gcp.bigtable.instance.id": "'"$INSTANCE"'",
               "gcp.bigtable.project.id": "'"$PROJECT"'",
               "auto.create.tables": "true",
               "auto.create.column.families": "true",
               "table.name.format" : "kafka_${topic}"
          }' \
     http://localhost:8083/connectors/gcp-bigtable-sink/config | jq .

sleep 30


# [2022-02-04 11:01:46,069] ERROR [gcp-bigtable-sink|worker] [Worker clientId=connect-1, groupId=connect-cluster] Failed to start connector 'gcp-bigtable-sink' (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1490)
# org.apache.kafka.connect.errors.ConnectException: Failed to start connector: gcp-bigtable-sink
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.lambda$startConnector$25(DistributedHerder.java:1461)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:335)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to transition connector gcp-bigtable-sink to state STARTED
#         ... 8 more
# Caused by: org.apache.kafka.common.config.ConfigException: Missing required configuration "confluent.topic.bootstrap.servers" which has no default value.
#         at org.apache.kafka.common.config.ConfigDef.parseValue(ConfigDef.java:507)
#         at org.apache.kafka.common.config.ConfigDef.parse(ConfigDef.java:497)
#         at org.apache.kafka.common.config.AbstractConfig.<init>(AbstractConfig.java:113)
#         at org.apache.kafka.common.config.AbstractConfig.<init>(AbstractConfig.java:133)
#         at io.confluent.connect.bigtable.BaseBigtableSinkConnectorConfig.<init>(BaseBigtableSinkConnectorConfig.java:235)
#         at io.confluent.connect.gcp.bigtable.BigtableSinkConnectorConfig.<init>(BigtableSinkConnectorConfig.java:65)
#         at io.confluent.connect.gcp.bigtable.BigtableSinkConnector.config(BigtableSinkConnector.java:28)
#         at io.confluent.connect.gcp.bigtable.BigtableSinkConnector.config(BigtableSinkConnector.java:22)
#         at io.confluent.connect.bigtable.BaseBigtableSinkConnector.start(BaseBigtableSinkConnector.java:32)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doStart(WorkerConnector.java:185)
#         at org.apache.kafka.connect.runtime.WorkerConnector.start(WorkerConnector.java:210)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:349)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:332)
#         ... 7 more

log "Verify data is in GCP BigTable"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $PROJECT -instance $INSTANCE read kafka_stats > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Bob" /tmp/result.log

log "Delete table"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $PROJECT -instance $INSTANCE deletetable kafka_stats

log "Deleting instance"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $INSTANCE --project $PROJECT  << EOF
Y
EOF

docker rm -f gcloud-config
