#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

file="producer-repro-93917-customer.avsc"
mkdir -p producer-repro-108092/src/main/resources/avro/
cd producer-repro-108092/src/main/resources/avro/
get_3rdparty_file "$file"
if [ ! -f $file ]
then
     logerror "ERROR: $file is missing"
     exit 1
else
     mv $file customer.avsc
fi
cd -

file="producer-repro-93917-2-customer.avsc"
mkdir -p producer-repro-108092-2/src/main/resources/avro/
cd producer-repro-108092-2/src/main/resources/avro/
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

for component in producer-repro-108092 producer-repro-108092-2
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-108092-schemaprojectorexception.yml"

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
               "flush.size":"10",
               "hadoop.conf.dir":"/etc/hadoop/",

               "partitioner.class": "io.confluent.connect.storage.partitioner.DailyPartitioner",
               "path.format": "'year'=YYYY/'month'=MM/'day'=dd/",
               "locale": "en-GB",
               "timezone": "Europe/Paris",

               "rotate.interval.ms":"120000",
               "logs.dir":"/tmp",

               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"FULL"
          }' \
     http://localhost:8083/connectors/hdfs-sink/config | jq .


log "Register first version using producer-repro-108092/src/main/resources/avro/customer.avsc"
escaped_json=$(jq -c -Rs '.' producer-repro-108092/src/main/resources/avro/customer.avsc)
cat << EOF > /tmp/final.json
{"schema":$escaped_json}
EOF

log "Register new version v1 for schema customer_avro-value"
curl -X POST http://localhost:8081/subjects/customer_avro-value/versions \
--header 'Content-Type: application/vnd.schemaregistry.v1+json' \
--data @/tmp/final.json

log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec -d producer-repro-108092 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing content of /topics/customer_avro in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/customer_avro"



log "Register second version using producer-repro-108092-2/src/main/resources/avro/customer.avsc"
escaped_json=$(jq -c -Rs '.' producer-repro-108092-2/src/main/resources/avro/customer.avsc)

cat << EOF > /tmp/final.json
{"schema":$escaped_json}
EOF

log "Register new version v2 for schema customer_avro-value"
curl -X POST http://localhost:8081/subjects/customer_avro-value/versions \
--header 'Content-Type: application/vnd.schemaregistry.v1+json' \
--data @/tmp/final.json

log "✨ Run the avro java producer which produces to topic customer_avro, with added optional field"
docker exec -d producer-repro-108092-2 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"
