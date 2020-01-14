#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/sol-jms-10.6.4.jar ]
then
     log "Downloading sol-jms-10.6.4.jar"
     wget http://central.maven.org/maven2/com/solacesystems/sol-jms/10.6.0/sol-jms-10.6.4.jar
fi

if [ ! -f ${DIR}/commons-lang-2.6.jar ]
then
     log "Downloading commons-lang-2.6.jar"
     wget https://repo1.maven.org/maven2/commons-lang/commons-lang/2.6/commons-lang-2.6.jar
fi

# if [ ! -f ${DIR}/commons-logging-1.1.3.jar ]
# then
#      log "Downloading commons-logging-1.1.3.jar"
#      wget https://repo1.maven.org/maven2/commons-logging/commons-logging/1.1.3/commons-logging-1.1.3.jar
# fi

# if [ ! -f ${DIR}/geronimo-jms_1.1_spec-1.1.1.jar ]
# then
#      log "Downloading geronimo-jms_1.1_spec-1.1.1.jar"
#      wget https://repo1.maven.org/maven2/org/apache/geronimo/specs/geronimo-jms_1.1_spec/1.1.1/geronimo-jms_1.1_spec-1.1.1.jar
# fi

# if [ ! -f ${DIR}/org.apache.servicemix.bundles.jzlib-1.0.7_2.jar ]
# then
#      log "Downloading org.apache.servicemix.bundles.jzlib-1.0.7_2.jar"
#      wget https://repo1.maven.org/maven2/org/apache/servicemix/bundles/org.apache.servicemix.bundles.jzlib/1.0.7_2/org.apache.servicemix.bundles.jzlib-1.0.7_2.jar
# fi

# if [ ! -f ${DIR}/org.osgi.annotation-6.0.0.jar ]
# then
#      log "Downloading org.osgi.annotation-6.0.0.jar"
#      wget https://repo1.maven.org/maven2/org/osgi/org.osgi.annotation/6.0.0/org.osgi.annotation-6.0.0.jar
# fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Wait 60 seconds for Solace to be up and running"
sleep 60
log "Solace UI is accessible at http://127.0.0.1:8080 (admin/admin)"

log "Sending messages to topic sink-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages

log "Create connector-quickstart queue in the default Message VPN using CLI"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/create_queue_cmd"

log "Creating Solace sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
                    "tasks.max": "1",
                    "topics": "sink-messages",
                    "java.naming.factory.initial": "com.solacesystems.jndi.SolJNDIInitialContextFactory",
                    "java.naming.provider.url": "smf://solace:55555",
                    "java.naming.security.principal": "admin",
                    "java.naming.security.credentials": "admin",
                    "connection.factory.name": "/jms/cf/default",
                    "Solace_JMS_VPN": "default",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-solace-sink/config | jq_docker_cli .

sleep 10

log "Confirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/show_queue_cmd"