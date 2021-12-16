#!/bin/bash
set -e

# to reproduce use version 1.3.1
export CONNECTOR_TAG=1.3.1

# 1.3.1: 🔥
# 1.3.2: 🔥
# 1.3.3: ✅
# 1.4.0: 🔥
# 1.4.2: ✅
# 1.5.0: ✅


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "04_populate_customer.sh" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show '04_populate_customer.sh' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"

# Create a redo-log-topic. Please make sure you create a topic with the same name you will use for "redo.log.topic.name": "redo-log-topic"
# CC-13104
docker exec connect kafka-topics --create --topic redo-log-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1 --config cleanup.policy=delete --config retention.ms=120960000
log "redo-log-topic is created"
sleep 5


log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "XE",
               "oracle.username": "MYUSER",
               "oracle.password": "password",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "key.converter.schemas.enable": "false",
               "key.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "redo.log.row.fetch.size":1
          }' \
     http://localhost:8083/connectors/cdc-oracle11-source/config | jq .

log "Waiting 10s for connector to read existing data"
sleep 10

log "Running SQL scripts"
for script in ${DIR}/sample-sql-scripts/*.sh
do
     $script
done

log "Waiting 30s for connector to read new data"
sleep 30

log "Issue reproduced if topic XE.MYUSER.CUSTOMERS has only 5 records"
set +e
timeout 30 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic XE.MYUSER.CUSTOMERS --from-beginning --max-messages 13 > /tmp/result.log  2>&1
cat /tmp/result.log

log "Issue reproduced if topic redo-log-topic has 0 records"
timeout 30 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic redo-log-topic --from-beginning --max-messages 9
set -e
