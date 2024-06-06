#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/hadoop-2.7.4.tar.gz ]
then
     log "Getting hadoop-2.7.4.tar.gz"
     wget -q https://archive.apache.org/dist/hadoop/common/hadoop-2.7.4/hadoop-2.7.4.tar.gz > /dev/null 2>&1
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.ha-kerberos.yml"

log "Wait 80 seconds while hadoop is installing"
sleep 80

log "namenode1 becomes primary"
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local;hdfs haadmin -transitionToActive nn1"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -chmod 777  /"

log "Add connect kerberos principal"
docker exec -i krb5 kadmin.local << EOF
addprinc -randkey connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days +allow_renewable connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days krbtgt/EXAMPLE.COM
modprinc -maxlife 11days connect/connect.kerberos-demo.local@EXAMPLE.COM
ktadd -k /connect.keytab connect/connect.kerberos-demo.local@EXAMPLE.COM
listprincs
EOF

log "Copy connect.keytab to connect container /tmp/sshuser.keytab"
docker cp krb5:/connect.keytab .
docker cp connect.keytab connect:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/connect.keytab
fi

log "Creating HDFS Sink connector"
playground connector create-or-update --connector hdfs2-sink-ha-kerberos  << EOF
{
  "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
  "tasks.max":"1",
  "topics":"test_hdfs",
  "store.url":"hdfs://sh",
  "flush.size":"3",
  "hadoop.conf.dir":"/opt/hadoop/etc/hadoop/",
  "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
  "rotate.interval.ms":"120000",
  "logs.dir":"/logs",
  "hdfs.authentication.kerberos": "true",
  "connect.hdfs.principal": "connect/connect.kerberos-demo.local@EXAMPLE.COM",
  "connect.hdfs.keytab": "/tmp/connect.keytab",
  "hdfs.namenode.principal": "nn/namenode1.kerberos-demo.local@EXAMPLE.COM",
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
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -ls /topics/test_hdfs/partition=0"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/partition=0/test_hdfs+0+0000000000+0000000002.avro /tmp"
docker cp namenode1:/tmp/test_hdfs+0+0000000000+0000000002.avro /tmp/

playground  tools read-avro-file --file /tmp/test_hdfs+0+0000000000+0000000002.avro
