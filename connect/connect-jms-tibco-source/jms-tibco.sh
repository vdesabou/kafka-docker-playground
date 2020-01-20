#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco

if [ ! -f ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     logerror "ERROR: ${DIR}/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
     exit 1
fi

if [ ! -f ${DIR}/tibjms.jar ]
then
     log "${DIR}/tibjms.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/tibjms.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

if [ ! -f ${DIR}/jms-2.0.jar ]
then
     log "${DIR}/jms-2.0.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/jms-2.0.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/jms-2.0.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

if test -z "$(docker images -q tibems:latest)"
then
     log "Building TIBCO EMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:latest . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending EMS messages m1 m2 m3 m4 m5 in queue connector-quickstart"
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgProducer -user admin -queue connector-quickstart m1 m2 m3 m4 m5'


log "Creating JMS TIBCO source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
          }' \
     http://localhost:8083/connectors/jms-tibco-source/config | jq_docker_cli .

sleep 5

log "Verify we have received the data in from-tibco-messages topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic from-tibco-messages --from-beginning --max-messages 2
