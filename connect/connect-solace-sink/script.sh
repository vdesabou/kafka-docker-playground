export TAG=6.1.1
export DISABLE_KSQLDB=true
export DISABLE_CONTROL_CENTER=true
#export ENABLE_JMX_GRAFANA=true

./solace-sink.sh

docker exec -it connect /usr/bin/confluent-hub install confluentinc/kafka-connect-jms:11.0.5 --no-prompt
docker exec -it connect /usr/bin/confluent-hub install confluentinc/kafka-connect-solace-sink:latest --no-prompt

if [ ! -f ${DIR}/javax.jms-api-2.0.jar ]
then
     log "Downloading jms-2.0.jar"
     wget https://repo1.maven.org/maven2/javax/jms/javax.jms-api/2.0/javax.jms-api-2.0.jar
fi

if [ ! -f ${DIR}/commons-lang-2.6.jar ]
then
     log "Downloading commons-lang-2.6.jar"
     wget https://repo1.maven.org/maven2/commons-lang/commons-lang/2.6/commons-lang-2.6.jar
fi

docker cp javax.jms-api-2.0.jar connect:/usr/share/confluent-hub-components/confluentinc-kafka-connect-jms/lib/jms-2.0.jar
docker cp commons-lang-2.6.jar connect:/usr/share/confluent-hub-components/confluentinc-kafka-connect-jms/lib/commons-lang-2.6.jar
docker cp sol-jms-10.6.4.jar connect:/usr/share/confluent-hub-components/confluentinc-kafka-connect-jms/lib/sol-jms-10.6.4.jar

docker exec -it connect /usr/bin/confluent-hub install confluentinc/kafka-connect-datagen:latest --no-prompt
docker restart connect
sleep 40

docker exec -it connect ls /usr/share/confluent-hub-components

docker exec -it connect ls /usr/share/confluent-hub-components/confluentinc-kafka-connect-jms/lib/

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
    "tasks.max": "10",
    "kafka.topic": "sink-messages",
    "iterations": "1",
    "max.interval": "10",
    "schema.string": "{ \t\t\"name\": \"timestamp_field\", \t\t\"type\": \"record\", \t\t\"fields\": [ \t\t\t{ \t\t\t\t\"name\": \"timestamp\",  \t\t\t\t\"type\": { \t\t\t\t\t\"type\": \"string\", \t\t\t\t\t\"arg.properties\": { \t\t\t\t\t\t\"options\": [ \t\t\t\t\t\t\t\"timestamp\" \t\t\t\t\t\t] \t\t\t\t\t} \t\t\t\t} \t\t\t} \t\t] \t}"
  }' \
     http://localhost:8083/connectors/datagen-internal/config | jq .

sleep 40
curl localhost:8083/connectors/datagen-internal/status

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.SolaceSinkConnector",
                    "tasks.max": "10",
                    "topics": "sink-messages",
                    "solace.host": "smf://solace:55555",
                    "solace.username": "admin",
                    "solace.password": "admin",
                    "solace.dynamic.durables": "true",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/SolaceSinkConnector/config | jq .
sleep 300

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "source-messages",
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
     http://localhost:8083/connectors/jms-solace-source/config | jq .

docker exec -it connect /usr/bin/kafka-consumer-perf-test  --messages 100000 --broker-list broker:9092 --topic  source-messages --print-metrics --reporting-interval 1000 --show-detailed-stats --timeout 90000 --from-latest --consumer.config /etc/kafka/consumer.properties

