#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of the Schema Registry, ksqlDB, SASL and TLS exercises of https://kafka-docker-playground.io/#/academy (the
# 🌊 Streams, SR & Non-Java and 🔐 Platform, Security & Cloud Infra support areas): runs their reproduction models and
# asserts the symptom each exercise is about, then the fix the page gives. The SASL and TLS models start their own
# environment (sasl-plain, 2way-ssl)
lab_require_plaintext
academy="${DIR}/../../academy"

function run_model () {
    lab_run bash -c "cd '$academy/$1' && bash '$2'"
}

log "Exercise: Schema Registry, the new version of the producer is refused"
run_model environment-plaintext schema-registry-repro-000026-producer-refused-incompatible-schema.sh
lab_expect_contains "Schema being registered is incompatible with an earlier schema for subject \"customers-value\""
lab_expect_contains "🎓 why it is refused, field by field: playground schema check-compatibility --subject customers-value"
lab_run playground schema check-compatibility --subject customers-value << 'EOF'
{"type": "record", "namespace": "com.example", "name": "Customer", "fields": [{"name": "name", "type": "string"}, {"name": "email", "type": "string"}, {"name": "loyalty_tier", "type": "string"}]}
EOF
lab_expect_contains "READER_FIELD_MISSING_DEFAULT_VALUE: The field 'loyalty_tier'"
lab_run playground topic produce -t customers --nb-messages 3 << 'EOF'
{"type": "record", "namespace": "com.example", "name": "Customer", "fields": [{"name": "name", "type": "string"}, {"name": "email", "type": "string"}, {"name": "loyalty_tier", "type": "string", "default": "standard"}]}
EOF
lab_expect_contains "📤 produced 3 records to topic customers"

log "Exercise: ksqlDB, the new table stays empty"
run_model environment-plaintext ksqldb-repro-000027-ksqldb-table-stays-empty.sh
lab_expect_not_contains "|product-1" "the table is empty"
lab_run playground ksqldb wait --source SALES
lab_expect_contains "processed none of the records already in its input"
lab_run playground ksqldb sql << 'EOF'
DROP TABLE SALES DELETE TOPIC;
SET 'auto.offset.reset' = 'earliest';
CREATE TABLE sales AS SELECT product, SUM(amount) AS total FROM orders GROUP BY product EMIT CHANGES;
EOF
lab_run playground ksqldb wait --source SALES
lab_expect_contains "✅ the queries writing to SALES are RUNNING and have no lag"
lab_run playground ksqldb sql <<< "SELECT * FROM sales;"
lab_expect_contains "product-6"

log "Exercise: SASL, the sink connector is refused after a password rotation"
run_model environment-sasl-plain sasl-plain-repro-000028-sink-fails-authentication-old-password.sh
lab_expect_contains "SaslAuthenticationException: Authentication failed: Invalid username or password"
lab_expect_contains "🔑 SASL authentication refused with the connector's own credentials: consumer.override.sasl.jaas.config"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "payments",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"client\" password=\"client-secret\";"
}
EOF
sleep 10
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"payment": 5}'

log "Exercise: TLS, the connector fails when it uses the IP address of the broker"
run_model environment-2way-ssl 2way-ssl-repro-000029-sink-fails-tls-broker-by-ip-address.sh
lab_expect_contains "No subject alternative names matching IP address"
lab_expect_contains "🔐 TLS handshake refused (No subject alternative names matching IP address"
broker_ip=$(playground --output-level ERROR container exec -c connect --command "getent hosts broker" | awk '{print $1}' | tail -1)
lab_run playground tools cert inspect --server broker:9092 --hostname "$broker_ip" --output-dir /tmp
lab_expect_contains "regenerate with -ext SAN=ip:$broker_ip (an address only matches an IP entry, never a DNS one)"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "payments",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.bootstrap.servers": "broker:9092"
}
EOF
sleep 10
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"payment": 3}'

log "✅ academy areas lab: the exercises behave as the page says"
