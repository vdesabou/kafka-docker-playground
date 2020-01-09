#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "aws"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# cleanup
set +e
aws logs delete-log-group --log-group my-log-group
set -e

echo -e "\033[0;33mCreate a log group in AWS CloudWatch Logs.\033[0m"
aws logs create-log-group --log-group my-log-group

echo -e "\033[0;33mCreate a log stream in AWS CloudWatch Logs.\033[0m"
aws logs create-log-stream --log-group my-log-group --log-stream my-log-stream

echo -e "\033[0;33mInsert Records into your log stream.\033[0m"
# If this is the first time inserting logs into a new log stream, then no sequence token is needed.
# However, after the first put, there will be a sequence token returned that will be needed as a parameter in the next put.
aws logs put-log-events --log-group my-log-group --log-stream my-log-stream --log-events timestamp=`date +%s000`,message="This is a log #0"

echo -e "\033[0;33mInjecting more messages\033[0m"
for i in $(seq 1 10)
do
     token=$(aws logs describe-log-streams --log-group my-log-group | jq -r .logStreams[0].uploadSequenceToken)
     aws logs put-log-events --log-group my-log-group --log-stream my-log-stream --log-events timestamp=`date +%s000`,message="This is a log #${i}" --sequence-token ${token}
done

echo -e "\033[0;33mCreating AWS CloudWatch Logs Source connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.aws.cloudwatch.AwsCloudWatchSourceConnector",
                    "tasks.max": "1",
                    "aws.cloudwatch.logs.url": "https://logs.us-east-1.amazonaws.com",
                    "aws.cloudwatch.log.group": "my-log-group",
                    "aws.cloudwatch.log.streams": "my-log-stream",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-cloudwatch-logs-source/config | jq .

sleep 5

echo -e "\033[0;33mVerify we have received the data in my-log-group.my-log-stream topic\033[0m"
docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic my-log-group.my-log-stream --from-beginning --max-messages 10
