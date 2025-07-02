#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.0.5"
then
     logwarn "minimal supported connector version is 1.0.6 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

get_3rdparty_file "ImpalaJDBC42.jar"

if [ ! -f ${DIR}/ImpalaJDBC42.jar ]
then
     logerror "❌ ${DIR}/ImpalaJDBC42.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

sleep 30

log "Create Database test in kudu"
docker exec -i kudu impala-shell -i localhost:21000 -l -u kudu --ldap_password_cmd="echo -n secret" --auth_creds_ok_in_clear << EOF
CREATE DATABASE test;
EOF

sleep 5

log "Creating Kudu sink connector"
playground connector create-or-update --connector kudu-sink  << EOF
{
                    "connector.class": "io.confluent.connect.kudu.KuduSinkConnector",
                    "tasks.max": "1",
                    "topics": "orders",
                    "impala.server": "kudu",
                    "impala.port": "21050",
                    "kudu.database": "test",
                    "auto.create": "true",
                    "pk.mode":"record_value",
                    "pk.fields":"id",
                    "key.converter": "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "impala.ldap.password": "secret",
                    "impala.ldap.user": "kudu",
                    "kudu.tablet.replicas": "1",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }
EOF


log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

sleep 15

log "Verify data is in kudu orders table"
docker exec -i kudu impala-shell -i localhost:21000 -l -u kudu --ldap_password_cmd="echo -n secret" --auth_creds_ok_in_clear > /tmp/result.log  2>&1 <<-EOF
USE test;
SELECT * from orders;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log
