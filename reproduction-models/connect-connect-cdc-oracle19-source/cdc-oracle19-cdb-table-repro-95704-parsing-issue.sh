#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table.repro-95704-parsing-issue.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
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
sleep 10

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
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto",

               "behavior.on.dictionary.mismatch":"log",
               "behavior.on.unparsable.statement":"log",
               "lob.topic.name.template": "${tableName}-${columnName}-testing-new",
               "record.buffer.mode": "connector"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

log "Waiting 20s for connector to read existing data"
sleep 20


docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
  insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Rica3', 'Blaisde32', 'rblaisdell30@rambler.ru\', 'Female3', 'bronze3', utl_raw.cast_to_raw('Universal optimal hierarchy3'));
  exit;
EOF

# [2022-03-29 12:52:18,622] WARN [cdc-oracle-source-cdb|task-1|changeEvent] Encountered unparsable statement: insert into "C##MYUSER"."CUSTOMERS"("ID","FIRST_NAME","LAST_NAME","EMAIL","GENDER","CLUB_STATUS","COMMENTS","CREATE_TS","UPDATE_TS","COUNTRY") values ('63','Rica3','Blaisde32','rblaisdell30@rambler.ru\','Female3','bronze3',EMPTY_BLOB(),TO_TIMESTAMP('2022-03-29 12:52:14.189'),TO_TIMESTAMP('2022-03-29 12:52:14.000'),NULL);. Logging and continuing (io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter:341)
# [2022-03-29 12:52:18,629] WARN [cdc-oracle-source-cdb|task-1|changeEvent] Encountered unparsable statement: update "C##MYUSER"."CUSTOMERS" set "COMMENTS" = HEXTORAW('556e6976657273616c206f7074696d616c2068696572617263687933') where "ID" = '63' and "FIRST_NAME" = 'Rica3' and "LAST_NAME" = 'Blaisde32' and "EMAIL" = 'rblaisdell30@rambler.ru\' and "GENDER" = 'Female3' and "CLUB_STATUS" = 'bronze3' and "CREATE_TS" = TO_TIMESTAMP('2022-03-29 12:52:14.189') and "UPDATE_TS" = TO_TIMESTAMP('2022-03-29 12:52:14.000') and "COUNTRY" IS NULL and ROWID = 'AAAR32AAHAAAAFbAAA';. Logging and continuing (io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter:341)

# [2022-03-29 12:52:19,273] ERROR [cdc-oracle-source-cdb|task-1] WorkerSourceTask{id=cdc-oracle-source-cdb-1} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Error while polling for records
#         at io.confluent.connect.oracle.cdc.util.RecordQueue.poll(RecordQueue.java:372)
#         at io.confluent.connect.oracle.cdc.OracleCdcSourceTask.poll(OracleCdcSourceTask.java:493)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:308)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Exception processing LOB column
#         at io.confluent.connect.oracle.cdc.record.OracleLobRecordConverter.convert(OracleLobRecordConverter.java:199)
#         at io.confluent.connect.oracle.cdc.ChangeEventGenerator.processSingleRecord(ChangeEventGenerator.java:511)
#         at io.confluent.connect.oracle.cdc.ChangeEventGenerator.lambda$doGenerateChangeEvent$2(ChangeEventGenerator.java:419)
#         at java.base/java.util.stream.ReferencePipeline$3$1.accept(ReferencePipeline.java:195)
#         at java.base/java.util.Spliterators$ArraySpliterator.forEachRemaining(Spliterators.java:948)
#         at java.base/java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:484)
#         at java.base/java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:474)
#         at java.base/java.util.stream.ReduceOps$ReduceOp.evaluateSequential(ReduceOps.java:913)
#         at java.base/java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)
#         at java.base/java.util.stream.ReferencePipeline.collect(ReferencePipeline.java:578)
#         at io.confluent.connect.oracle.cdc.ChangeEventGenerator.doGenerateChangeEvent(ChangeEventGenerator.java:421)
#         at io.confluent.connect.oracle.cdc.ChangeEventGenerator.execute(ChangeEventGenerator.java:221)
#         at io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$0(RecordQueue.java:465)
#         at java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)
#         ... 3 more
# Caused by: net.sf.jsqlparser.JSQLParserException
#         at net.sf.jsqlparser.parser.CCJSqlParserUtil.parse(CCJSqlParserUtil.java:51)
#         at net.sf.jsqlparser.parser.CCJSqlParserUtil.parse(CCJSqlParserUtil.java:40)
#         at io.confluent.connect.oracle.cdc.record.OracleLobRecordConverter.convertLobUpdate(OracleLobRecordConverter.java:270)
#         at io.confluent.connect.oracle.cdc.record.OracleLobRecordConverter.convert(OracleLobRecordConverter.java:99)
#         ... 16 more
# Caused by: net.sf.jsqlparser.parser.ParseException: Encountered unexpected token: "Female3" <S_IDENTIFIER>
#     at line 1, column 250.

# Was expecting one of:

#     "&"
#     "&&"
#     "("
#     "::"
#     ";"
#     "<<"
#     ">>"
#     "AND"
#     "COLLATE"
#     "LIMIT"
#     "ORDER"
#     "RETURNING"
#     "["
#     "^"
#     "|"
#     <EOF>

#         at net.sf.jsqlparser.parser.CCJSqlParser.generateParseException(CCJSqlParser.java:22439)
#         at net.sf.jsqlparser.parser.CCJSqlParser.jj_consume_token(CCJSqlParser.java:22286)
#         at net.sf.jsqlparser.parser.CCJSqlParser.Statement(CCJSqlParser.java:85)
#         at net.sf.jsqlparser.parser.CCJSqlParserUtil.parse(CCJSqlParserUtil.java:49)
#         ... 19 more

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS"
set +e
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 1
set -e

log "Verifying topic redo-log-topic: there should be 9 records"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 9

log "🚚 If you're planning to inject more data, have a look at https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/README.md#note-on-redologrowfetchsize"
