#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99"
then
    logwarn "This connector does not support CP versions < 6.0.0"
    logwarn "see https://github.com/vdesabou/kafka-docker-playground/issues/2753#issuecomment-1194115633"
    exit 111
fi

export CONNECTOR_VERSION="0.9.3"
if [ ! -f kafka-connector-hana_2.13-$CONNECTOR_VERSION.jar ]
then
     rm -rf kafka-connect-sap
     git clone https://github.com/SAP/kafka-connect-sap.git
     cd kafka-connect-sap
     git checkout tags/$CONNECTOR_VERSION
     cd -
     for component in kafka-connect-sap
     do
          set +e
          log "🏗 Building jar for ${component}"
          docker run -i --rm -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/modules/scala_2.13/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.1-eclipse-temurin-11 mvn install -DskipTests > /tmp/result.log 2>&1
          if [ $? != 0 ]
          then
               logerror "❌ failed to build java component $component"
               tail -500 /tmp/result.log
               exit 1
          fi
          set -e
     done
     cp kafka-connect-sap/modules/scala_2.13/target/kafka-connector-hana_2.13-$CONNECTOR_VERSION.jar .
fi

if [ ! -f ${DIR}/ngdbc-2.12.9.jar ]
then
     log "Downloading ngdbc-2.12.9.jar "
     wget -q https://repo1.maven.org/maven2/com/sap/cloud/db/jdbc/ngdbc/2.12.9/ngdbc-2.12.9.jar
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


playground container logs --container sap --wait-for-log "Startup finished!" --max-wait 600
log "SAP HANA has started!"

log "Creating SAP HANA Sink connector"
playground connector create-or-update --connector sap-hana-sink  << EOF
{
     "tasks.max": "1",
     "connector.class": "com.sap.kafka.connect.sink.hana.HANASinkConnector",
     "topics": "testtopic",
     "connection.url": "jdbc:sap://sap:39041/?databaseName=HXE&reconnect=true&statementCacheSize=512",
     "connection.user": "LOCALDEV",
     "connection.password" : "Localdev1",
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url": "http://schema-registry:8081",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "auto.create": "true",
     "testtopic.table.name": "\"LOCALDEV\".\"TEST\""
}
EOF

sleep 5

log "Sending records to testtopic topic"
docker exec -i connect kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic testtopic --property key.schema='{"type":"record","namespace": "io.confluent.connect.avro","name":"myrecordkey","fields":[{"name":"ID","type":"long"}]}' --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"ID","type":"long"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"ID": 111,"product": "foo", "quantity": 100, "price": 50}
{"ID": 222}|{"ID": 222,"product": "bar", "quantity": 100, "price": 50}
EOF

sleep 120

log "Check data is in SAP HANA"
docker exec -i sap /usr/sap/HXE/HDB90/exe/hdbsql -i 90 -d HXE -u LOCALDEV -p Localdev1 << EOF
select * from "LOCALDEV"."TEST";
EOF
docker exec -i sap /usr/sap/HXE/HDB90/exe/hdbsql -i 90 -d HXE -u LOCALDEV -p Localdev1  > /tmp/result.log  2>&1 <<-EOF
select * from "LOCALDEV"."TEST";
EOF
cat /tmp/result.log
grep "product" /tmp/result.log