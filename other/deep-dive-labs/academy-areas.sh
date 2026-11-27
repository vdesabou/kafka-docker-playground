#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of the Schema Registry, ksqlDB, SASL, TLS, Python client, RBAC, OAuth, Kerberos and Kafka Streams exercises of https://kafka-docker-playground.io/#/academy (the
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

log "Exercise: TLS, the Connect worker does not come back after a hardware swap (its clock behind)"
run_model environment-2way-ssl 2way-ssl-repro-000037-connect-worker-down-clock-behind-certificate-not-yet-valid.sh
lab_expect_contains "runs with the fake clock"
lab_expect_contains "the connect REST API does not answer, is the worker up?"
lab_run playground container logs -c connect --errors
lab_expect_contains "CertificateNotYetValidException: NotBefore:"
lab_run playground debug clock -c connect
lab_expect_contains "offset -17"
lab_run playground debug clock -c connect --reset
lab_expect_contains "no fake clock"
MAX_WAIT=120
CUR_WAIT=0
until playground --output-level ERROR connector status --connector filestream-sink 2>&1 | grep -q "✅ RUNNING  0:🟢 RUNNING"
do
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ filestream-sink is not RUNNING $MAX_WAIT seconds after the clock reset"
        exit 1
    fi
done
lab_run playground topic produce -t payments --nb-messages 2 --forced-value '{"payment": %g, "after": "reset"}'
sleep 10
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"payment": 2, "after": "reset"}'

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

log "Exercise: Kafka Streams, one application stopped on a bad record"
run_model other-kafka-streams streams-repro-000036-one-application-stops-on-poison-pill.sh
lab_expect_contains '{"key":"p3","offset":2}'
lab_expect_not_contains '{"key":"p4","offset"' "p4 never reaches the output of the stopped application"
lab_run playground streams status
lab_expect_contains "❌ streams: the client is ERROR since"
lab_expect_contains "❌ streams2: the client is ERROR since"
lab_expect_contains "❌ streams3: the client is ERROR since"
lab_expect_contains "🧪 Deserialization error"
lab_expect_not_contains "zombie" "a dead instance is not a second owner of its tasks"
# the dead instances stay members of the group until their session times out (45 s)
MAX_WAIT=120
CUR_WAIT=0
until playground consumer-group describe --group streams-serde-errors-fail-on-poison-pill 2>&1 | grep -q "has no active members"
do
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ consumer group streams-serde-errors-fail-on-poison-pill still has members after $MAX_WAIT seconds"
        exit 1
    fi
done
lab_run playground consumer-group reset-offsets --group streams-serde-errors-fail-on-poison-pill --topic payments:2 --to-offset 3
lab_expect_contains "streams-serde-errors-fail-on-poison-pill payments        2          3"
lab_run playground container restart -c streams -c streams2 -c streams3
lab_run playground topic consume --topic payments-processed-fail-demo --min-expected-messages 4 --timeout 120
lab_expect_contains '"id": "p4"'

log "Exercise: Kafka Streams, the enriched orders of most customers never come out (topics not co-partitioned)"
run_model other-kafka-streams streams-repro-000038-join-loses-orders-topics-not-co-partitioned.sh
lab_expect_contains '{"key":"c2","value":'
lab_expect_not_contains '{"key":"c1","value":' "the order of c1 is lost"
lab_run playground streams status
lab_expect_contains "streams-join-copartition-demo reads topics with different partition counts (customers: 3, orders-by-customer: 6)"
lab_run playground topic delete --topic orders-by-customer
lab_run playground topic create --topic orders-by-customer --nb-partitions 3
lab_run playground container restart -c streams -c streams2 -c streams3
MAX_WAIT=120
CUR_WAIT=0
until playground streams status 2>&1 | grep -q "📐 Internal topic with the wrong number of partitions"
do
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ no 📐 Internal topic with the wrong number of partitions after $MAX_WAIT seconds"
        exit 1
    fi
done
CUR_WAIT=0
until playground consumer-group describe --group streams-join-copartition-demo 2>&1 | grep -q "has no active members"
do
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ consumer group streams-join-copartition-demo still has members after $MAX_WAIT seconds"
        exit 1
    fi
done
lab_run playground container exec -c broker --command "kafka-streams-application-reset --bootstrap-server broker:9092 --application-id streams-join-copartition-demo --input-topics customers,orders-by-customer --to-earliest"
lab_expect_contains "Deleting inferred internal topics [streams-join-copartition-demo-customers-STATE-STORE-0000000000-changelog]"
lab_run playground container restart -c streams -c streams2 -c streams3
CUR_WAIT=0
until [ "$(playground streams status --json 2>/dev/null | jq '[.applications[] | select(.application_id == "streams-join-copartition-demo") | .instances[] | select(.state == "RUNNING")] | length')" == "3" ]
do
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ streams-join-copartition-demo is not RUNNING $MAX_WAIT seconds after the reset"
        exit 1
    fi
done
for customer in c1 c2 c3
do
    playground topic produce --topic orders-by-customer --nb-messages 1 --key $customer --value "{\"order_id\":\"y-$customer\",\"product\":\"p1\"}" --value-format raw > /dev/null
done
lab_run playground topic consume --topic orders-by-customer-enriched --min-expected-messages 4 --timeout 60
lab_expect_contains 'y-c1'
lab_expect_contains 'y-c3'
lab_run playground streams status
lab_expect_not_contains "reads topics with different partition counts" "co-partitioned now"

log "✅ academy areas lab: the exercises behave as the page says"
