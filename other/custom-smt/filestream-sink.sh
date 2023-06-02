#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


for component in MyCustomSMT
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic filestream"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic filestream << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF

log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink << EOF
{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
               "topics": "filestream",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "transforms": "MyCustomSMT",
               "transforms.MyCustomSMT.type": "com.github.vdesabou.kafka.connect.transforms.MyCustomSMT"
          }
EOF


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json
