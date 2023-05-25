#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# read configuration files
#
if [ -r ${DIR}/test.properties ]
then
    . ${DIR}/test.properties
else
    logerror "Cannot read configuration file ${DIR}/test.properties"
    exit 1
fi

if [ -r ${DIR}/ccloud-cluster.properties ]
then
    . ${DIR}/ccloud-cluster.properties
else
    logerror "Cannot read configuration file ${APP_HOME}/ccloud-cluster.properties"
    exit 1
fi

verify_installed "kubectl"
verify_installed "helm"

CONFIG_FILE=${DIR}/client.properties
cat << EOF > ${CONFIG_FILE}
bootstrap.servers=${bootstrap_servers}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${cluster_api_key}' password='${cluster_api_secret}';
schema.registry.url=${schema_registry_url}
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=${schema_registry_api_key}:${schema_registry_api_secret}
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
EOF

NOW="$(date +%s)000"
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/schemas/orders-template.avro > ${DIR}/schemas/orders.avro
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/schemas/shipments-template.avro > ${DIR}/schemas/shipments.avro

kubectl cp ${CONFIG_FILE} confluent/connectors-0:/tmp/config
kubectl cp ${DIR}/schemas confluent/connectors-0:/tmp/
function create_input_topic () {
  topic_name=$1
  set +e
  # check if topic already exists
  kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ${topic_name} --describe > /dev/null 2>&1
  if [ $? -eq 0 ]
  then
    logwarn "Topic ${topic_name} already exists, it will be deleted!"
    check_if_continue
  fi
  log "Delete topic ${topic_name}"
  kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ${topic_name} --delete > /dev/null 2>&1
  log "Create topic ${topic_name}"
  kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ${topic_name} --create --replication-factor 3 --partitions ${number_topic_partitions} > /dev/null 2>&1
  set -e
}

# https://github.com/confluentinc/kafka-connect-datagen
# https://github.com/confluentinc/avro-random-generator

random_value=$RANDOM

#######
# orders
#######
topic="orders"
create_input_topic "${topic}"
iterations_total=$(eval echo '$'${topic}_iterations)
iterations_per_task=$((iterations_total / datagen_tasks))
kubectl exec -i connectors-0 -- curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "'"${topic}"'",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "'"$iterations_per_task"'",
                "tasks.max": "'"$datagen_tasks"'",
                "schema.filename" : "'"/tmp/schemas/${topic}.avro"'",
                "schema.keyfield" : "orderid"
            }' \
      http://localhost:8083/connectors/datagen-${topic}-${random_value}/config | jq

wait_for_datagen_connector_to_inject_data "${topic}-${random_value}" "${datagen_tasks}" "kubectl exec -i connectors-0 --"

log "Verify we have received data in topic ${topic}"
playground topic consume --topic ${topic} --min-expected-messages 1 --timeout 60

#######
# shipments
#######
topic="shipments"
create_input_topic "${topic}"
iterations_total=$(eval echo '$'${topic}_iterations)
iterations_per_task=$((iterations_total / datagen_tasks))
kubectl exec -i connectors-0 -- curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "'"${topic}"'",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "'"$iterations_per_task"'",
                "tasks.max": "'"$datagen_tasks"'",
                "schema.filename" : "'"/tmp/schemas/${topic}.avro"'"
            }' \
      http://localhost:8083/connectors/datagen-${topic}-${random_value}/config | jq

wait_for_datagen_connector_to_inject_data "${topic}-${random_value}" "${datagen_tasks}" "kubectl exec -i connectors-0 --"

log "Verify we have received data in topic ${topic}"
playground topic consume --topic ${topic} --min-expected-messages 1 --timeout 60

#######
# products
#######
topic="products"
create_input_topic "${topic}"
iterations_total=$(eval echo '$'${topic}_iterations)
iterations_per_task=$((iterations_total / datagen_tasks))
kubectl exec -i connectors-0 -- curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "'"$topic"'",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "'"$iterations_per_task"'",
                "tasks.max": "'"$datagen_tasks"'",
                "schema.filename" : "'"/tmp/schemas/${topic}.avro"'",
                "schema.keyfield" : "productid"
            }' \
      http://localhost:8083/connectors/datagen-${topic}-${random_value}/config | jq

wait_for_datagen_connector_to_inject_data "${topic}-${random_value}" "${datagen_tasks}" "kubectl exec -i connectors-0 --"
log "Verify we have received data in topic ${topic}"
playground topic consume --topic ${topic} --min-expected-messages 1 --timeout 60

#######
# customers
#######
topic="customers"
create_input_topic "${topic}"
iterations_total=$(eval echo '$'${topic}_iterations)
iterations_per_task=$((iterations_total / datagen_tasks))
kubectl exec -i connectors-0 -- curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "'"$topic"'",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "'"$iterations_per_task"'",
                "tasks.max": "'"$datagen_tasks"'",
                "schema.filename" : "'"/tmp/schemas/${topic}.avro"'",
                "schema.keyfield" : "customerid"
            }' \
      http://localhost:8083/connectors/datagen-${topic}-${random_value}/config | jq

wait_for_datagen_connector_to_inject_data "${topic}-${random_value}" "${datagen_tasks}" "kubectl exec -i connectors-0 --"
log "Verify we have received data in topic ${topic}"
playground topic consume --topic ${topic} --min-expected-messages 1 --timeout 60

rm ${CONFIG_FILE}