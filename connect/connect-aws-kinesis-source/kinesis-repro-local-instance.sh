#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# This is required even though we use a local instance !
if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ ! -f $HOME/.aws/credentials ]
then
     logerror "ERROR: $HOME/.aws/credentials is not set"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-local-instance.yml"

log "Create a Kinesis stream my_kinesis_stream"
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ create-stream --stream-name my_kinesis_stream --shard-count 1

log "Sleep 10 seconds to let the Kinesis stream being fully started"
sleep 10

TODAY=$(date +%s)
log "Creating Kinesis Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.base.url": "http://kinesis-local:4567",
               "kinesis.stream": "my_kinesis_stream",
               "kinesis.position": "AT_TIMESTAMP",
               "kinesis.shard.timestamp": "'"$TODAY"'",
               "kinesis.region": "eu-west-3",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kinesis-source-local/config | jq .

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into my_kinesis_stream.
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ put-record --stream-name my_kinesis_stream --partition-key 123 --data test-message-1

sleep 10

log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ delete-stream --stream-name my_kinesis_stream