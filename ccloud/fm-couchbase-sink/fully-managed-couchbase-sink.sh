#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


COUCHBASE_USERNAME=${COUCHBASE_USERNAME:-$1}
COUCHBASE_PASSWORD=${COUCHBASE_PASSWORD:-$2}
COUCHBASE_HOSTNAME=${COUCHBASE_HOSTNAME:-$3}

if [ -z "$COUCHBASE_USERNAME" ]
then
     logerror "COUCHBASE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$COUCHBASE_PASSWORD" ]
then
     logerror "COUCHBASE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$COUCHBASE_HOSTNAME" ]
then
     logerror "COUCHBASE_HOSTNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

# sed -e "s|:COUCHBASE_HOSTNAME:|$COUCHBASE_HOSTNAME|g" \
#     -e "s|:COUCHBASE_USERNAME:|$COUCHBASE_USERNAME|g" \
#     -e "s|:COUCHBASE_PASSWORD:|$COUCHBASE_PASSWORD|g" \
#     ../../ccloud/fm-couchbase-sink/cbsh-config.template > ../../ccloud/fm-couchbase-sink/cbsh-config

bootstrap_ccloud_environment


# log "Creating Couchbase bucket travel-data"
# cd ../../ccloud/fm-couchbase-sink
# docker run -t -v $PWD/cbsh-config:/home/nonroot/.cbsh/config -v $PWD/create-bucket:/tmp/command vdesabou/cbsh:latest --script /tmp/command
# cd -

set +e
playground topic delete --topic test-travel-sample
sleep 3
playground topic create --topic test-travel-sample --nb-partitions 1
set -e


playground topic produce -t test-travel-sample --nb-messages 5 << 'EOF'
[
{
    "_meta": {
        "topic": "",
        "key": "",
        "relationships": []
    },
    "nested": {
        "phone": "faker.phone.imei()",
        "website": "faker.internet.domainName()"
    },
    "id": "iteration.index",
    "name": "faker.internet.userName()",
    "email": "faker.internet.exampleEmail()",
    "phone": "faker.phone.imei()",
    "website": "faker.internet.domainName()",
    "city": "faker.location.city()",
    "company": "faker.company.name()"
}
]
EOF


connector_name="CouchbaseSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "CouchbaseSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "test-travel-sample",
  "input.data.format": "JSON",
  "couchbase.seed.nodes": "couchbases://$COUCHBASE_HOSTNAME",
  "couchbase.username": "$COUCHBASE_USERNAME",
  "couchbase.password": "$COUCHBASE_PASSWORD",
  "couchbase.bucket": "travel-data",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

playground connector show-lag --connector $connector_name --max-wait 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name