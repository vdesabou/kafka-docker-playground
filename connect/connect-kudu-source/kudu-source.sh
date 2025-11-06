#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.0.5"
then
     logwarn "minimal supported connector version is 1.0.6 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     logerror "this connector is broken with CP 8"
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

sleep 120

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
playground connector create-or-update --connector kudu-source  << EOF
{
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
          }
EOF

sleep 5

log "Verify we have received the data in test-kudu-accounts topic"
playground topic consume --topic test-kudu-accounts --min-expected-messages 2 --timeout 60
