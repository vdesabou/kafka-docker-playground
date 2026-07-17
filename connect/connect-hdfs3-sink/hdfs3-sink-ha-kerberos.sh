#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.1.99"
then
     logwarn "minimal supported connector version is 1.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}

# HDFS3 sink is not compatible with CFK (Confluent for Kubernetes)
# CFK processes the docker-compose override to create Kubernetes Pods,
# but HDFS datanodes fail to register with the namenode in K8s networking model.
# HDFS cluster requires StatefulSets for persistent node identity, not ephemeral Pods.
if [[ "$PLAYGROUND_ENVIRONMENT" == "cfk" ]]
then
  logwarn "⚠️  HDFS3 sink connector is not compatible with CFK (Confluent for Kubernetes)"
  logwarn "   HDFS requires persistent node registration that K8s Pods cannot maintain"
  logwarn "   This example is for Docker Compose environments only"
  exit 111
fi

playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.ha-kerberos.yml"

log "Wait 80 seconds while hadoop is installing"
sleep 80

log "namenode1 becomes primary"
playground container exec --container namenode1 --command "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local;hdfs haadmin -transitionToActive nn1"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
playground container exec --container namenode1 --command "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -chmod 777  /"

log "Add connect kerberos principal"
playground container exec --container krb5 --command "kadmin.local" << EOF
addprinc -randkey connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days +allow_renewable connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days krbtgt/EXAMPLE.COM
modprinc -maxlife 11days connect/connect.kerberos-demo.local@EXAMPLE.COM
ktadd -k /connect.keytab connect/connect.kerberos-demo.local@EXAMPLE.COM
listprincs
EOF

log "Copy connect.keytab to connect container /tmp/sshuser.keytab"
playground container cp --source krb5:/connect.keytab --destination .
playground container cp --source connect.keytab --destination connect:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     playground container exec --container connect --root --command "chown appuser:appuser /tmp/connect.keytab"
fi

log "Creating HDFS Sink connector"
playground connector create-or-update --connector hdfs3-sink-ha-kerberos  << EOF
{
  "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
  "tasks.max":"1",
  "topics":"hdfs-topic",
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
  "confluent.license": "",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1",
  "key.converter":"org.apache.kafka.connect.storage.StringConverter",
  "value.converter":"io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url":"http://schema-registry:8081",
  "schema.compatibility":"BACKWARD"
}
EOF

log "Sending messages to topic hdfs-topic"
playground topic produce -t hdfs-topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
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

log "Listing content of /topics/hdfs-topic/partition=0 in HDFS"
playground container exec --container namenode1 --command "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -ls /topics/hdfs-topic/partition=0"

log "Getting one of the avro files locally and displaying content with avro-tools"
playground container exec --container namenode1 --command "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hadoop fs -copyToLocal /topics/hdfs-topic/partition=0/hdfs-topic+0+0000000000+0000000002.avro /tmp"
playground container cp --source namenode1:/tmp/hdfs-topic+0+0000000000+0000000002.avro --destination /tmp/

playground  tools read-avro-file --file /tmp/hdfs-topic+0+0000000000+0000000002.avro
