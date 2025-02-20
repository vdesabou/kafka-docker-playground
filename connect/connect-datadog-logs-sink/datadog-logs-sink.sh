#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

DD_API_KEY=${DD_API_KEY:-$1}
DD_SITE=${DD_SITE:-$2}
DD_APP_KEY=${DD_APP_KEY:-$3}

if [ -z "$DD_API_KEY" ]
then
     logerror "DD_API_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DD_SITE" ]
then
     logerror "DD_SITE is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DD_APP_KEY" ]
then
     logerror "DD_APP_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic datadog-logs-topic"
TIMESTAMP=`date +%s`
playground topic produce -t datadog-logs-topic --nb-messages 1 --value="This is a log line"

log "Creating Datadog logs sink connector"
playground connector create-or-update --connector datadog-logs-sink  << EOF
{
     "connector.class": "com.datadoghq.connect.logs.DatadogLogsSinkConnector",
     "tasks.max": "1",
     "key.converter":"org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor":1,
     "datadog.api_key": "$DD_API_KEY",
     "datadog.site": "$DD_SITE",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "behavior.on.error": "fail",
     "topics": "datadog-logs-topic"
}
EOF

sleep 20


log "Make sure logs is present in Datadog"

curl -s -X POST "https://api.$DD_SITE/api/v2/logs/events/search" \
-H "Content-Type: application/json" \
-H "DD-API-KEY: $DD_API_KEY" \
-H "DD-APPLICATION-KEY: $DD_APP_KEY" \
--data-raw '{
   "page": {
    "limit":1
  },
  "sort":"-timestamp"
}' > /tmp/result.log

grep "This is a log line" /tmp/result.log
