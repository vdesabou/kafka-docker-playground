#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-repro-98764 producer-repro-98764-2 producer-repro-98764-3
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-98764-hdfs3-sink-connector-not-writting-new-fields.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -chmod 777  /"


log "Creating HDFS Sink connector without Hive integration (not supported with JDK 11)"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
               "tasks.max":"1",
               "topics":"customer_avro",
               "store.url":"hdfs://namenode:9000",
               "flush.size":"5",
               "hadoop.conf.dir":"/etc/hadoop/",

               "format.class": "io.confluent.connect.hdfs3.avro.AvroFormat",
               "rotate.interval.ms": "900000",
               "timezone": "Europe/Paris",

               "partitioner.class": "io.confluent.connect.storage.partitioner.DailyPartitioner",
               "path.format": "'year'=YYYY/'month'=MM/'day'=dd/",
               "locale": "en-GB",
               "timezone": "Europe/Paris",

               "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
               "logs.dir":"/tmp",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD",
               "connect.meta.data": "false",
               "value.converter.connect.meta.data": "false"
          }' \
     http://localhost:8083/connectors/hdfs3-sink/config | jq .


log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-98764 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing content of /topics/customer_avro in HDFS"
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -ls /topics/customer_avro"

log "✨ Run the avro java producer which produces to topic customer_avro, with additional fields ADDED_FIELD_1 and ADDED_FIELD_2"
docker exec producer-repro-98764-2 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "✨ Run the avro java producer which produces to topic customer_avro, with additional fields ADDED_FIELD_1 and ADDED_FIELD_2 and updated connect.version"
docker exec producer-repro-98764-3 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing content of /topics/customer_avro in HDFS"
docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -ls /topics/customer_avro"

log "Get v1"
curl --request GET \
  --url http://localhost:8081/subjects/customer_avro-value/versions/1

log "Get v2"
curl --request GET \
  --url http://localhost:8081/subjects/customer_avro-value/versions/2

log "Get v3"
curl --request GET \
  --url http://localhost:8081/subjects/customer_avro-value/versions/3

docker exec namenode bash -c "rm -rf /tmp/customer_avro;/opt/hadoop-3.1.3/bin/hadoop fs -copyToLocal /topics/customer_avro /tmp/customer_avro"
docker exec namenode tar cvfz file.tgz /tmp/customer_avro
docker cp namenode:/file.tgz /tmp/

rm -rf tmp
tar xvfz /tmp/file.tgz


set +e
found=0
for file in $(find tmp/customer_avro -name *.avro)
do
     grep ADDED_FIELD_1 $file
     if [ $? = 0 ]
     then
          log "Found new field ADDED_FIELD_1 in $file"
          found=1
          continue
     fi

     grep ADDED_FIELD_2 $file
     if [ $? = 0 ]
     then
          log "Found new field ADDED_FIELD_2 in $file"
          found=1
          continue
     fi
done
if [ $found -eq 0 ]
then
     log "Problem has been reproduced !"
fi
set -e

# When removing from the schema itself:

#     "connect.name": "aname",
#     "connect.version": 1

# or updating "connect.version": 2

# ...then it works:

# 10:10:02 ℹ️ Found new field ADDED_FIELD_1 in tmp/customer_avro/year=2022/month=03/day=28/customer_avro+0+0000000010+0000000014.avro
# 10:10:02 ℹ️ Found new field ADDED_FIELD_1 in tmp/customer_avro/year=2022/month=03/day=28/customer_avro+0+0000000015+0000000019.avro

# event when setting, it does not work:

#                "value.converter.connect.meta.data": "false"


