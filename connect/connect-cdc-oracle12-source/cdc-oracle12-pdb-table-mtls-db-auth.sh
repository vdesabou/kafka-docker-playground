#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# THIS TEST IS SKIPPED AS NOT WORKING, see #833 Oracle CDC: mTLS with DB authentication cannot work with PDB #833 https://github.com/vdesabou/kafka-docker-playground/issues/833

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
          ./buildContainerImage.sh -v 12.2.0.1 -e
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

# required to make utils.sh script being able to work, do not remove:
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.pdb-table.yml"
log "Starting up oracle container to get generated cert from oracle server wallet"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.pdb-table-mtls.yml" up -d oracle

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

log "Grant select on CUSTOMERS table"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
     ALTER SESSION SET CONTAINER=ORCLPDB1;
     GRANT select on CUSTOMERS TO C##MYUSER;
EOF

log "Setting up SSL on oracle server..."
# https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf
log "Create a wallet for the test CA"

docker exec oracle bash -c "orapki wallet create -wallet /tmp/root -pwd WalletPasswd123"
# Add a self-signed certificate to the wallet
docker exec oracle bash -c "orapki wallet add -wallet /tmp/root -dn CN=root_test,C=US -keysize 2048 -self_signed -validity 3650 -pwd WalletPasswd123"
# Export the certificate
docker exec oracle bash -c "orapki wallet export -wallet /tmp/root -dn CN=root_test,C=US -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"

log "Create a wallet for the Oracle server"

# Create an empty wallet with auto login enabled
docker exec oracle bash -c "orapki wallet create -wallet /tmp/server -pwd WalletPasswd123 -auto_login"
# Add a user In the wallet (a new pair of private/public keys is created)
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -keysize 2048"
# Export the certificate request to a file
docker exec oracle bash -c "orapki wallet export -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -request /tmp/server/creq.txt"
# Using the test CA, sign the certificate request
docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/server/creq.txt -cert /tmp/server/cert.txt -validity 3650 -pwd WalletPasswd123"
log "You now have the following files under the /tmp/server directory"
docker exec oracle ls /tmp/server
# View the signed certificate:
docker exec oracle bash -c "orapki cert display -cert /tmp/server/cert.txt -complete"
# Add the test CA's trusted certificate to the wallet
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -trusted_cert -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"
# add the user certificate to the wallet:
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -user_cert -cert /tmp/server/cert.txt -pwd WalletPasswd123"

cd ${DIR}/mtls
# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+w .
log "Create a JKS keystore"
# Create a new private/public key pair for 'CN=connect,C=US'
rm -f keystore.jks
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -genkey -alias testclient -dname 'CN=connect,C=US' -storepass 'welcome123' -storetype JKS -keystore /tmp/keystore.jks -keyalg RSA

# Generate a CSR (Certificate Signing Request):
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -certreq -alias testclient -file /tmp/csr.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Sign the client certificate using the test CA (root)
docker cp csr.txt oracle:/tmp/csr.txt
docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/csr.txt -cert /tmp/cert.txt -validity 3650 -pwd WalletPasswd123"
# import the test CA's certificate:
docker cp oracle:/tmp/root/b64certificate.txt b64certificate.txt
# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+w .
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -noprompt -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Import the signed certificate
docker cp oracle:/tmp/cert.txt cert.txt
# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+w .
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -alias testclient -file /tmp/cert.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
log "Displaying keystore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/keystore.jks -storepass 'welcome123' -v

log "Create a JKS truststore"
rm -f truststore.jks
docker cp oracle:/tmp/root/b64certificate.txt b64certificate.txt
# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+w .
# We import the test CA certificate
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
log "Displaying truststore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/truststore.jks -storepass 'welcome123' -v

cd ${DIR}

log "Alter user 'C##MYUSER' in order to be identified as 'CN=connect,C=US'"
docker exec -i oracle sqlplus sys/Admin123@//localhost:1521/ORCLCDB as sysdba <<- EOF
	ALTER USER C##MYUSER IDENTIFIED EXTERNALLY AS 'CN=connect,C=US';
	exit;
EOF

log "Update listener.ora, sqlnet.ora and tnsnames.ora"
docker cp ${PWD}/mtls/listener.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/listener.ora
docker cp ${PWD}/mtls/sqlnet.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/sqlnet.ora
docker cp ${PWD}/mtls/tnsnames.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/tnsnames.ora

docker exec -i oracle lsnrctl << EOF
reload
stop
start
EOF

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.pdb-table-mtls.yml" up -d

../../scripts/wait-for-connect-and-controlcenter.sh

docker exec connect kafka-topics --create --topic redo-log-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1 --config cleanup.policy=delete --config retention.ms=120960000
log "redo-log-topic is created"

