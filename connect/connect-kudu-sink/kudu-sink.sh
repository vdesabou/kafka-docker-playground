#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/ImpalaJDBC42.jar ]
then
     log "ERROR: ${DIR}/ImpalaJDBC42.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

sleep 30

log "Create Database test in kudu"
docker exec -i kudu impala-shell -i localhost:21000 -l -u kudu --ldap_password_cmd="echo -n secret" --auth_creds_ok_in_clear << EOF
CREATE DATABASE test;
EOF

sleep 5

log "Creating Kudu sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
          }' \
     http://localhost:8083/connectors/kudu-sink/config | jq .


log "Sending messages to topic orders"
docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5

log "Verify data is in kudu orders table"
docker exec -i kudu impala-shell -i localhost:21000 -l -u kudu --ldap_password_cmd="echo -n secret" --auth_creds_ok_in_clear << EOF
USE test;
SELECT * from orders;
EOF
