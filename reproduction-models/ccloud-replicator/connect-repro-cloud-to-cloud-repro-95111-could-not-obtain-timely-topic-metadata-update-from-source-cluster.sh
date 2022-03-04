#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-cloud-to-cloud.repro-95111-could-not-obtain-timely-topic-metadata-update-from-source-cluster.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
create_topic topic-replicator
set -e

log "Sending messages to topic topic-replicator on SRC cluster (topic topic-replicator should be created manually first)"
docker exec -i -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic topic-replicator --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-cloud-to-same-cloud",
          "src.kafka.ssl.endpoint.identification.algorithm":"https",
          "src.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
          "src.kafka.security.protocol" : "SASL_SSL",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
          "src.kafka.sasl.mechanism":"PLAIN",
          "src.kafka.request.timeout.ms":"20000",
          "src.kafka.retry.backoff.ms":"500",
          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.topic.replication.factor": "3",
          "dest.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "topic.whitelist": "topic-replicator",

          "topic.auto.create": "true",
          "topic.config.sync.interval.ms": "10000",
          "topic.config.sync": "true"
          }' \
     http://localhost:8083/connectors/replicate-cloud-to-same-cloud/config | jq .


# with: (missing src security)

# curl -X PUT \
#      -H "Content-Type: application/json" \
#      --data '{
#           "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
#           "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
#           "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
#           "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
#           "src.consumer.group.id": "replicate-cloud-to-same-cloud",
#           "src.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
#           "dest.kafka.ssl.endpoint.identification.algorithm":"https",
#           "dest.topic.replication.factor": "3",
#           "dest.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
#           "dest.kafka.security.protocol" : "SASL_SSL",
#           "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
#           "dest.kafka.sasl.mechanism":"PLAIN",
#           "dest.kafka.request.timeout.ms":"20000",
#           "dest.kafka.retry.backoff.ms":"500",
#           "topic.whitelist": "topic-replicator",

#           "topic.auto.create": "true",
#           "topic.config.sync.interval.ms": "10000",
#           "topic.config.sync": "true"
#           }' \
#      http://localhost:8083/connectors/replicate-cloud-to-same-cloud/config | jq .

# I get:

# [2022-03-04 11:16:48,488] INFO Gathering task configs... (io.confluent.connect.replicator.ReplicatorSourceConnector)
# [2022-03-04 11:16:48,488] INFO Assigning topic partitions to 1 tasks... (io.confluent.connect.replicator.NewTopicMonitorThread)
# [2022-03-04 11:16:57,980] INFO [AdminClient clientId=adminclient-18] Metadata update failed (org.apache.kafka.clients.admin.internals.AdminMetadataManager)
# org.apache.kafka.common.errors.TimeoutException: Call(callName=fetchMetadata, deadlineMs=1646392617979, tries=1, nextAllowedTryMs=1646392618080) timed out at 1646392617980 after 1 attempt(s)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting for a node assignment.
# [2022-03-04 11:16:58,488] ERROR [Worker clientId=connect-1, groupId=connect] Failed to reconfigure connector's tasks, retrying after backoff: (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# org.apache.kafka.connect.errors.ConnectException: Could not obtain timely topic metadata update from source cluster
#         at io.confluent.connect.replicator.NewTopicMonitorThread.assignments(NewTopicMonitorThread.java:167)
#         at io.confluent.connect.replicator.ReplicatorSourceConnector.taskConfigs(ReplicatorSourceConnector.java:114)
#         at org.apache.kafka.connect.runtime.Worker.connectorTaskConfigs(Worker.java:373)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.reconfigureConnector(DistributedHerder.java:1420)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.reconfigureConnectorTasksWithRetry(DistributedHerder.java:1358)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.access$1000(DistributedHerder.java:127)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder$15$1.call(DistributedHerder.java:1375)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder$15$1.call(DistributedHerder.java:1372)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.tick(DistributedHerder.java:365)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.run(DistributedHerder.java:294)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)

log "Verify we have received the data in topic-replicator topic"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic topic-replicator --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 3'