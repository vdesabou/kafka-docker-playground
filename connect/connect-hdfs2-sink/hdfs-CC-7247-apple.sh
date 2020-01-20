#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-CC-7247.yml"


# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"apple.pie",
               "hdfs.url":"hdfs://hadoop:9000",
               "flush.size":"3",
               "hadoop.conf.dir":"/usr/local/hadoop-2.7.1/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "hadoop.home":"/usr/local/hadoop-2.7.1/share/hadoop/common/",
               "logs.dir":"/tmp",
               "topics.dir":"${topic}/${2}/some/path/${1}pie",
               "topic.capture.groups.regex": "^([a-zA-Z]*)[-._]([a-zA-Z]*)$",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs-sink/config | jq_docker_cli .


log "Sending messages to topic apple.pie "
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic apple.pie --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /apple.pie/pie/some/path/applepie/ in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /apple.pie/pie/some/path/applepie/"

# drwxrwxrwx   - root supergroup          0 2019-12-27 10:27 /apple.pie/pie/some/path/applepie/+tmp
# drwxr-xr-x   - root supergroup          0 2019-12-27 10:27 /apple.pie/pie/some/path/applepie/apple.pie