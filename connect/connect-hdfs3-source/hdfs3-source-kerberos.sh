#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.kerberos.yml"

sleep 20

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
set +e
docker exec hadoop bash -c "echo password | kinit && /usr/local/hadoop/bin/hdfs dfs -chmod 777  /"
if [ $? -ne 0 ]
then
  playground container restart --container hadoop

  sleep 20

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

log "Creating HDFS Sink connector"
playground connector create-or-update --connector hdfs3-sink << EOF
{
  "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
  "tasks.max":"1",
  "topics":"test_hdfs",
  "store.url":"hdfs://hadoop.kerberos-demo.local:9000",
  "flush.size":"3",
  "hadoop.conf.dir":"/etc/hadoop/",
  "partitioner.class":"io.confluent.connect.storage.partitioner.FieldPartitioner",
  "partition.field.name":"f1",
  "rotate.interval.ms":"120000",
  "hadoop.home":"/usr/local/hadoop",
  "logs.dir":"/logs",
  "hdfs.authentication.kerberos": "true",
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

log "Listing content of /topics/test_hdfs in HDFS"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /topics/test_hdfs"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec hadoop bash -c "/usr/local/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/f1=value1/test_hdfs+0+0000000000+0000000000.avro /tmp"
docker cp hadoop:/tmp/test_hdfs+0+0000000000+0000000000.avro /tmp/

docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000000.avro

log "Creating HDFS Source connector"
playground connector create-or-update --connector hdfs3-source-kerberos << EOF
{
          "connector.class":"io.confluent.connect.hdfs3.Hdfs3SourceConnector",
          "tasks.max":"1",
          "store.url":"hdfs://hadoop.kerberos-demo.local:9000",
          "hadoop.conf.dir":"/etc/hadoop/",
          "hadoop.home":"/usr/local/hadoop",
          "format.class" : "io.confluent.connect.hdfs3.format.avro.AvroFormat",
          "hdfs.authentication.kerberos": "true",
          "connect.hdfs.principal": "connect/connect.kerberos-demo.local@EXAMPLE.COM",
          "connect.hdfs.keytab": "/tmp/connect.keytab",
          "hdfs.namenode.principal": "nn/hadoop.kerberos-demo.local@EXAMPLE.COM",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "transforms" : "AddPrefix",
          "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
          "transforms.AddPrefix.regex" : ".*",
          "transforms.AddPrefix.replacement" : "copy_of_\$0"
          }
EOF

sleep 10

log "Verifying topic copy_of_test_hdfs"
playground topic consume --topic copy_of_test_hdfs --min-expected-messages 9 --timeout 60
