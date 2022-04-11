#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

file="producer-repro-101057-customer.avsc"
cd producer-repro-101057/src/main/resources/avro/
get_3rdparty_file "$file"
if [ ! -f $file ]
then
     logerror "ERROR: $file is missing"
     exit 1
else
     mv $file customer.avsc
fi
cd -

file="producer-repro-101057-2-customer.avsc"
cd producer-repro-101057-2/src/main/resources/avro/
get_3rdparty_file "$file"
if [ ! -f $file ]
then
     logerror "ERROR: $file is missing"
     exit 1
else
     mv $file customer.avsc
fi
cd -

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.2/hive-jdbc-3.1.2-standalone.jar
fi


for component in producer-repro-101057 producer-repro-101057-2
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-101057-doc-values-and-schema-compatibility.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"customer_avro",
               "store.url":"hdfs://namenode:8020",
               "flush.size":"3",
               "hadoop.conf.dir":"/etc/hadoop/",
               "locale": "en-US",
               "max.retries": "5",
               "timezone": "UTC",
               "rotate.interval.ms":"120000",
               "logs.dir":"/tmp",
               "hive.integration": "true",
               "hive.metastore.uris": "thrift://hive-metastore:9083",
               "hive.database": "testhive",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"FULL",

               "format.class":"io.confluent.connect.hdfs.avro.AvroFormat",
               "value.converter.connect.meta.data":"false"
          }' \
     http://localhost:8083/connectors/hdfs-sink/config | jq .



log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-101057 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"


sleep 10

log "Listing content of /topics/customer_avro in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/customer_avro"



log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-101057-2 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"


log "Check data with beeline"
docker exec -i hive-server beeline > /tmp/result.log  2>&1 <<-EOF
!connect jdbc:hive2://hive-server:10000/testhive
hive
hive
show create table customer_avro;
select * from customer_avro;
EOF
cat /tmp/result.log