sleep 15

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
               "oracle.port": 1532,
               "oracle.sid": "ORCLCDB",
               "oracle.pdb.name": "ORCLPDB1",
               "oracle.ssl.truststore.file": "/tmp/truststore.jks",
               "oracle.ssl.truststore.password": "welcome123",
               "oracle.connection.javax.net.ssl.keyStore": "/tmp/keystore.jks",
               "oracle.connection.javax.net.ssl.keyStorePassword": "welcome123",
               "oracle.connection.oracle.net.authentication_services": "(TCPS)",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": "ORCLPDB1[.].*[.]CUSTOMERS",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "connection.pool.max.size": 20,
               "confluent.topic.replication.factor":1
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-pdb/config | jq .

sleep 5

# FIXTHIS:
# [2021-04-12 13:33:52,281] ERROR WorkerSourceTask{id=cdc-oracle-source-pdb-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Failed on attempt 1 of 32768 to snapshot table schema from  at jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=oracle)(PORT=1532))(CONNECT_DATA=(SID=ORCLCDB))) (pool=oracle-cdc-source:cdc-oracle-source-pdb-0): ORA-65053: A global user cannot change the container in the session.

#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:423)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:368)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.snapshotTableSchema(OracleDatabase.java:466)
#         at io.confluent.connect.oracle.cdc.OracleCdcSourceTask.lambda$start$4(OracleCdcSourceTask.java:235)
#         at java.base/java.util.stream.Collectors.lambda$uniqKeysMapAccumulator$1(Collectors.java:178)
#         at java.base/java.util.stream.ReduceOps$3ReducingSink.accept(ReduceOps.java:169)
#         at java.base/java.util.stream.ReferencePipeline$2$1.accept(ReferencePipeline.java:177)
#         at java.base/java.util.HashMap$KeySpliterator.forEachRemaining(HashMap.java:1603)
#         at java.base/java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:484)
#         at java.base/java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:474)
#         at java.base/java.util.stream.ReduceOps$ReduceOp.evaluateSequential(ReduceOps.java:913)
#         at java.base/java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)
#         at java.base/java.util.stream.ReferencePipeline.collect(ReferencePipeline.java:578)
#         at io.confluent.connect.oracle.cdc.OracleCdcSourceTask.start(OracleCdcSourceTask.java:234)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: java.sql.SQLException: ORA-65053: A global user cannot change the container in the session.

#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:509)
#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:461)
#         at oracle.jdbc.driver.T4C8Oall.processError(T4C8Oall.java:1104)
#         at oracle.jdbc.driver.T4CTTIfun.receive(T4CTTIfun.java:550)
#         at oracle.jdbc.driver.T4CTTIfun.doRPC(T4CTTIfun.java:268)
#         at oracle.jdbc.driver.T4C8Oall.doOALL(T4C8Oall.java:655)
#         at oracle.jdbc.driver.T4CCallableStatement.doOall8(T4CCallableStatement.java:265)
#         at oracle.jdbc.driver.T4CCallableStatement.doOall8(T4CCallableStatement.java:86)
#         at oracle.jdbc.driver.T4CCallableStatement.executeForRows(T4CCallableStatement.java:965)
#         at oracle.jdbc.driver.OracleStatement.doExecuteWithTimeout(OracleStatement.java:1205)
#         at oracle.jdbc.driver.OraclePreparedStatement.executeInternal(OraclePreparedStatement.java:3666)
#         at oracle.jdbc.driver.T4CCallableStatement.executeInternal(T4CCallableStatement.java:1358)
#         at oracle.jdbc.driver.OraclePreparedStatement.execute(OraclePreparedStatement.java:3778)
#         at oracle.jdbc.driver.OracleCallableStatement.execute(OracleCallableStatement.java:4251)
#         at oracle.jdbc.driver.OraclePreparedStatementWrapper.execute(OraclePreparedStatementWrapper.java:1081)
#         at oracle.ucp.jdbc.proxy.oracle$1ucp$1jdbc$1proxy$1oracle$1StatementProxy$2oracle$1jdbc$1internal$1OracleCallableStatement$$$Proxy.execute(Unknown Source)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.switchContainer(OracleDatabase.java:591)
#         at io.confluent.connect.oracle.cdc.OracleDatabase$PdbContext.<init>(OracleDatabase.java:643)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.pdbContext(OracleDatabase.java:611)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.doSnapshotTableSchema(OracleDatabase.java:477)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.lambda$snapshotTableSchema$5(OracleDatabase.java:469)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         ... 21 more
# Caused by: Error : 65053, Position : 0, Sql = ALTER SESSION SET CONTAINER=ORCLPDB1, OriginalSql = ALTER SESSION SET CONTAINER=ORCLPDB1, Error Msg = ORA-65053: A global user cannot change the container in the session.

#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:513)
#         ... 42 more

log "Verifying topic ORCLPDB1.C__MYUSER.CUSTOMERS"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLPDB1.C__MYUSER.CUSTOMERS --from-beginning --max-messages 2
