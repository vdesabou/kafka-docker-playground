#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

bootstrap_ccloud_environment


connector_name="DatagenSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "DatagenSource",
     "name": "DatagenSource",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "kafka.topic" : "pageviews",
     "output.data.format" : "AVRO",
     "quickstart" : "PAGEVIEWS",
     "max.interval": "10000",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Verifying topic pageviews"
playground topic consume --topic pageviews --min-expected-messages 5 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name