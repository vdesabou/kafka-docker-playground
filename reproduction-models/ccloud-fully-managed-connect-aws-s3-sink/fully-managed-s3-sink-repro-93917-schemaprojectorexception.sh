#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-repro-93917 producer-repro-93917-2
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME | awk -F'=' '{print $2;}' )
export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME | awk -F'=' '{print $2;}' )

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

docker-compose build
docker-compose down -v --remove-orphans
docker-compose up -d

AWS_BUCKET_NAME=kafka-docker-playground-93917
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}

#AWS_REGION=$(aws configure get region | tr '\r' '\n')
AWS_REGION=us-west-2
log "Creating bucket name <$AWS_BUCKET_NAME>, if required"
set +e
aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME --recursive --region $AWS_REGION
set -e

log "Creating customer_avro topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
delete_topic customer_avro
create_topic customer_avro
set -e

log "Sending messages to topic customer_avro"

cat << EOF > connector.json
{
     "connector.class": "S3_SINK",
     "name": "S3_SINK",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "topics": "customer_avro",
     "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
     "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
     "input.data.format": "AVRO",
     "output.data.format": "JSON",
     "s3.bucket.name": "$AWS_BUCKET_NAME",
     "time.interval" : "HOURLY",
     "flush.size": "1000",
     "compression.codec": "JSON - gzip",
     "s3.compression.level": "9",
     "locale": "en",
     "schema.compatibility": "BACKWARD",
     "value.converter.connect.meta.data": "true",
     "tasks.max" : "1"
}
EOF

log "Connector configuration is:"
cat connector.json

set +e
log "Deleting fully managed connector, it might fail..."
delete_ccloud_connector connector.json
set -e

log "Creating fully managed connector"
create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300

log "Register first version using producer-repro-93917/src/main/resources/avro/customer.avsc"
escaped_json=$(jq -c -Rs '.' producer-repro-93917/src/main/resources/avro/customer.avsc)
# fix this not working
base64_auth=$(echo "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" | base64)
base64_auth=${base64_auth::-4}
cat << EOF > /tmp/final.json
{"schema":$escaped_json}
EOF

log "Register new version v1 for schema customer_avro-value"
curl -X POST $SCHEMA_REGISTRY_URL/subjects/customer_avro-value/versions \
--header 'Content-Type: application/vnd.schemaregistry.v1+json' \
--header 'Authorization: Basic $base64_auth' \
--data @/tmp/final.json

log "✨ Run a java producer with schema v1 which produces to topic customer_avro, it runs 1 message per second"
docker exec -d producer-repro-93917 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Register second version using producer-repro-93917-2/src/main/resources/avro/customer.avsc"
escaped_json=$(jq -c -Rs '.' producer-repro-93917-2/src/main/resources/avro/customer.avsc)

cat << EOF > /tmp/final.json
{"schema":$escaped_json}
EOF

log "Register new version v2 for schema customer_avro-value"
curl -X POST $SCHEMA_REGISTRY_URL/subjects/customer_avro-value/versions \
--header 'Content-Type: application/vnd.schemaregistry.v1+json' \
--header 'Authorization: Basic $base64_auth' \
--data @/tmp/final.json

log "✨ Run a java producer with schema v2 which produces to topic customer_avro, it runs 1 message per second"
docker exec -d producer-repro-93917-2 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
