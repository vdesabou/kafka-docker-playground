#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     create_topic dbserver1_mydb_team
     create_topic dbserver1
     create_topic schema-changes.mydb
     set -e
fi


log "Describing the team table in DB 'mydb':"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'describe team'"

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

log "Adding an element to the table"
docker exec mysql mysql --user=root --password=password --database=mydb -e "
INSERT INTO team (   \
  id,   \
  name, \
  email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
); "

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

log "Creating Debezium MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.mysql.MySqlConnector",
               "tasks.max": "1",
               "database.hostname": "mysql",
               "database.port": "3306",
               "database.user": "debezium",
               "database.password": "dbz",
               "database.server.id": "223344",
               "database.server.name": "dbserver1",
               "database.whitelist": "mydb",
               "database.history.consumer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "database.history.consumer.sasl.mechanism": "PLAIN",
               "database.history.consumer.security.protocol": "SASL_SSL",
               "database.history.consumer.ssl.endpoint.identification.algorithm": "https",
               "database.history.kafka.bootstrap.servers":  "${file:/data:bootstrap.servers}",
               "database.history.kafka.topic": "cdc.lower-case-email-gmail-migration-qa.gmail_integration.gmail_integration.connected_accounts.schemaChanges",
               "database.history.producer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "database.history.producer.sasl.mechanism": "PLAIN",
               "database.history.producer.security.protocol": "SASL_SSL",
               "database.history.producer.ssl.endpoint.identification.algorithm": "https",
               "database.history.kafka.topic": "schema-changes.mydb",
               "transforms": "RemoveDots",
               "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
               "transforms.RemoveDots.replacement": "$1_$2_$3",
               "topic.creation.default.replication.factor": "-1",
               "topic.creation.default.partitions": "-1"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

log "Verifying topic dbserver1_mydb_team"
timeout 60 docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic dbserver1_mydb_team --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 2'

