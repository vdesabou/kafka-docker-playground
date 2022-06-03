#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

# required to make utils.sh script being able to work, do not remove:
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-105528-npe-when-oracle-is-down.yml"


docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.repro-105528-npe-when-oracle-is-down.yml" down -v --remove-orphans
log "Starting up oracle container to get ojdbc8.jar and aqapi.jar"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.repro-105528-npe-when-oracle-is-down.yml" up -d oracle


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

if [ ! -f aqapi.jar ]
then
     docker cp oracle:/opt/oracle/product/19c/dbhome_1/rdbms/jlib/aqapi.jar aqapi.jar
fi
if [ ! -f ojdbc8.jar ]
then
     docker cp oracle:/opt/oracle/product/19c/dbhome_1/jdbc/lib/ojdbc8.jar ojdbc8.jar
fi
if [ ! -f jta-1.1.jar ]
then
     # NoClassDefFoundError: javax/transaction/Synchronization
     wget https://repo1.maven.org/maven2/javax/transaction/jta/1.1/jta-1.1.jar
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.repro-105528-npe-when-oracle-is-down.yml" up -d

../../scripts/wait-for-connect-and-controlcenter.sh


# https://github.com/monodot/oracle-aq-demo
log "Grant all permissions to C##MYUSER"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA

GRANT EXECUTE ON SYS.DBMS_AQ to C##MYUSER;
GRANT RESOURCE TO C##MYUSER;
GRANT CONNECT TO C##MYUSER;
GRANT EXECUTE ANY PROCEDURE TO C##MYUSER;
GRANT aq_administrator_role TO C##MYUSER;
GRANT aq_user_role TO C##MYUSER;
GRANT EXECUTE ON dbms_aqadm TO C##MYUSER;
GRANT EXECUTE ON dbms_aq TO C##MYUSER;
GRANT EXECUTE ON dbms_aqin TO C##MYUSER;

  exit;
EOF

log "Create JMS QUEUE called PLAYGROUND"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF

EXEC dbms_aqadm.create_queue_table('PLAYGROUNDTABLE', 'SYS.AQ\$_JMS_TEXT_MESSAGE')
EXEC dbms_aqadm.create_queue('PLAYGROUND','PLAYGROUNDTABLE')
EXEC dbms_aqadm.start_queue('PLAYGROUND')

  exit;
EOF

log "Check Queues"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA


select owner, table_name from dba_all_tables where table_name = 'QT';
select owner, table_name from dba_all_tables where table_name = 'FOOQUEUETABLE';

  exit;
EOF

log "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message 1
This is my message 2
EOF



log "Creating JMS Oracle AQ sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
               "tasks.max": "1",
               "topics": "sink-messages",

               "db_url": "jdbc:oracle:thin:@oracle:1521/ORCLCDB",
               "java.naming.factory.initial": "oracle.jms.AQjmsInitialContextFactory",
               "java.naming.provider.url": "jdbc:oracle:thin:@oracle:1521/ORCLCDB",
               "java.naming.security.credentials": "mypassword",
               "java.naming.security.principal": "C##MYUSER",
               "jms.destination.name": "PLAYGROUND",
               "jms.destination.type": "queue",
               "jms.message.format": "string",
               "jndi.connection.factory": "javax.jms.XAQueueConnectionFactory",

               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-oracle-sink/config | jq .


sleep 10

log "Check table PLAYGROUNDTABLE"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB > /tmp/result.log  2>&1 <<-EOF

select * from PLAYGROUNDTABLE;

  exit;
EOF
cat /tmp/result.log
grep "This is my message 1" /tmp/result.log


log "restart oracle"
docker restart oracle

sleep 60

log "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message 3
This is my message 4
EOF


# [2022-06-03 10:10:31,971] ERROR [jms-oracle-sink|task-0] WorkerSinkTask{id=jms-oracle-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:750)
# Caused by: java.lang.NullPointerException
#         at oracle.jms.AQjmsSession.getDriver(AQjmsSession.java:7702)
#         at oracle.jms.AQjmsProducer.send(AQjmsProducer.java:786)
#         at oracle.jms.AQjmsProducer.send(AQjmsProducer.java:558)
#         at io.confluent.connect.jms.BaseJmsSinkTask.send(BaseJmsSinkTask.java:174)
#         at java.util.stream.ForEachOps$ForEachOp$OfRef.accept(ForEachOps.java:183)
#         at java.util.stream.ReferencePipeline$2$1.accept(ReferencePipeline.java:175)
#         at java.util.ArrayList$ArrayListSpliterator.forEachRemaining(ArrayList.java:1384)
#         at java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:482)
#         at java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:472)
#         at java.util.stream.ForEachOps$ForEachOp.evaluateSequential(ForEachOps.java:150)
#         at java.util.stream.ForEachOps$ForEachOp$OfRef.evaluateSequential(ForEachOps.java:173)
#         at java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)
#         at java.util.stream.ReferencePipeline.forEach(ReferencePipeline.java:485)
#         at io.confluent.connect.jms.BaseJmsSinkTask.put(BaseJmsSinkTask.java:111)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         ... 10 more
