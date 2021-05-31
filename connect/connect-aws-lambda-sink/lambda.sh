#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
export AWS_CREDENTIALS_FILE_NAME="credentials"
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic add-topic"
seq -f "{\"a\": %g,\"b\": 1}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic add-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"a","type":"int"},{"name":"b","type":"int"}]}'

log "Creating AWS Lambda Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.aws.lambda.AwsLambdaSinkConnector",
               "tasks.max": "1",
               "topics" : "add-topic",
               "aws.lambda.function.name" : "Add",
               "aws.lambda.invocation.type" : "sync",
               "aws.lambda.batch.size" : "50",
               "aws.lambda.region": "us-east-1",
               "behavior.on.error" : "fail",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-lambda/config | jq .


sleep 10

log "Verify topic success-responses"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 10

# log "Verify topic error-responses"
# timeout 20 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1