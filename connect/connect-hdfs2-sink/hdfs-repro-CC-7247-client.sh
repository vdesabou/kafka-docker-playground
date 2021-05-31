#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.CC-7247.yml"


# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"tracking.mmtro.navigation.client.clientA.enabled,tracking.mmtro.navigation.client.clientB.enabled,tracking.mmtro.navigation.client.client123.enabled,tracking.mmtro.navigation.client.client-C.enabled",
               "hdfs.url":"hdfs://hadoop:9000",
               "flush.size":"3",
               "hadoop.conf.dir":"/usr/local/hadoop-2.7.1/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "hadoop.home":"/usr/local/hadoop-2.7.1/share/hadoop/common/",
               "logs.dir":"/tmp",
               "topics.dir":"${1}/landing/behavioral",
               "topic.capture.groups.regex": ".*\\.client\\.(.*)\\.enabled$",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs-sink/config | jq .


log "Sending messages to topic tracking.mmtro.navigation.client.clientA.enabled "
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic tracking.mmtro.navigation.client.clientA.enabled --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Sending messages to topic tracking.mmtro.navigation.client.clientB.enabled "
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic tracking.mmtro.navigation.client.clientB.enabled --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Sending messages to topic tracking.mmtro.navigation.client.client123.enabled "
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic tracking.mmtro.navigation.client.client123.enabled --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Sending messages to topic tracking.mmtro.navigation.client.client-C.enabled "
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic tracking.mmtro.navigation.client.client-C.enabled --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /clientA/landing/behavioral in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /clientA/landing/behavioral"


# Found 2 items
# drwxrwxrwx   - root supergroup          0 2019-12-16 07:23 /clientA/landing/behavioral/+tmp
# drwxr-xr-x   - root supergroup          0 2019-12-16 07:23 /clientA/landing/behavioral/tracking.mmtro.navigation.client.clientA.enabled

log "Listing content of /clientB/landing/behavioral in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /clientB/landing/behavioral"

# Found 2 items
# drwxrwxrwx   - root supergroup          0 2019-12-16 07:23 /clientB/landing/behavioral/+tmp
# drwxr-xr-x   - root supergroup          0 2019-12-16 07:23 /clientB/landing/behavioral/tracking.mmtro.navigation.client.clientB.enabled

log "Listing content of /client123/landing/behavioral in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /client123/landing/behavioral"

# Found 2 items
# drwxrwxrwx   - root supergroup          0 2019-12-16 10:10 /client123/landing/behavioral/+tmp
# drwxr-xr-x   - root supergroup          0 2019-12-16 10:10 /client123/landing/behavioral/tracking.mmtro.navigation.client.client123.enabled

log "Listing content of /client-C/landing/behavioral in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /client-C/landing/behavioral"

# Found 2 items
# drwxrwxrwx   - root supergroup          0 2019-12-16 10:35 /client-C/landing/behavioral/+tmp
# drwxr-xr-x   - root supergroup          0 2019-12-16 10:35 /client-C/landing/behavioral/tracking.mmtro.navigation.client.client-C.enabled