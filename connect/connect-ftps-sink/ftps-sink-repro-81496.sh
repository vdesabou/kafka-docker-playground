#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/security
log "🔐 Generate keys and certificates used for SSL"
docker run -u0 --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
cd ${DIR}

if [ ! -z "$CI" ]
then
     # running with github actions
     sudo chown root ${DIR}/config/vsftpd.conf
     sudo chown root ${DIR}/security/vsftpd.pem
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-81496.yml"


log "Creating JSON file with schema FTPS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "3",
               "connector.class": "io.confluent.connect.ftps.FtpsSinkConnector",
               "ftps.working.dir": "/",
               "ftps.username":"bob",
               "ftps.password":"test",
               "ftps.host":"ftps-server",
               "ftps.port":"220",
               "ftps.security.mode": "EXPLICIT",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "ftps.ssl.truststore.location": "/etc/kafka/secrets/kafka.ftps-server.truststore.jks",
               "ftps.ssl.truststore.password": "${file:/etc/kafka/secrets/kafkajks.txt:password}",
               "ftps.ssl.keystore.location": "/etc/kafka/secrets/kafka.ftps-server.keystore.jks",
               "ftps.ssl.key.password": "${file:/etc/kafka/secrets/kafkajks.txt:password}",
               "ftps.ssl.keystore.password": "${file:/etc/kafka/secrets/kafkajks.txt:password}",
               "topics": "test_ftps_sink",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "format.class": "io.confluent.connect.ftps.sink.format.avro.AvroFormat",
               "flush.size": "1"
          }' \
     http://localhost:8083/connectors/ftps-sink/config | jq .

log "Sending messages to topic test_ftps_sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_ftps_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /home/vsftpd/bob/test_ftps_sink/partition\=0/"
docker exec ftps-server bash -c "ls /home/vsftpd/bob/test_ftps_sink/partition\=0/"

log "Moving JKS files and kafkajks.txt to new folder /tmp"
docker exec connect mv /etc/kafka/secrets/kafka.ftps-server.truststore.jks /tmp/
docker exec connect mv /etc/kafka/secrets/kafka.ftps-server.keystore.jks /tmp/
docker exec connect mv /etc/kafka/secrets/kafkajks.txt /tmp/

log "Reloading connector with /tmp"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "3",
               "connector.class": "io.confluent.connect.ftps.FtpsSinkConnector",
               "ftps.working.dir": "/",
               "ftps.username":"bob",
               "ftps.password":"test",
               "ftps.host":"ftps-server",
               "ftps.port":"220",
               "ftps.security.mode": "EXPLICIT",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "ftps.ssl.truststore.location": "/tmp/kafka.ftps-server.truststore.jks",
               "ftps.ssl.truststore.password": "${file:/tmp/kafkajks.txt:password}",
               "ftps.ssl.keystore.location": "/tmp/kafka.ftps-server.keystore.jks",
               "ftps.ssl.key.password": "${file:/tmp/kafkajks.txt:password}",
               "ftps.ssl.keystore.password": "${file:/tmp/kafkajks.txt:password}",
               "topics": "test_ftps_sink",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "format.class": "io.confluent.connect.ftps.sink.format.avro.AvroFormat",
               "flush.size": "1"
          }' \
     http://localhost:8083/connectors/ftps-sink/config | jq .


# [2021-11-22 09:30:01,829] ERROR [Worker clientId=connect-1, groupId=connect-cluster] Failed to reconfigure connector's tasks (ftps-sink), retrying after backoff: (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1522)
# org.apache.kafka.common.config.ConfigException: Could not read properties from file /etc/kafka/secrets/kafkajks.txt
# 	at org.apache.kafka.common.config.provider.FileConfigProvider.get(FileConfigProvider.java:92)
# 	at org.apache.kafka.common.config.ConfigTransformer.transform(ConfigTransformer.java:103)
# 	at org.apache.kafka.connect.runtime.WorkerConfigTransformer.transform(WorkerConfigTransformer.java:58)
# 	at org.apache.kafka.connect.runtime.distributed.ClusterConfigState.taskConfig(ClusterConfigState.java:164)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.reconfigureConnector(DistributedHerder.java:1575)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.reconfigureConnectorTasksWithRetry(DistributedHerder.java:1513)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.lambda$null$29(DistributedHerder.java:1526)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.tick(DistributedHerder.java:408)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.run(DistributedHerder.java:326)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
