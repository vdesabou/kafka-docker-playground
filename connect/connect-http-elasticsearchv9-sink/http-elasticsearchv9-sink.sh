#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.7.9"
then
     logwarn "minimal supported connector version is 1.7.10 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

cd ../../connect/connect-http-elasticsearchv9-sink/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -

cd ../../connect/connect-http-elasticsearchv9-sink
# Copy JAR to confluent-hub
mkdir -p ${DIR}/../../confluent-hub/confluentinc-kafka-connect-http/lib/
cp ../../connect/connect-http-elasticsearchv9-sink/jcl-over-slf4j-2.0.7.jar ${DIR}/../../confluent-hub/confluentinc-kafka-connect-http/lib/
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

#playground debug log-level set --package "org.apache.http" --level TRACE

log "Sending messages to topic mytopic"
playground topic produce -t mytopic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

log "Creating http-elasticsearchv9-sink connector"
playground connector create-or-update --connector http-elasticsearchv9-sink  << EOF
{
    "topics": "mytopic",
    "tasks.max": "1",
    "connector.class": "io.confluent.connect.http.HttpSinkConnector",

    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "reporter.bootstrap.servers": "broker:9092",
    "reporter.error.topic.name": "error-responses",
    "reporter.error.topic.replication.factor": 1,
    "reporter.result.topic.name": "success-responses",
    "reporter.result.topic.replication.factor": 1,
    "reporter.result.topic.value.format": "string",
    "http.api.url": "http://elasticsearch:9200/myindex/_doc",
    "request.body.format" : "json",
    "batch.json.as.array":"false",
    "headers": "Content-Type: application/json"
}
EOF


sleep 10

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/myindex/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"