#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


function wait_for_stream_to_finish () {
  stream="$1"

  set +e
  MAX_WAIT=3600
  CUR_WAIT=0
  nb_streams_finished=0
  while [[ ! "${nb_streams_finished}" = "1" ]]
  do
    throughput=$(curl -s -X "POST" "http://localhost:8088/ksql" \
        -H "Accept: application/vnd.ksql.v1+json" \
        -d $"{
      "ksql": "DESCRIBE EXTENDED ${stream};",
      "streamsProperties": {}
    }" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)messages-per-sec:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')
    if [ "$throughput" = "0" ]
    then
      let "nb_streams_finished++"
    elif [ "$throughput" = "" ]
    then
      log "⚠️ Stream $stream has not started to process messages"
      continue
    else
      log "⏳ Stream $stream currently processing $throughput messages-per-sec"
    fi

    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      logerror "❗❗❗ ERROR: Please troubleshoot"
      exit 1
    fi
  done
  set -e
}

function throughtput () {
  stream="$1"
  duration="$2"

  MAX_WAIT=600
  CUR_WAIT=0
  totalmessages=""
  while [[ "${totalmessages}" = "" ]]
  do
    totalmessages=$(curl -s -X "POST" "http://localhost:8088/ksql" \
        -H "Accept: application/vnd.ksql.v1+json" \
        -d $"{
      "ksql": "DESCRIBE EXTENDED $stream;",
      "streamsProperties": {}
    }" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)total-messages:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')

    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      logerror "❗❗❗ ERROR: Please troubleshoot"
      exit 1
    fi
  done

  throughput=$(echo $((totalmessages / duration)))
  log "🚀 Stream $stream has processed $totalmessages messages. Took $duration seconds. Throughput=$throughput msg/s"
}

NOW="$(date +%s)000"
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/schemas/orders-template.avro > ${DIR}/schemas/orders.avro
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/schemas/shipments-template.avro > ${DIR}/schemas/shipments.avro

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Create topic orders"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "orders",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "1000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/orders.avro",
                "schema.keyfield" : "orderid"
            }' \
      http://localhost:8083/connectors/datagen-orders/config | jq

wait_for_datagen_connector_to_inject_data "orders" "10"

log "Create topic shipments"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "shipments",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "1000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/shipments.avro"
            }' \
      http://localhost:8083/connectors/datagen-shipments/config | jq

wait_for_datagen_connector_to_inject_data "shipments" "10"

log "Create topic products"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "products",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "100",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/products.avro",
                "schema.keyfield" : "productid"
            }' \
      http://localhost:8083/connectors/datagen-products/config | jq

wait_for_datagen_connector_to_inject_data "products" "10"

log "Create topic customers"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "customers",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "1000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/customers.avro",
                "schema.keyfield" : "customerid"
            }' \
      http://localhost:8083/connectors/datagen-customers/config | jq

wait_for_datagen_connector_to_inject_data "customers" "10"

for((i=0;i<10;i++))
do
  ./create-queries.sh
  sleep 5
  ./cleanup-queries.sh
  if [ $? -ne 0 ]
  then
    logerror "Cleanup failed, check the reason"
    exit 1
  fi
done

# 01:48:26 Cannot terminate all queries, check the errors below:
# [
#   {
#     "@type": "currentStatus",
#     "statementText": "TERMINATE CSAS_ENRICHED_O_C_105;",
#     "commandId": "terminate/CSAS_ENRICHED_O_C_105/execute",
#     "commandStatus": {
#       "status": "SUCCESS",
#       "message": "Query terminated.",
#       "queryId": null
#     },
#     "commandSequenceNumber": 114,
#     "warnings": []
#   }
# ]
# [
#   {
#     "@type": "currentStatus",
#     "statementText": "TERMINATE CSAS_FILTERED_STREAM_103;",
#     "commandId": "terminate/CSAS_FILTERED_STREAM_103/execute",
#     "commandStatus": {
#       "status": "SUCCESS",
#       "message": "Query terminated.",
#       "queryId": null
#     },
#     "commandSequenceNumber": 116,
#     "warnings": []
#   }
# ]
# [
#   {
#     "@type": "currentStatus",
#     "statementText": "TERMINATE CSAS_ENRICHED_O_C_P_107;",
#     "commandId": "terminate/CSAS_ENRICHED_O_C_P_107/execute",
#     "commandStatus": {
#       "status": "SUCCESS",
#       "message": "Query terminated.",
#       "queryId": null
#     },
#     "commandSequenceNumber": 118,
#     "warnings": []
#   }
# ]
# [
#   {
#     "@type": "currentStatus",
#     "statementText": "TERMINATE CTAS_ORDERPER_PROD_CUST_AGG_111;",
#     "commandId": "terminate/CTAS_ORDERPER_PROD_CUST_AGG_111/execute",
#     "commandStatus": {
#       "status": "EXECUTING",
#       "message": "Executing statement",
#       "queryId": null
#     },
#     "commandSequenceNumber": 120,
#     "warnings": []
#   }
# ]
# {
#   "@type": "statement_error",
#   "error_code": 50000,
#   "message": "Could not write the statement 'TERMINATE CSAS_ORDERS_SHIPPED_109;' into the command topic.\nCaused by: Timeout while waiting for command topic consumer to process command\n\ttopic",
#   "statementText": "TERMINATE CSAS_ORDERS_SHIPPED_109;",
#   "entities": []
# }