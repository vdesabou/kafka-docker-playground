#!/bin/bash
set -e

export TAG="5.4.0-1-ubi8"
export CONNECTOR_TAG="10.0.6"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_gss_exception () {
     CONNECT_CONTAINER=connect
     MAX_WAIT=600
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for GSS exception to happen"
     docker container logs ${CONNECT_CONTAINER} > /tmp/out.txt 2>&1
     while [[ ! $(cat /tmp/out.txt) =~ "Failed to find any Kerberos tgt" ]]; do
          sleep 10
          docker container logs ${CONNECT_CONTAINER} > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in ${CONNECT_CONTAINER} container do not show 'Failed to find any Kerberos tgt' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
          # send requests
          seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
     done
     log "The problem has been reproduced !"
}

log "Forcing TAG 5.4.0-1-ubi8 in order to use OpenJDK Runtime Environment (Zulu 8.44.0.11-CA-linux64) (build 1.8.0_242-b20)"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-gss-exception.yml"

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

log "Add connect kerberos principal"
docker exec -i kdc kadmin.local << EOF
addprinc -randkey connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days +allow_renewable connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days krbtgt/EXAMPLE.COM
modprinc -maxlife 11days connect/connect.kerberos-demo.local@EXAMPLE.COM
ktadd -k /connect.keytab connect/connect.kerberos-demo.local@EXAMPLE.COM
listprincs
EOF

log "Copy connect.keytab to connect container /tmp/sshuser.keytab"
docker cp kdc:/connect.keytab .
docker cp connect.keytab connect:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/connect.keytab
fi

# log "Calling kinit manually"
# docker exec connect kinit -kt /tmp/connect.keytab connect/connect.kerberos-demo.local
# docker exec connect klist


log "Creating HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "store.url":"hdfs://hadoop.kerberos-demo.local:9000",
               "flush.size":"3",
               "hadoop.conf.dir":"/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "logs.dir":"/logs",
               "hdfs.authentication.kerberos": "true",
               "kerberos.ticket.renew.period.ms": "1000",
               "connect.hdfs.principal": "connect/connect.kerberos-demo.local@EXAMPLE.COM",
               "connect.hdfs.keytab": "/tmp/connect.keytab",
               "hdfs.namenode.principal": "nn/hadoop.kerberos-demo.local@EXAMPLE.COM",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs-sink-kerberos/config | jq .

log "Sending messages to topic test_hdfs"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /topics/test_hdfs in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /topics/test_hdfs"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/f1=value1/test_hdfs+0+0000000000+0000000000.avro /tmp"
docker cp hadoop:/tmp/test_hdfs+0+0000000000+0000000000.avro /tmp/

docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000000.avro

wait_for_gss_exception

# https://bugs.openjdk.java.net/browse/JDK-8186576 ????
# fixed normally in 8u242-b08, but https://bugs.openjdk.java.net/browse/JDK-8239188 says openjdk8u252
# we use here 1.8.0_242-b20

# Removed and destroyed the expired Ticket
# Destroyed KerberosTicket
# Found ticket for connect/connect.kerberos-demo.local@EXAMPLE.COM to go to nn/hadoop.kerberos-demo.local@EXAMPLE.COM expiring on Sat Jul 17 16:04:11 GMT 2021
# Removed and destroyed the expired Ticket
# Destroyed KerberosTicket

