#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating syslog connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "topic": "logs",
                "tasks.max": "1",
                "connector.class": "io.confluent.connect.syslog.SyslogSourceConnector",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "syslog.port": "42514",
                "syslog.listener": "UDP",
                "syslog.reverse.dns.remote.ip": "true",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/syslog-source/config


log "Creating elasticsearch connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
                "connection.url": "http://elasticsearch:9200",
                "connection.username": "elastic",
                "connection.password": "elastic",
                "type.name": "",
                "behavior.on.malformed.documents": "warn",
                "errors.tolerance": "all",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true",
                "topics": "ssh_bad_auth_count",
                "key.ignore": "false",
                "schema.ignore": "false",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/elastic-sink/config

log "Create ssh logs"
docker exec -i connect bash -c 'kafka-topics --bootstrap-server broker:9092 --topic ssh_logs --partitions 1 --replication-factor 1 --create'

log "Create the ksqlDB stream"
docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [[ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ]] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE OR REPLACE STREAM SSH_LOGS (
  level BIGINT,
  sshd_auth_type VARCHAR,
  sshd_invalid_user VARCHAR,
  ssh_fail_line VARCHAR,
  sshd_port BIGINT,
  host VARCHAR,
  sshd_protocol VARCHAR,
  sshd_client_ip VARCHAR) 
  WITH (KAFKA_TOPIC='ssh_logs', VALUE_FORMAT='JSON');
EOF

log "Create the materialized views"
docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [[ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ]] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE OR REPLACE TABLE ssh_bad_auth_count
    WITH (kafka_topic='ssh_bad_auth_count') AS
    SELECT SSHD_INVALID_USER,
           COUNT(*) AS rating_count
    FROM SSH_LOGS
    GROUP BY SSHD_INVALID_USER;
EOF

sleep 5

# Import elastic index & dashboard



log "Try to connect with a wrong password on ssh endoint localhost:7022"
log "<ssh test@localhost -p 7022> or <ssh admin@localhost -p 7022>"