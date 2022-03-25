#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: This RBAC example is working starting from CP 5.4 only"
    exit 111
fi

${DIR}/../../environment/rbac-sasl-plain/start.sh "${PWD}/docker-compose.plaintext.repro-96655-rbac-and-centralized-license.yml"

log "Sending messages to topic rbac_gcs_topic"
seq -f "{\"f1\": \"This is a message sent with RBAC SASL/PLAIN authentication %g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_gcs_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --producer.config /etc/kafka/secrets/client_sasl_plain.config

log "Creating Replicator connector"
curl -X PUT \
      -H "Content-Type: application/json" \
      -u connectorSubmitter:connectorSubmitter \
      --data '{
            "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
            "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
            "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
            "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
            "src.consumer.group.id": "duplicate-topic",
            "confluent.topic.replication.factor": 1,
            "provenance.header.enable": true,
            "topic.whitelist": "rbac_gcs_topic",
            "topic.rename.format": "rbac_gcs_topic-duplicate",
            "dest.kafka.bootstrap.servers": "broker:9092",
            "src.kafka.bootstrap.servers": "broker:9092",
            "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectorSA\" password=\"connectorSA\" metadataServerUrls=\"http://broker:8091\";"
           }' \
      http://localhost:8083/connectors/my-rbac-connector/config | jq .

sleep 10

log "Checking messages from topic rbac_gcs_topic-duplicate"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_gcs_topic-duplicate  --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --consumer.config /etc/kafka/secrets/client_sasl_plain.config --consumer-property group.id=clientAvro --from-beginning --max-messages 1


# [2022-03-25 09:19:49,004] ERROR [my-rbac-connector|worker] WorkerConnector{id=my-rbac-connector} Error while starting connector (org.apache.kafka.connect.runtime.WorkerConnector:193)
# org.apache.kafka.common.errors.TimeoutException: License topic could not be created
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting for a node assignment. Call: createTopics
# [2022-03-25 09:19:49,056] ERROR [my-rbac-connector|worker] [Worker clientId=connect-1, groupId=connect-cluster] Failed to start connector 'my-rbac-connector' (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1490)
# org.apache.kafka.connect.errors.ConnectException: Failed to start connector: my-rbac-connector
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.lambda$startConnector$25(DistributedHerder.java:1461)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:335)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to transition connector my-rbac-connector to state STARTED
#         ... 8 more
# Caused by: org.apache.kafka.common.errors.TimeoutException: License topic could not be created
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting for a node assignment. Call: createTopics