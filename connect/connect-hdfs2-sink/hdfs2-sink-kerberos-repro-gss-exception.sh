#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.kerberos.yml"

sleep 30

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.hdfs \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "DEBUG"
}'

curl --request PUT \
  --url http://localhost:8083/admin/loggers/org.apache.hadoop.security \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "DEBUG"
}'

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec hadoop bash -c "echo password | kinit && /usr/local/hadoop/bin/hdfs dfs -chmod 777  /"

for((i=0;i<10;i++)); do

     log "Add connect$i kerberos principal"

docker exec -i kdc kadmin.local << EOF
addprinc -randkey connect$i/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days +allow_renewable connect$i/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days krbtgt/EXAMPLE.COM
modprinc -maxlife 11days connect$i/connect.kerberos-demo.local@EXAMPLE.COM
ktadd -k /connect$i.keytab connect$i/connect.kerberos-demo.local@EXAMPLE.COM
listprincs
EOF

     log "Copy connect$i.keytab to connect container /tmp/sshuser.keytab"
     docker cp kdc:/connect$i.keytab .
     docker cp connect$i.keytab connect:/tmp/connect$i.keytab
     if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
     then
          docker exec -u 0 connect chown appuser:appuser /tmp/connect$i.keytab
     fi

     log "Creating HDFS Sink connector $i"

     LOG_DIR="/logs$i"
     KEYTAB="/tmp/connect$i.keytab"
     TOPIC="test_hdfs$i"
     PRINCIPAL="connect$i/connect.kerberos-demo.local@EXAMPLE.COM"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
                    "tasks.max":"1",
                    "topics":"'"$TOPIC"'",
                    "store.url":"hdfs://hadoop.kerberos-demo.local:9000",
                    "flush.size":"3",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
                    "partition.field.name":"f1",
                    "rotate.interval.ms":"120000",
                    "logs.dir": "'"$LOG_DIR"'",
                    "hdfs.authentication.kerberos": "true",
                    "kerberos.ticket.renew.period.ms": "500",
                    "connect.hdfs.principal": "'"$PRINCIPAL"'",
                    "connect.hdfs.keytab": "'"$KEYTAB"'",
                    "hdfs.namenode.principal": "nn/_HOST@EXAMPLE.COM",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs-sink-kerberos$i/config | jq .

     log "Sending messages to topic test_hdfs$i"
     seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs$i --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
done

# log "Calling kinit manually"
# docker exec connect kinit -kt /tmp/connect.keytab connect/connect.kerberos-demo.local
# docker exec connect klist


# [2021-07-09 13:30:46,435] INFO Hadoop namenode principal: nn/connect.kerberos-demo.local@EXAMPLE.COM (io.confluent.connect.hdfs.DataWriter)
# [2021-07-09 13:30:46,439] DEBUG unwrapping token of length:492 (org.apache.hadoop.security.SaslRpcClient)
# [2021-07-09 13:30:46,446] DEBUG hadoop login (org.apache.hadoop.security.UserGroupInformation)
# [2021-07-09 13:30:46,446] DEBUG hadoop login commit (org.apache.hadoop.security.UserGroupInformation)
# [2021-07-09 13:30:46,446] DEBUG using kerberos user:connect4/connect.kerberos-demo.local@EXAMPLE.COM (org.apache.hadoop.security.UserGroupInformation)
# [2021-07-09 13:30:46,446] DEBUG Using user: "connect4/connect.kerberos-demo.local@EXAMPLE.COM" with name connect4/connect.kerberos-demo.local@EXAMPLE.COM (org.apache.hadoop.security.UserGroupInformation)
# [2021-07-09 13:30:46,446] DEBUG User entry: "connect4/connect.kerberos-demo.local@EXAMPLE.COM" (org.apache.hadoop.security.UserGroupInformation)

