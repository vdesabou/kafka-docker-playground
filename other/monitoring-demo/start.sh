#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget -q https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi


for component in producer consumer streams
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "❌ failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "-------------------------------------"
log "Dotnet client examples"
log "-------------------------------------"

log "Starting dotnet producer"
docker exec -d client-dotnet dotnet Monitoring.dll produce topic-dotnet

log "Starting dotnet consume"
docker exec -d client-dotnet dotnet Monitoring.dll consume topic-dotnet

log "-------------------------------------"
log "Connector examples"
log "-------------------------------------"


log "Creating MySQL source connector"
playground connector create-or-update --connector mysql-source  << EOF
{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"1",
               "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
               "table.whitelist":"application",
               "mode":"timestamp+incrementing",
               "timestamp.column.name":"last_modified",
               "incrementing.column.name":"id",
               "topic.prefix":"mysql-"
          }
EOF

log "Adding an element to the table"
docker exec mysql mysql --user=root --password=password --database=db -e "
INSERT INTO application (   \
  id,   \
  name, \
  team_email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
);"




sleep 30

if [ -z "$CLOUDFORMATION" ]
then
     log "Verifying topic mysql-application"
     # this command works for both cases (with local schema registry and Confluent Cloud Schema Registry)
playground topic consume --topic mysql-application --min-expected-messages 2 --timeout 60
fi


log "Creating http-sink connector"
playground connector create-or-update --connector http-sink  << EOF
{
               "topics": "mysql-application",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker-europe:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker-europe:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password"
          }
EOF

sleep 30

if [ -z "$CLOUDFORMATION" ]
then
     log "Confirm that the data was sent to the HTTP endpoint."
     curl admin:password@localhost:9083/api/messages | jq .
fi

log "Creating Elasticsearch Sink connector"
playground connector create-or-update --connector elasticsearch-sink  << EOF
{
        "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
          "tasks.max": "1",
          "topics": "mysql-application",
          "key.ignore": "true",
          "connection.url": "http://elasticsearch:9200",
          "type.name": "kafka-connect",
          "name": "elasticsearch-sink"
          }
EOF

sleep 40

if [ -z "$CLOUDFORMATION" ]
then
     log "Check that the data is available in Elasticsearch"
     curl -XGET 'http://localhost:9200/mysql-application/_search?pretty'
fi

# if [[ ! $(type kafka-consumer-groups 2>&1) =~ "not found" ]]; then
#      log "Example showing how to use kafka-consumer-groups command for Confluent Cloud"
#      kafka-consumer-groups --bootstrap-server "broker-europe:9092" --list
#      kafka-consumer-groups --bootstrap-server "broker-europe:9092" --group simple-stream --describe
# fi


log "Sending sales in Europe cluster"

seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i connect-europe bash -c "KAFKA_OPTS="";kafka-console-producer --bootstrap-server broker-europe:9092 --topic sales_EUROPE"

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "KAFKA_OPTS="";kafka-console-producer --bootstrap-server broker-us:9092 --topic sales_US"


log "Consolidating all sales in the US"

docker container exec connect-us \
playground connector create-or-update --connector replicate-europe-to-us  << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE"
          }
EOF


log "Consolidating all sales in Europe"

docker container exec connect-europe \
playground connector create-or-update --connector replicate-us-to-europe  << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-us-to-europe",
          "src.kafka.bootstrap.servers": "broker-us:9092",
          "dest.kafka.bootstrap.servers": "broker-europe:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_US"
          }
EOF

sleep 120

log "Verify we have received the data in all the sales_ topics in EUROPE"
docker container exec -i connect-europe bash -c "KAFKA_OPTS="";kafka-console-consumer --bootstrap-server broker-europe:9092 --include 'sales_.*' --from-beginning --max-messages 20 --property metadata.max.age.ms 30000"

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i connect-us bash -c "KAFKA_OPTS=""; kafka-console-consumer --bootstrap-server broker-us:9092 --include 'sales_.*' --from-beginning --max-messages 20 --property metadata.max.age.ms 30000"

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # running with github actions
     log "##################################################"
     log "Stopping everything"
     log "##################################################"
     bash ${DIR}/stop.sh
fi
