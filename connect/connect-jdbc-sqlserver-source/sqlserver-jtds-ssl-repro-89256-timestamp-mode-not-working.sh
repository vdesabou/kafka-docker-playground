#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.0"; then
    if [[ "$TAG" != *ubi8 ]]
    then
        logwarn "Known issue ! JDBC Source and Sink with MS SQL and JTDS driver does not work with SSL, see https://github.com/vdesabou/kafka-docker-playground/issues/1107"
        # known_issue https://github.com/vdesabou/kafka-docker-playground/issues/1107
        exit 111
    fi
fi

cd ${DIR}/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

rm -f mssql.pem
rm -f mssql.key

#https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-security?view=sql-server-ver15
#https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-encrypted-connections?view=sql-server-ver15&preserve-view=true#client-initiated-encryption
log "Create a self-signed certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=sqlserver' -keyout /tmp/mssql.key -out /tmp/mssql.pem -days 365

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

log "Creating JKS from pem files"
rm -f truststore.jks
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -importcert -alias MSSQLCACert -noprompt -file /tmp/mssql.pem -keystore /tmp/truststore.jks -storepass confluent

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds-ssl.repro-89256-timestamp-mode-not-working.yml"


log "Load inventory.sql to SQL Server"
cat inventory-repro-89256-timestamp-mode-not-working.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


log "Creating JDBC SQL Server (with JTDS driver) source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433/testDB;ssl=require",
               "connection.user": "sa",
               "connection.password": "Password!",
               "table.whitelist": "customers",
               "mode": "timestamp",
               "timestamp.delay.interval.ms": "0",
               "timestamp.column.name": "last_update",
               "topic.prefix": "sqlserver-",
               "validate.non.null":"false",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-source-ssl/config | jq .


# [2022-01-24 09:26:19,830] ERROR [sqlserver-source-ssl|task-0] Failed to run query for table: TimestampTableQuerier{table="testDB"."dbo"."customers", query='null', topicPrefix='sqlserver-', timestampColumns=[last_update]} (io.confluent.connect.jdbc.source.JdbcSourceTask:423)
# java.lang.ClassCastException: class java.lang.String cannot be cast to class java.sql.Timestamp (java.lang.String is in module java.base of loader 'bootstrap'; java.sql.Timestamp is in module java.sql of loader 'platform')
#         at io.confluent.connect.jdbc.source.TimestampIncrementingCriteria.extractOffsetTimestamp(TimestampIncrementingCriteria.java:229)
#         at io.confluent.connect.jdbc.source.TimestampIncrementingCriteria.extractValues(TimestampIncrementingCriteria.java:198)
#         at io.confluent.connect.jdbc.source.TimestampTableQuerier.doExtractRecord(TimestampTableQuerier.java:148)
#         at io.confluent.connect.jdbc.source.TimestampTableQuerier.next(TimestampTableQuerier.java:98)
#         at io.confluent.connect.jdbc.source.JdbcSourceTask.poll(JdbcSourceTask.java:383)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:291)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:248)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email,last_update) VALUES ('Pam','Thomas','pam@office.com', GETDATE());
GO
EOF

log "Verifying topic sqlserver-customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sqlserver-customers --from-beginning --max-messages 5