# [2021-07-09 13:32:30,830] WARN Exception encountered while connecting to the server  (org.apache.hadoop.ipc.Client)
# javax.security.sasl.SaslException: GSS initiate failed [Caused by GSSException: No valid credentials provided (Mechanism level: Failed to find any Kerberos tgt)]
# 	at jdk.security.jgss/com.sun.security.sasl.gsskerb.GssKrb5Client.evaluateChallenge(GssKrb5Client.java:222)
# 	at org.apache.hadoop.security.SaslRpcClient.saslConnect(SaslRpcClient.java:407)
# 	at org.apache.hadoop.ipc.Client$Connection.setupSaslConnection(Client.java:629)
# 	at org.apache.hadoop.ipc.Client$Connection.access$2200(Client.java:423)
# 	at org.apache.hadoop.ipc.Client$Connection$2.run(Client.java:824)
# 	at org.apache.hadoop.ipc.Client$Connection$2.run(Client.java:820)
# 	at java.base/java.security.AccessController.doPrivileged(Native Method)
# 	at java.base/javax.security.auth.Subject.doAs(Subject.java:423)
# 	at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1926)
# 	at org.apache.hadoop.ipc.Client$Connection.setupIOstreams(Client.java:819)
# 	at org.apache.hadoop.ipc.Client$Connection.access$3700(Client.java:423)
# 	at org.apache.hadoop.ipc.Client.getConnection(Client.java:1610)
# 	at org.apache.hadoop.ipc.Client.call(Client.java:1441)
# 	at org.apache.hadoop.ipc.Client.call(Client.java:1394)
# 	at org.apache.hadoop.ipc.ProtobufRpcEngine$Invoker.invoke(ProtobufRpcEngine.java:232)
# 	at org.apache.hadoop.ipc.ProtobufRpcEngine$Invoker.invoke(ProtobufRpcEngine.java:118)
# 	at com.sun.proxy.$Proxy53.renewLease(Unknown Source)
# 	at org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolTranslatorPB.renewLease(ClientNamenodeProtocolTranslatorPB.java:617)
# 	at jdk.internal.reflect.GeneratedMethodAccessor32.invoke(Unknown Source)
# 	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
# 	at java.base/java.lang.reflect.Method.invoke(Method.java:566)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler.invokeMethod(RetryInvocationHandler.java:422)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invokeMethod(RetryInvocationHandler.java:165)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invoke(RetryInvocationHandler.java:157)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invokeOnce(RetryInvocationHandler.java:95)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler.invoke(RetryInvocationHandler.java:359)
# 	at com.sun.proxy.$Proxy54.renewLease(Unknown Source)
# 	at org.apache.hadoop.hdfs.DFSClient.renewLease(DFSClient.java:578)
# 	at org.apache.hadoop.hdfs.client.impl.LeaseRenewer.renew(LeaseRenewer.java:396)
# 	at org.apache.hadoop.hdfs.client.impl.LeaseRenewer.run(LeaseRenewer.java:416)
# 	at org.apache.hadoop.hdfs.client.impl.LeaseRenewer.access$600(LeaseRenewer.java:76)
# 	at org.apache.hadoop.hdfs.client.impl.LeaseRenewer$1.run(LeaseRenewer.java:308)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: GSSException: No valid credentials provided (Mechanism level: Failed to find any Kerberos tgt)
# 	at java.security.jgss/sun.security.jgss.krb5.Krb5InitCredential.getInstance(Krb5InitCredential.java:162)
# 	at java.security.jgss/sun.security.jgss.krb5.Krb5MechFactory.getCredentialElement(Krb5MechFactory.java:126)
# 	at java.security.jgss/sun.security.jgss.krb5.Krb5MechFactory.getMechanismContext(Krb5MechFactory.java:193)
# 	at java.security.jgss/sun.security.jgss.GSSManagerImpl.getMechanismContext(GSSManagerImpl.java:218)
# 	at java.security.jgss/sun.security.jgss.GSSContextImpl.initSecContext(GSSContextImpl.java:230)
# 	at java.security.jgss/sun.security.jgss.GSSContextImpl.initSecContext(GSSContextImpl.java:196)
# 	at jdk.security.jgss/com.sun.security.sasl.gsskerb.GssKrb5Client.evaluateChallenge(GssKrb5Client.java:203)
# 	... 32 more

exit 0

