#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.3.14"
then
    logwarn "WARN: connector version >= 1.3.15 do not support CP versions < 6.0.0"
    exit 111
fi

logwarn "⚠️ This example and associated custom code is not supported, use at your own risks !"

AWS_STS_ROLE_ARN=${AWS_STS_ROLE_ARN:-$1}

if [ -z "$AWS_STS_ROLE_ARN" ]
then
     logerror "AWS_STS_ROLE_ARN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID" ]
then
     logerror "AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY" ]
then
     logerror "AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

handle_aws_credentials

for component in awscredentialsprovider
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.assuming-iam-role-with-custom-awscredentialsprovider.yml"

KINESIS_STREAM_NAME=pg${USER}${TAG}
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME//[-.]/}

set +e
log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION
set -e

sleep 5

log "Create a Kinesis stream $KINESIS_STREAM_NAME"
aws kinesis create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1 --region $AWS_REGION

function cleanup_cloud_resources {
    set +e
    log "Delete the Kinesis stream"
    check_if_continue
    aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION
}
trap cleanup_cloud_resources EXIT

log "Sleep 60 seconds to let the Kinesis stream being fully started"
sleep 60

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into kafka_docker_playground.
aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1 --region $AWS_REGION

log "Creating Kinesis Source connector"
playground connector create-or-update --connector kinesis-source  << EOF
{
    "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
    "tasks.max": "1",
    "kafka.topic": "kinesis_topic",
    "kinesis.stream": "$KINESIS_STREAM_NAME",
    "kinesis.region": "$AWS_REGION",
    "kinesis.credentials.provider.class": "com.github.vdesabou.AwsAssumeRoleCredentialsProvider",
    "kinesis.credentials.provider.sts.role.arn": "$AWS_STS_ROLE_ARN",
    "kinesis.credentials.provider.sts.role.session.name": "session-name",
    "kinesis.credentials.provider.sts.role.external.id": "123",
    "kinesis.credentials.provider.sts.aws.access.key.id": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID",
    "kinesis.credentials.provider.sts.aws.secret.key.id": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

log "Verify we have received the data in kinesis_topic topic"
playground topic consume --topic kinesis_topic --min-expected-messages 1 --timeout 60