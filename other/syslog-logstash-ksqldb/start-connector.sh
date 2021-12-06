#!/bin/bash

echo "Creating syslog connector"
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
     http://localhost:8083/connectors/syslog-source/config | jq .

echo "Creating elasticsearch connector"
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
                "topics": "SSHD_BAD_AUTH_TABLE",
                "key.ignore": "false",
                "schema.ignore": "true",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/elastic-sink/config | jq .