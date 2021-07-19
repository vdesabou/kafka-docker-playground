#!/bin/bash
set -e

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-gss-exception.yml"

log "Java version used on connect:"
docker exec -i connect java -version

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

# https://serverfault.com/a/133631
log "Add connect kerberos principal"
docker exec -i kdc kadmin.local << EOF
addprinc -randkey connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 120days +allow_renewable connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 120days krbtgt/EXAMPLE.COM
modprinc -maxlife 120days connect/connect.kerberos-demo.local@EXAMPLE.COM
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

# With:

#  ticket_lifetime = 168h 0m 0s
#  renew_lifetime = 90d

# Forwardable Ticket true
# Forwarded Ticket false
# Proxiable Ticket false
# Proxy Ticket false
# Postdated Ticket false
# Renewable Ticket false
# Initial Ticket false
# Auth Time = Mon Jul 19 11:46:13 GMT 2021
# Start Time = Mon Jul 19 11:46:14 GMT 2021
# End Time = Tue Jul 20 11:46:13 GMT 2021    <--------- One day because of https://stackoverflow.com/questions/38555244/how-do-you-set-the-kerberos-ticket-lifetime-from-java ?
# Renew Till = null
# Client Addresses  Null
# >>> KrbApReq: APOptions are 00100000 00000000 00000000 00000000
# >>> EType: sun.security.krb5.internal.crypto.Aes256CtsHmacSha1EType
# Krb5Context setting mySeqNumber to: 750598037
# Created InitSecContextToken:


# [root@connect appuser]# klist -f
# Ticket cache: FILE:/tmp/krb5cc_0
# Default principal: connect/connect.kerberos-demo.local@EXAMPLE.COM

# Valid starting     Expires            Service principal
# 07/19/21 11:49:51  07/20/21 11:49:51  krbtgt/EXAMPLE.COM@EXAMPLE.COM
#         renew until 07/26/21 11:49:51, Flags: FRI




# With:

#  ticket_lifetime = 60
#  renew_lifetime = 90d

# or :

#  ticket_lifetime = 60
#  renew_lifetime = 10d


# Forwardable Ticket true
# Forwarded Ticket false
# Proxiable Ticket false
# Proxy Ticket false
# Postdated Ticket false
# Renewable Ticket false
# Initial Ticket false
# Auth Time = Mon Jul 19 12:00:59 GMT 2021
# Start Time = Mon Jul 19 12:01:00 GMT 2021
# End Time = Tue Jul 20 12:00:59 GMT 2021 --------> 1 day
# Renew Till = null
# Client Addresses  Null


# With:

#  ticket_lifetime = 60
#  renew_lifetime = 604800


# Forwardable Ticket true
# Forwarded Ticket false
# Proxiable Ticket false
# Proxy Ticket false
# Postdated Ticket false
# Renewable Ticket false
# Initial Ticket false
# Auth Time = Mon Jul 19 12:57:45 GMT 2021
# Start Time = Mon Jul 19 12:57:49 GMT 2021
# End Time = Mon Jul 19 12:59:45 GMT 2021
# Renew Till = null
# Client Addresses  Null
# >>> KrbApReq: APOptions are 00100000 00000000 00000000 00000000