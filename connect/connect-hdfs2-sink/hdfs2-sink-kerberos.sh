#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.kerberos.yml"

sleep 20

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
set +e
docker exec hadoop bash -c "echo password | kinit && /usr/local/hadoop/bin/hdfs dfs -chmod 777  /"
if [ $? -ne 0 ]
then
  playground container restart --container hadoop

  sleep 30

  docker exec hadoop bash -c "echo password | kinit && /usr/local/hadoop/bin/hdfs dfs -chmod 777  /"
  if [ $? -ne 0 ]
  then
    logerror "failed to start hadoop !"
    exit 1
  fi
fi
set -e

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
playground connector create-or-update --connector hdfs-sink-kerberos << EOF
{
  "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
  "tasks.max":"1",
  "topics":"test_hdfs",
  "store.url":"hdfs://hadoop.kerberos-demo.local:9000",
  "flush.size":"3",
  "hadoop.conf.dir":"/etc/hadoop/",
  "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
  "rotate.interval.ms":"120000",
  "logs.dir":"/logs",
  "hdfs.authentication.kerberos": "true",
  "kerberos.ticket.renew.period.ms": "60000",
  "connect.hdfs.principal": "connect/connect.kerberos-demo.local@EXAMPLE.COM",
  "connect.hdfs.keytab": "/tmp/connect.keytab",
  "hdfs.namenode.principal": "nn/hadoop.kerberos-demo.local@EXAMPLE.COM",
  "key.converter":"org.apache.kafka.connect.storage.StringConverter",
  "value.converter":"io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url":"http://schema-registry:8081",
  "schema.compatibility":"BACKWARD"
}
EOF

log "Sending messages to topic test_hdfs"
playground topic produce -t test_hdfs --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

sleep 10

log "Listing content of /topics/test_hdfs/partition=0 in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /topics/test_hdfs/partition=0"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/partition=0/test_hdfs+0+0000000000+0000000002.avro /tmp"
docker cp hadoop:/tmp/test_hdfs+0+0000000000+0000000002.avro /tmp/

docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000002.avro

# renew ticket manually:
# docker exec connect kinit -kt /tmp/connect.keytab connect/connect.kerberos-demo.local