#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "8.3.99"
then
    logwarn "Explicit topic-subject associations need Confluent Platform 8.4 or later"
    exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

SR_URL="http://localhost:8081"

# the Schema Registry Associations API is read only: associations are written with the topic configs
# confluent.key.association / confluent.value.association
function get_associations () {
    curl -s "${SR_URL}/associations/$1"
}

# wait until the association lookup $1 returns $2 associations ("a change to an association can take a few seconds
# to appear in lookup results")
function wait_for_associations () {
    local path="$1"
    local expected="$2"
    MAX_WAIT=60
    CUR_WAIT=0
    while [ "$(get_associations "$path" | jq 'length')" != "$expected" ]
    do
        sleep 2
        CUR_WAIT=$(( CUR_WAIT+2 ))
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ GET /associations/$path did not return $expected association(s) after $MAX_WAIT seconds"
            get_associations "$path"
            exit 1
        fi
    done
    get_associations "$path" | jq .
}

CLUSTER_ID=$(playground broker describe | grep 'Cluster id:' | awk '{print $NF}')
if [ -z "${CLUSTER_ID}" ]
then
    logerror "❌ could not get the Kafka cluster id with playground broker describe"
    exit 1
fi
log "🆔 Kafka cluster id is ${CLUSTER_ID}"

########################
# Native schema (STRONG)
########################
# kafka-topics refuses --config confluent.value.association: the association is given as a JSON file
# {"schemaType": "AVRO", "schema": "<the Order schema as a string>"} (order-association.json, mounted in the broker)
log "🆕 Create topic orders with its own native Order schema (kafka-topics --confluent-value-association)"
playground topic create --topic orders -- --confluent-value-association /data/order-association.json

NATIVE_SUBJECT=":.${CLUSTER_ID}:orders-value"
log "🔍 Look up the associations of topic orders: subject ${NATIVE_SUBJECT}, lifecycle STRONG"
wait_for_associations "resources/${CLUSTER_ID}/orders" 1
if [ "$(get_associations "resources/${CLUSTER_ID}/orders" | jq -r '.[0].lifecycle')" != "STRONG" ]
then
    logerror "❌ the association of topic orders should be STRONG (native schema)"
    exit 1
fi

log "🗂️ The native schema lives in the context :.${CLUSTER_ID}: (no orders-value subject in the default context)"
playground schema get --subject orders-value --context ".${CLUSTER_ID}"

log "📤 Produce to orders: the serializer (AssociatedNameStrategy, the default) finds the native subject through the association"
playground topic produce --topic orders --nb-messages 5 --value "${DIR}/order.avsc"
playground topic consume --topic orders --min-expected-messages 5 --timeout 60

if playground schema get --subject orders-value > /dev/null 2>&1
then
    logerror "❌ subject orders-value should not exist in the default context: the producer should have used ${NATIVE_SUBJECT}"
    exit 1
fi

########################
# Shared schema (WEAK)
########################
log "⏺️ Register the shared Customer schema under subject Customer"
playground schema register --subject Customer --schema "@${DIR}/customer.avsc"

log "🔗 Associate topic customer-signups with the existing subject Customer"
playground topic create --topic customer-signups
# {"subject": "Customer"} (customer-association.json, mounted in the broker)
playground topic alter --topic customer-signups --confluent-value-association /data/customer-association.json

log "🔍 Look up the topics associated with subject Customer: customer-signups, lifecycle WEAK"
wait_for_associations "subjects/Customer" 1
if [ "$(get_associations "subjects/Customer" | jq -r '.[0].lifecycle')" != "WEAK" ]
then
    logerror "❌ the association of subject Customer should be WEAK (shared schema)"
    exit 1
fi

log "📤 Produce to customer-signups: the schema is found under subject Customer, no customer-signups-value subject is created"
playground topic produce --topic customer-signups --nb-messages 5 --value "${DIR}/customer.avsc"
# topic consume finds the schema with TopicNameStrategy only: --value-subject to decode the records of an associated topic
playground topic consume --topic customer-signups --value-subject Customer --min-expected-messages 5 --timeout 60

if playground schema get --subject customer-signups-value > /dev/null 2>&1
then
    logerror "❌ subject customer-signups-value should not exist: the producer should have used subject Customer"
    exit 1
fi

log "🛡️ Deleting subject Customer is blocked while a topic is associated with it (error 40904)"
set +e
playground schema delete --subject Customer
set -e
# 🔥 ❌ Command failed with error code 40904
# 🔥 An association already exists for subject 'Customer'
if ! playground schema get --subject Customer > /dev/null 2>&1
then
    logerror "❌ subject Customer should not be deletable while topic customer-signups is associated with it"
    exit 1
fi

log "✂️ Unlink topic customer-signups: the shared subject Customer stays"
playground topic alter --topic customer-signups --delete-config confluent.value.association
wait_for_associations "subjects/Customer" 0
playground schema get --subject Customer

########################
# Delete the topic with the native schema
########################
log "❌ Delete topic orders (without the playground subject cleanup): Schema Registry deletes its native subject"
playground topic delete --topic orders --skip-delete-schema
wait_for_associations "resources/${CLUSTER_ID}/orders" 0

MAX_WAIT=60
CUR_WAIT=0
while playground schema get --subject orders-value --context ".${CLUSTER_ID}" > /dev/null 2>&1
do
    sleep 2
    CUR_WAIT=$(( CUR_WAIT+2 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ native subject ${NATIVE_SUBJECT} still exists $MAX_WAIT seconds after topic orders was deleted"
        exit 1
    fi
done
log "✅ native subject ${NATIVE_SUBJECT} was deleted together with topic orders"
