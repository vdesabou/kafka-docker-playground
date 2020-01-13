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

sleep 120

docker container logs --tail=600 ldap
docker container logs --tail=600 kudu

log "Create Database test and table accounts in kudu"
docker exec -i kudu impala-shell -i localhost:21000 -l -u kudu --ldap_password_cmd="echo -n secret" --auth_creds_ok_in_clear << EOF
CREATE DATABASE test;
USE test;
CREATE TABLE accounts (
     id BIGINT,
     name STRING,
     PRIMARY KEY(id)
     ) PARTITION BY HASH PARTITIONS 16 STORED AS KUDU TBLPROPERTIES ("kudu.master_addresses" = "127.0.0.1","kudu.num_tablet_replicas" = "1");
INSERT INTO accounts (id, name) VALUES (1, 'alice');
INSERT INTO accounts (id, name) VALUES (2, 'bob');
EOF

sleep 5

log "Creating Kudu source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.kudu.KuduSourceConnector",
                    "tasks.max": "1",
                    "impala.server": "kudu",
                    "impala.port": "21050",
                    "kudu.database": "test",
                    "mode": "incrementing",
                    "incrementing.column.name": "id",
                    "topic.prefix": "test-kudu-",
                    "table.whitelist": "accounts",
                    "key.converter": "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "impala.ldap.password": "secret",
                    "impala.ldap.user": "kudu",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kudu-source/config | jq_docker_cli .

sleep 5

log "Verify we have received the data in test-kudu-accounts topic"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic test-kudu-accounts --from-beginning --max-messages 2
