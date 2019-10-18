#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco

if [ ! -f ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     echo "ERROR: ${DIR}/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
     exit 1
fi

if [ ! -f ${DIR}/tibjms.jar ]
then
     echo "${DIR}/tibjms.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/tibjms.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

if [ ! -f ${DIR}/jms-2.0.jar ]
then
     echo "${DIR}/jms-2.0.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/jms-2.0.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/jms-2.0.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

if test -z "$(docker images -q tibems:latest)"
then
     echo "Building TIBCO EMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:latest . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


# This is clashing when TIBCO, IBM MQ and ActiveMQ connectors are installed
docker container exec connect rm -rf /usr/share/confluent-hub-components/confluentinc-kafka-connect-activemq
docker container exec connect rm -rf /usr/share/confluent-hub-components/confluentinc-kafka-connect-ibmmq
docker container exec connect rm -rf /usr/share/confluent-hub-components/confluentinc-kafka-connect-ibmmq-sink
docker container exec connect rm -rf /usr/share/confluent-hub-components/confluentinc-kafka-connect-tibco-sink
docker container exec connect rm -rf /usr/share/confluent-hub-components/confluentinc-kafka-connect-tibco-source
docker container restart connect

echo "sleeping 60 seconds"
sleep 60

echo "Sending EMS messages m1 m2 m3 m4 m5 in queue connector-quickstart"
docker container exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgProducer -user admin -queue connector-quickstart m1 m2 m3 m4 m5'


echo "Creating JMS TIBCO source connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "jms-tibco-source",
               "config": {
                    "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "from-tibco-messages",
                    "java.naming.factory.initial": "com.tibco.tibjms.naming.TibjmsInitialContextFactory",
                    "java.naming.provider.url": "tibjmsnaming://tibco-ems:7222",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

echo "Verify we have received the data in from-tibco-messages topic"
docker container exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic from-tibco-messages --from-beginning --max-messages 2
