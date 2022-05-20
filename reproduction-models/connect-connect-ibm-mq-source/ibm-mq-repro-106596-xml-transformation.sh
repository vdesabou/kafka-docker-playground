#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

file="repro-106596-FromXmlToJson.java"
final_file="FromXmlToJson.java"
folder="FromXmlToJson/src/main/java/com/github/vdesabou/kafka/connect/transform"
if [ ! -f $folder/$final_file ]
then
     cd $folder
     get_3rdparty_file "$file"
     if [ ! -f $file ]
     then
          logerror "ERROR: $file is missing"
          exit 1
     else
          mv $file $final_file
     fi
     cd -
fi

file="repro-106596-BaseJsonGenerator.java"
final_file="BaseJsonGenerator.java"
folder="FromXmlToJson/src/main/java/com/github/vdesabou/kafka/connect/transform"
if [ ! -f $folder/$final_file ]
then
     cd $folder
     get_3rdparty_file "$file"
     if [ ! -f $file ]
     then
          logerror "ERROR: $file is missing"
          exit 1
     else
          mv $file $final_file
     fi
     cd -
fi

file="repro-106596-exampleMessage.xml"
final_file="exampleMessage.xml"
folder="."
if [ ! -f $folder/$final_file ]
then
     cd $folder
     get_3rdparty_file "$file"
     if [ ! -f $file ]
     then
          logerror "ERROR: $file is missing"
          exit 1
     else
          mv $file $final_file
     fi
     cd -
fi

for component in FromXmlToJson
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

get_3rdparty_file "IBM-MQ-Install-Java-All.jar"

if [ ! -f ${DIR}/IBM-MQ-Install-Java-All.jar ]
then
     # not running with github actions
     logerror "ERROR: ${DIR}/IBM-MQ-Install-Java-All.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

if [ ! -f ${DIR}/com.ibm.mq.allclient.jar ]
then
     # install deps
     log "Getting com.ibm.mq.allclient.jar and jms.jar from IBM-MQ-Install-Java-All.jar"
     if [[ "$OSTYPE" == "darwin"* ]]
     then
          # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
          rm -rf ${DIR}/install/
     else
          sudo rm -rf ${DIR}/install/
     fi
     docker run --rm -v ${DIR}/IBM-MQ-Install-Java-All.jar:/tmp/IBM-MQ-Install-Java-All.jar -v ${DIR}/install:/tmp/install openjdk:8 java -jar /tmp/IBM-MQ-Install-Java-All.jar --acceptLicense /tmp/install
     cp ${DIR}/install/wmq/JavaSE/lib/jms.jar ${DIR}/
     cp ${DIR}/install/wmq/JavaSE/lib/com.ibm.mq.allclient.jar ${DIR}/
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-106596-xml-transformation.yml"


log "Creating IBM MQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.ibm.mq.IbmMQSourceConnector",
               "kafka.topic": "MyKafkaTopicName",
               "mq.hostname": "ibmmq",
               "mq.port": "1414",
               "mq.transport.type": "client",
               "mq.queue.manager": "QM1",
               "mq.channel": "DEV.APP.SVRCONN",
               "mq.username": "app",
               "mq.password": "passw0rd",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "transforms": "extractPayload,xml",
               "transforms.extractPayload.type": "org.apache.kafka.connect.transforms.ExtractField$Value",
               "transforms.extractPayload.field": "text",
               "transforms.xml.type": "com.github.vdesabou.kafka.connect.transforms.FromXmlToJson$Value",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter"
          }' \
     http://localhost:8083/connectors/ibm-mq-source/config | jq .

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
<?xml version="1.0"?><note><to>Tove</to><from>Jani</from><heading>Reminder</heading><body>Don't forget me this weekend!</body></note>
EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MyKafkaTopicName --from-beginning --max-messages 2
