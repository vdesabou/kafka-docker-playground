#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of the Schema Registry, ksqlDB, SASL, TLS, Python client, RBAC, OAuth and Kerberos exercises of https://kafka-docker-playground.io/#/academy (the
# 🌊 Streams, SR & Non-Java and 🔐 Platform, Security & Cloud Infra support areas): runs their reproduction models and
# asserts the symptom each exercise is about, then the fix the page gives. The SASL, TLS, Python, RBAC, OAuth and
# Kerberos models start their own environment (sasl-plain, 2way-ssl, rbac-sasl-plain, sasl-oauthbearer, kerberos)
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

log "Exercise: Python client, the producer cannot connect"
python_conf="$academy/environment-sasl-plain/client-python-000030/client.properties"
cp "$python_conf" "$python_conf.lab"
trap 'mv -f "$python_conf.lab" "$python_conf" 2>/dev/null || true' EXIT
run_model environment-sasl-plain python-repro-000030-python-producer-cannot-connect.sh
lab_expect_contains "Disconnected: connection closed by peer"
lab_expect_contains "Only 0 records out of 5 were delivered"
cat >> "$python_conf" << 'EOF'
security.protocol=SASL_PLAINTEXT
sasl.mechanisms=PLAIN
sasl.username=client
sasl.password=client-secret
EOF
lab_run playground container exec -c client-python --command "python client.py produce orders /tmp/conf/client.properties 5"
lab_expect_contains "5 records were produced to topic orders"
mv -f "$python_conf.lab" "$python_conf"

log "Exercise: RBAC, the connector runs as its own service account"
run_model environment-rbac-sasl-plain rbac-repro-000031-sink-not-authorized-own-service-account.sh
lab_expect_contains "TopicAuthorizationException: Not authorized to access topics: [invoices]"
lab_run playground connector diagnose --connector invoices-sink
# (the name of the principal comes from the example run with playground run, appSA for a learner; the lab runs the models
# with bash, so it is <principal> here)
lab_expect_contains "(principal.service.name) is not authorized on Topic:invoices"
lab_expect_contains "--role DeveloperRead --resource Topic:invoices"
lab_run playground rbac role-binding create --principal User:appSA --role DeveloperRead --resource Topic:invoices
lab_run playground connector restart --connector invoices-sink
sleep 15
lab_run playground connector status --connector invoices-sink
lab_expect_contains "GroupAuthorizationException: Not authorized to access group: connect-invoices-sink"
lab_run playground rbac role-binding create --principal User:appSA --role DeveloperRead --resource Group:connect-invoices-sink
lab_run playground connector restart --connector invoices-sink
sleep 15
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"invoice": 5}'

log "Exercise: OAuth, the connector cannot get its token after a secret rotation"
run_model environment-sasl-oauthbearer oauth-repro-000032-sink-cannot-get-token-rotated-secret.sh
lab_expect_contains "was encountered reading the token endpoint response"
lab_run playground connector diagnose --connector shipments-sink
lab_expect_contains "🎟️ the token endpoint refused the OAuth client of the connector"
playground connector create-or-update --connector shipments-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "shipments",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required clientId=\"client\" clientSecret=\"client-secret\";"
}
EOF
sleep 10
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"shipment": 5}'

log "Exercise: Kerberos, the connector fails after a restart, Checksum failed"
run_model environment-kerberos kerberos-repro-000033-sink-fails-after-key-rotation-old-keytab.sh
lab_expect_contains "LoginException: Checksum failed"
lab_run playground connector diagnose --connector orders-sink
lab_expect_contains "🎫 Kerberos login refused (Checksum failed) with consumer.override.sasl.jaas.config"
lab_run playground container exec -c kdc --command "kadmin.local -q 'ktadd -k /var/lib/secret/orders-sink.key -norandkey orders_sink@TEST.CONFLUENT.IO' && chmod a+r /var/lib/secret/orders-sink.key"
lab_run playground connector restart --connector orders-sink
sleep 15
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"order": 3, "day": "tuesday"}'

log "✅ academy areas lab: the exercises behave as the page says"
