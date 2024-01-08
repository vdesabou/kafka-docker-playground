#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.kerberos.yml"

log "Add connect kerberos principal"
docker exec -i kerberos kadmin.local << EOF
addprinc -randkey connect/connect.kerberos-demo.local@KERBEROS.SERVER
modprinc -maxrenewlife 11days +allow_renewable connect/connect.kerberos-demo.local@KERBEROS.SERVER
modprinc -maxrenewlife 11days krbtgt/KERBEROS.SERVER
modprinc -maxlife 11days connect/connect.kerberos-demo.local@KERBEROS.SERVER
ktadd -k /connect.keytab connect/connect.kerberos-demo.local@KERBEROS.SERVER
listprincs
EOF

log "Copy connect.keytab to connect container /tmp/sshuser.keytab"
docker cp kerberos:/connect.keytab .
docker cp connect.keytab connect:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/connect.keytab
fi

log "Creating HBase sink connector"
playground connector create-or-update --connector hbase-sink  << EOF
{
     "connector.class": "io.confluent.connect.hbase.HBaseSinkConnector",
     "tasks.max": "1",
     "key.converter":"org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor":1,
     "hbase.zookeeper.quorum": "hbase",
     "hbase.zookeeper.property.clientPort": "2181",
     "zookeeper.znode.parent": "/hbase-secure",

     "hbase.keytab.file": "/tmp/connect.keytab",
     "hbase.master.kerberos.principal": "hbase/hbase.kerberos-demo.local@KERBEROS.SERVER",
     "hbase.regionserver.kerberos.principal": "hbase/hbase.kerberos-demo.local@KERBEROS.SERVER",
     "hbase.rpc.protection": "AUTHENTICATION",
     "hbase.user.principal": "connect/connect.kerberos-demo.local@KERBEROS.SERVER",

     "auto.create.tables": "true",
     "auto.create.column.families": "false",
     "table.name.format": "example_table",
     "topics": "hbase-test"
}
EOF

log "Sending messages to topic hbase-test"
playground topic produce -t hbase-test --nb-messages 3 --key "key1" << 'EOF'
value%g
EOF

sleep 10

log "Verify data is in HBase:"
docker exec -i hbase bash -c "kinit -kt /opt/keytabs/hbase.keytab hbase/hbase.kerberos-demo.local && hbase shell -Djava.security.auth.login.config=/opt/hbase-2.2.3/conf/hbase-client.jaas -Dsun.security.krb5.debug=true" > /tmp/result.log  2>&1 <<-EOF
scan 'example_table'
EOF
cat /tmp/result.log
grep "key1" /tmp/result.log | grep "value=value1"
grep "key2" /tmp/result.log | grep "value=value2"
grep "key3" /tmp/result.log | grep "value=value3"