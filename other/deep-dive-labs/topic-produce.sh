#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-topic-produce

schemas="${DIR}/../../scripts/cli/predefined-schemas"
playground_cli="${DIR}/../../scripts/cli/playground"

lab_require_plaintext
lab_start_environment

log "Step 1: the pool"
lab_run playground topic produce -t lab-pool --nb-messages 10 --max-nb-messages-to-generate 3 < "$schemas/avro/lead.avsc"
lab_expect_exit 0
lab_expect_contains "🔮 value schema was identified as avro"
lab_expect_contains "10 records were generated (3 different records, repeated)"
lab_expect_contains "📤 produced 10 records to topic lab-pool"

log "Step 2: keys and headers"
lab_run playground topic produce -t lab-keys --nb-messages 3 --key 'order-007' --headers 'source:web,version:2' --value '{"id": %g}'
lab_expect_exit 0
lab_expect_contains "🗝️ key order-007 is set with a number 007, it will be used as starting point"
lab_run playground topic consume -t lab-keys --min-expected-messages 3 --timeout 30
lab_expect_exit 0
lab_expect_contains 'Headers:source:web,version:2|Key:order-007|Value:{"id": 1}'
lab_expect_contains 'Headers:source:web,version:2|Key:order-008|Value:{"id": 2}'
lab_expect_contains 'Headers:source:web,version:2|Key:order-009|Value:{"id": 3}'

log "Step 3: datagen is JSON, not Avro"
lab_run playground topic produce -t lab-trades --nb-messages 2 < "$schemas/datagen/stock_trades_schema.avro"
lab_expect_exit 0
lab_expect_contains "🔮 value schema was identified as datagen"
lab_expect_contains '"symbol":'
lab_run playground schema get --subject lab-trades-value
lab_expect_exit 1
lab_expect_contains "No schema found !"

log "Step 4: derived schema, random values vs your values"
lab_run bash -c "echo '{\"order_id\": 1, \"customer\": \"acme\", \"amount\": 9.99}' | $playground_cli topic produce -t lab-derived --nb-messages 2 --derive-value-schema-as AVRO"
lab_expect_exit 0
lab_expect_contains "🪄 generated AVRO schema:"
lab_expect_contains '"name": "amount"'
lab_expect_contains "🔮 value schema was identified as avro"
lab_expect_contains "📤 produced 2 records to topic lab-derived"
lab_run bash -c "echo '{\"order_id\": 1, \"customer\": \"acme\", \"amount\": 9.99}' | $playground_cli topic produce -t lab-exact --derive-value-schema-as AVRO --forced-value '{\"order_id\": 1, \"customer\": \"acme\", \"amount\": 9.99}' --consume"
lab_expect_exit 0
lab_expect_contains "☢️ --forced-value is set"
lab_expect_contains 'Value:{"amount":9.99,"customer":"acme","order_id":1}|ValueSchemaId:'

log "Step 5: detection trap, then --value-format"
lab_run playground topic produce -t lab-raw --value '{"type": "record", "note": "not a schema"}'
lab_expect_exit 1
lab_expect_contains "🔮 value schema was identified as avro"
lab_expect_contains "org.apache.avro.SchemaParseException: No name in schema"
lab_run playground topic produce -t lab-raw --value '{"type": "record", "note": "not a schema"}' --value-format raw
lab_expect_exit 0
lab_expect_contains "🔮 value schema type is set to raw with --value-format"
lab_expect_contains "📤 produced 1 records to topic lab-raw"

log "Step 6: tombstone, then the partition guard"
lab_run playground topic produce -t lab-keys --tombstone --key 'order-007'
lab_expect_exit 0
lab_expect_contains "order-007|NULL"
lab_expect_contains "🧟 Sending tombstone(s)"
lab_run playground topic produce -t lab-keys --nb-partitions 3 --value x
lab_expect_exit 1
lab_expect_contains "--nb-partitions is set, but topic is not empty, delete it first and retry"

log "Step 7: a steady flow"
# ctrl-c in the page: stopped by timeout here
lab_run timeout 15 "$playground_cli" topic produce -t lab-ticks --nb-messages -1 --throughput 5 --value '{"tick": %g}'
lab_expect_exit 124
lab_expect_contains "🐢 --throughput is set, sending at most 5 records per second"
lab_expect_contains "records sent so far..."
lab_run playground topic get-number-records --topic lab-ticks
lab_expect_exit 0
nb_ticks=$(echo "$LAB_OUTPUT" | tail -1)
# about 5 records per second during the seconds left after the generation and the topic creation
if [ "$nb_ticks" -lt 10 ] || [ "$nb_ticks" -gt 80 ]
then
    logerror "❌ expected between 10 and 80 records at 5 records per second, got $nb_ticks"
    exit 1
fi
log "✅ $nb_ticks records sent at 5 records per second"

log "✅ all the outputs of the page are as expected"
