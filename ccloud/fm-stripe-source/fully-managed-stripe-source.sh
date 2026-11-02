#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

STRIPE_API_KEY=${STRIPE_API_KEY:-$1}

if [ -z "$STRIPE_API_KEY" ]
then
     logerror "STRIPE_API_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$STRIPE_API_KEY" == sk_live_* ]] || [[ "$STRIPE_API_KEY" == rk_live_* ]]
then
     logerror "STRIPE_API_KEY is a live mode key: use a sandbox (test mode) key, sk_test_... or rk_test_..., this example creates and deletes a customer"
     exit 1
fi

STRIPE_API_URL="https://api.stripe.com/v1"
CUSTOMER_PREFIX="playground-${USER}-${GITHUB_RUN_NUMBER}${TAG_BASE}-$RANDOM"
CUSTOMER_EMAIL="$CUSTOMER_PREFIX@example.com"
CUSTOMER_ID=""

function cleanup_cloud_resources {
    set +e
    if [ -n "$CUSTOMER_ID" ]
    then
        log "Deleting Stripe customer $CUSTOMER_ID ($CUSTOMER_EMAIL)"
        curl -s -X DELETE "$STRIPE_API_URL/customers/$CUSTOMER_ID" -u "$STRIPE_API_KEY:" | jq -c '{id, deleted}'
    fi
}
trap cleanup_cloud_resources EXIT

bootstrap_ccloud_environment

set +e
for topic in stripe-customers stripe-customers_events
do
    playground topic delete --topic $topic
done
sleep 3
for topic in stripe-customers stripe-customers_events
do
    playground topic create --topic $topic --nb-partitions 1
done
set -e

# the connector loads the history from this timestamp, keep it just before the customer creation
INITIAL_START_TIMESTAMP=$(( $(date +%s) - 60 ))

log "Creating Stripe customer $CUSTOMER_EMAIL"
curl -s --fail-with-body -X POST "$STRIPE_API_URL/customers" -u "$STRIPE_API_KEY:" \
    -d email="$CUSTOMER_EMAIL" \
    -d name="Kafka Docker Playground" \
    -d description="created by kafka-docker-playground fully-managed-stripe-source.sh" > /tmp/stripe-customer.json
CUSTOMER_ID=$(jq -r '.id' /tmp/stripe-customer.json)
if [[ "$CUSTOMER_ID" != cus_* ]]
then
    cat /tmp/stripe-customer.json
    logerror "❌ could not create the Stripe customer"
    exit 1
fi
log "Stripe customer $CUSTOMER_ID created"

connector_name="StripeSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "StripeSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "stripe.api.key": "$STRIPE_API_KEY",
    "stripe.resources": "customers",
    "stripe.initial.start.timestamp": "$INITIAL_START_TIMESTAMP",
    "topic.prefix": "stripe-",
    "output.data.format": "AVRO",
    "poll.interval.ms": "10000",
    "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Verify the customer $CUSTOMER_ID is in stripe-customers topic"
playground topic consume --topic stripe-customers --min-expected-messages 1 --grep "$CUSTOMER_ID" --timeout 120

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