# [2021-07-17 15:52:19,203] WARN Failed to renew lease for [DFSClient_NONMAPREDUCE_-1471448326_56] for 291 seconds.  Will retry shortly ... (org.apache.hadoop.hdfs.LeaseRenewer)
# java.io.IOException: Failed on local exception: java.io.IOException: Couldn't setup connection for connect/connect.kerberos-demo.local@EXAMPLE.COM to hadoop.kerberos-demo.local/172.20.0.4:9000; Host Details : local host is: "connect.kerberos-demo.local/172.20.0.7"; destination host is: "hadoop.kerberos-demo.local":9000;
#         at org.apache.hadoop.net.NetUtils.wrapException(NetUtils.java:776)
#         at org.apache.hadoop.ipc.Client.call(Client.java:1479)
#         at org.apache.hadoop.ipc.Client.call(Client.java:1412)
#         at org.apache.hadoop.ipc.ProtobufRpcEngine$Invoker.invoke(ProtobufRpcEngine.java:229)
#         at com.sun.proxy.$Proxy49.renewLease(Unknown Source)
#         at org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolTranslatorPB.renewLease(ClientNamenodeProtocolTranslatorPB.java:590)
#         at sun.reflect.GeneratedMethodAccessor23.invoke(Unknown Source)
#         at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
#         at java.lang.reflect.Method.invoke(Method.java:498)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler.invokeMethod(RetryInvocationHandler.java:191)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler.invoke(RetryInvocationHandler.java:102)
#         at com.sun.proxy.$Proxy50.renewLease(Unknown Source)
#         at org.apache.hadoop.hdfs.DFSClient.renewLease(DFSClient.java:892)
#         at org.apache.hadoop.hdfs.LeaseRenewer.renew(LeaseRenewer.java:423)
#         at org.apache.hadoop.hdfs.LeaseRenewer.run(LeaseRenewer.java:448)
#         at org.apache.hadoop.hdfs.LeaseRenewer.access$700(LeaseRenewer.java:71)
#         at org.apache.hadoop.hdfs.LeaseRenewer$1.run(LeaseRenewer.java:304)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.io.IOException: Couldn't setup connection for connect/connect.kerberos-demo.local@EXAMPLE.COM to hadoop.kerberos-demo.local/172.20.0.4:9000
#         at org.apache.hadoop.ipc.Client$Connection$1.run(Client.java:679)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at javax.security.auth.Subject.doAs(Subject.java:422)
#         at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1698)
#         at org.apache.hadoop.ipc.Client$Connection.handleSaslConnectionFailure(Client.java:650)
#         at org.apache.hadoop.ipc.Client$Connection.setupIOstreams(Client.java:737)
#         at org.apache.hadoop.ipc.Client$Connection.access$2900(Client.java:375)
#         at org.apache.hadoop.ipc.Client.getConnection(Client.java:1528)
#         at org.apache.hadoop.ipc.Client.call(Client.java:1451)
#         ... 16 more
# Caused by: javax.security.sasl.SaslException: GSS initiate failed [Caused by GSSException: No valid credentials provided (Mechanism level: Failed to find any Kerberos tgt)]
#         at com.sun.security.sasl.gsskerb.GssKrb5Client.evaluateChallenge(GssKrb5Client.java:211)
#         at org.apache.hadoop.security.SaslRpcClient.saslConnect(SaslRpcClient.java:414)
#         at org.apache.hadoop.ipc.Client$Connection.setupSaslConnection(Client.java:560)
#         at org.apache.hadoop.ipc.Client$Connection.access$1900(Client.java:375)
#         at org.apache.hadoop.ipc.Client$Connection$2.run(Client.java:729)
#         at org.apache.hadoop.ipc.Client$Connection$2.run(Client.java:725)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at javax.security.auth.Subject.doAs(Subject.java:422)
#         at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1698)
#         at org.apache.hadoop.ipc.Client$Connection.setupIOstreams(Client.java:725)
#         ... 19 more
# Caused by: GSSException: No valid credentials provided (Mechanism level: Failed to find any Kerberos tgt)
#         at sun.security.jgss.krb5.Krb5InitCredential.getInstance(Krb5InitCredential.java:162)
#         at sun.security.jgss.krb5.Krb5MechFactory.getCredentialElement(Krb5MechFactory.java:122)
#         at sun.security.jgss.krb5.Krb5MechFactory.getMechanismContext(Krb5MechFactory.java:189)
#         at sun.security.jgss.GSSManagerImpl.getMechanismContext(GSSManagerImpl.java:224)
#         at sun.security.jgss.GSSContextImpl.initSecContext(GSSContextImpl.java:212)
#         at sun.security.jgss.GSSContextImpl.initSecContext(GSSContextImpl.java:179)
#         at com.sun.security.sasl.gsskerb.GssKrb5Client.evaluateChallenge(GssKrb5Client.java:192)
#         ... 28 more