#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# this exercise is about Kerberos (SASL/GSSAPI with a keytab): it needs the kerberos environment
playground start-environment --environment kerberos --docker-compose-override-file "${PWD}/docker-compose.kerberos.repro-000033-sink-fails-after-key-rotation-old-keytab.yml"

# (renewable, as every principal of the environment: krb5.conf asks for renewable tickets, Java fails with
# "Message stream modified (41)" for a principal that is not)
log "The principal of the orders connector, its keytab, and its ACLs"
playground container exec -c kdc --command "kadmin.local -q 'add_principal -randkey orders_sink@TEST.CONFLUENT.IO' && kadmin.local -q 'modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable orders_sink@TEST.CONFLUENT.IO' && kadmin.local -q 'ktadd -k /var/lib/secret/orders-sink.key orders_sink@TEST.CONFLUENT.IO' && chmod a+r /var/lib/secret/orders-sink.key" > /dev/null
playground rbac acl create --principal User:orders_sink --operation READ --operation DESCRIBE --resource Topic:orders
playground rbac acl create --principal User:orders_sink --operation READ --resource Group:connect-orders-sink

playground topic produce -t orders --nb-messages 3 --forced-value '{"order": %g, "day": "monday"}'

# the customer config: the connector reads with its own principal and keytab
log "Creating the FileStream sink connector, with its own principal"
playground connector create-or-update --connector orders-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "orders",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.sasl.jaas.config": "com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\"/var/lib/secret/orders-sink.key\" principal=\"orders_sink@TEST.CONFLUENT.IO\";"
}
EOF
sleep 10
playground container exec -c connect --command "cat /tmp/output.json"

# 💥 on tuesday, the Active Directory team rotates the keys of the service accounts (a new key on the KDC, kvno + 1).
# Nobody exports the new keytab for the connect workers. Everything keeps working... until the connector restarts
log "Tuesday: the keys of the service accounts are rotated on the KDC"
playground container exec -c kdc --command "kadmin.local -q 'cpw -randkey orders_sink@TEST.CONFLUENT.IO'" > /dev/null

playground topic produce -t orders --nb-messages 3 --forced-value '{"order": %g, "day": "tuesday"}'

log "Wednesday: the connect worker restarts (a rolling upgrade)"
playground container restart -c connect
playground connector status --connector orders-sink || true
