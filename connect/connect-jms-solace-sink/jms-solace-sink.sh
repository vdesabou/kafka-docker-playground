#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/sol-jms-10.6.0.jar ]
then
     echo -e "\033[0;33mDownloading sol-jms-10.6.0.jar\033[0m"
     wget http://central.maven.org/maven2/com/solacesystems/sol-jms/10.6.0/sol-jms-10.6.0.jar
fi

if [ ! -f ${DIR}/commons-lang-2.6.jar ]
then
     echo -e "\033[0;33mDownloading commons-lang-2.6.jar\033[0m"
     wget https://repo1.maven.org/maven2/commons-lang/commons-lang/2.6/commons-lang-2.6.jar
fi

# if [ ! -f ${DIR}/commons-logging-1.1.3.jar ]
# then
#      echo -e "\033[0;33mDownloading commons-logging-1.1.3.jar\033[0m"
#      wget https://repo1.maven.org/maven2/commons-logging/commons-logging/1.1.3/commons-logging-1.1.3.jar
# fi

# if [ ! -f ${DIR}/geronimo-jms_1.1_spec-1.1.1.jar ]
# then
#      echo -e "\033[0;33mDownloading geronimo-jms_1.1_spec-1.1.1.jar\033[0m"
#      wget https://repo1.maven.org/maven2/org/apache/geronimo/specs/geronimo-jms_1.1_spec/1.1.1/geronimo-jms_1.1_spec-1.1.1.jar
# fi

# if [ ! -f ${DIR}/org.apache.servicemix.bundles.jzlib-1.0.7_2.jar ]
# then
#      echo -e "\033[0;33mDownloading org.apache.servicemix.bundles.jzlib-1.0.7_2.jar\033[0m"
#      wget https://repo1.maven.org/maven2/org/apache/servicemix/bundles/org.apache.servicemix.bundles.jzlib/1.0.7_2/org.apache.servicemix.bundles.jzlib-1.0.7_2.jar
# fi

# if [ ! -f ${DIR}/org.osgi.annotation-6.0.0.jar ]
# then
#      echo -e "\033[0;33mDownloading org.osgi.annotation-6.0.0.jar\033[0m"
#      wget https://repo1.maven.org/maven2/org/osgi/org.osgi.annotation/6.0.0/org.osgi.annotation-6.0.0.jar
# fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mWait 60 seconds for Solace to be up and running\033[0m"
sleep 60
echo -e "\033[0;33mSolace UI is accessible at http://127.0.0.1:8080 (admin/admin)\033[0m"

echo -e "\033[0;33mSending messages to topic sink-messages\033[0m"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages

echo -e "\033[0;33mCreate connector-quickstart queue in the default Message VPN using CLI\033[0m"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/create_queue_cmd"

echo -e "\033[0;33mCreating Solace sink connector\033[0m"
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
     http://localhost:8083/connectors/jms-solace-sink/config | jq .

sleep 10

echo -e "\033[0;33mConfirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI\033[0m"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/show_queue_cmd"