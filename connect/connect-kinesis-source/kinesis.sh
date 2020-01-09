#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "aws"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


set +e
echo -e "\033[0;33mDelete the stream\033[0m"
aws kinesis delete-stream --stream-name my_kinesis_stream
set -e

sleep 5

echo -e "\033[0;33mCreate a Kinesis stream my_kinesis_stream\033[0m"
aws kinesis create-stream --stream-name my_kinesis_stream --shard-count 1

echo -e "\033[0;33mSleep 30 seconds to let the Kinesis stream being fully started\033[0m"
sleep 30

echo -e "\033[0;33mInsert records in Kinesis stream\033[0m"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into my_kinesis_stream.
aws kinesis put-record --stream-name my_kinesis_stream --partition-key 123 --data test-message-1


echo -e "\033[0;33mCreating Kinesis Source connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.region": "US_EAST_1",
               "kinesis.stream": "my_kinesis_stream",
               "confluent.license": "",
               "name": "kinesis-source",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kinesis-source/config | jq .

echo -e "\033[0;33mVerify we have received the data in kinesis_topic topic\033[0m"
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1

echo -e "\033[0;33mDelete the stream\033[0m"
aws kinesis delete-stream --stream-name my_kinesis_stream