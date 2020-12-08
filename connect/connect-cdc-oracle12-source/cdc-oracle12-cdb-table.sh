#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -d ${DIR}/confluentinc-kafka-connect-oracle-cdc-1.0.0-rc-0463ef7-preview ]
then
     logerror "ERROR: ${DIR}/confluentinc-kafka-connect-oracle-cdc-1.0.0-rc-0463ef7-preview is missing."
     exit 1
fi

if [ -z "$CI" ]
then
     # not running with github actions
     if test -z "$(docker images -q oracle/database:12.2.0.1-ee)"
     then
          if [ ! -f ${DIR}/linuxx64_12201_database.zip ]
          then
               logerror "ERROR: ${DIR}/linuxx64_12201_database.zip is missing. It must be downloaded manually in order to acknowledge user agreement"
               exit 1
          fi
          log "Building oracle/database:12.2.0.1-ee docker image..it can take a while...(more than 15 minutes!)"
          OLDDIR=$PWD
          rm -rf ${DIR}/docker-images
          git clone https://github.com/oracle/docker-images.git

          cp ${DIR}/linuxx64_12201_database.zip ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles/12.2.0.1/linuxx64_12201_database.zip
          cd ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles
          ./buildDockerImage.sh -v 12.2.0.1 -e
          rm -rf ${DIR}/docker-images
          cd ${OLDDIR}
     fi
fi

export ORACLE_IMAGE="oracle/database:12.2.0.1-ee"
if [ ! -z "$CI" ]
then
     # if this is github actions, use private image.
     export ORACLE_IMAGE="vdesabou/oracle12"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-cdb-table.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "DONE: Executing user defined scripts" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":1,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "connection.pool.max.size": 20,
               "confluent.topic.replication.factor":1
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

sleep 5

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 2


# [2020-10-30 08:40:08,284] ERROR Exception in RecordQueue thread (io.confluent.connect.oracle.cdc.util.RecordQueue)
# org.apache.kafka.connect.errors.ConnectException: Failed to subscribe to the redo log topic 'redo-log-topic' even after waiting PT1M. Verify that this redo log topic exists in the brokers at broker:9092, and that the redo log reading task is able to produce to that topic.
#         at io.confluent.connect.oracle.cdc.ChangeEventGenerator.subscribeToRedoLogTopic(ChangeEventGenerator.java:248)
#         at io.confluent.connect.oracle.cdc.ChangeEventGenerator.execute(ChangeEventGenerator.java:203)
#         at io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$1(RecordQueue.java:468)
#         at java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
