#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function register_new_versions() {
     rm -f /tmp/added-fields.json
     rm -f /tmp/repro-93917-schema-v*.json
     rm -f /tmp/final.json
     for((i=0;i<100;i++))
     do
          # Create file
          cat producer-repro-93917/repro-93917-schema-template-begin > /tmp/repro-93917-schema-v$i.json

cat << EOF >> /tmp/added-fields.json
            {
                "default": null,
                "doc": "my added field $i",
                "name": "added_field_$i",
                "type": [
                    "null",
                    "string"
                ]
            },
EOF
          cat /tmp/added-fields.json >> /tmp/repro-93917-schema-v$i.json
          cat producer-repro-93917/repro-93917-schema-template-end >> /tmp/repro-93917-schema-v$i.json

          # register new version
          escaped_json=$(jq -c -Rs '.' /tmp/repro-93917-schema-v$i.json)

cat << EOF > /tmp/final.json
{"schema":$escaped_json}
EOF

          log "Register new version v$i for schema customer_avro-value"
          curl -X POST http://localhost:8081/subjects/customer_avro-value/versions \
          --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
          --data @/tmp/final.json

          sleep 10
     done
}

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

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

for component in producer-repro-93917
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-93917-schemaprojectorexception:-error-projecting.yml"

AWS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}

AWS_REGION=$(aws configure get region | tr '\r' '\n')
log "Creating bucket name <$AWS_BUCKET_NAME>, if required"
set +e
aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME --recursive --region $AWS_REGION
set -e

log "Creating S3 Sink connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "customer_avro",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "s3.part.size": 52428801,
               "flush.size": "5000",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
               "schema.compatibility": "BACKWARD",
               "behavior.on.null.values": "ignore",
               "connect.meta.data": "false",
               "enhanced.avro.schema.support": "true",
               "rotate.interval.ms": "180000",
               "schemas.cache.config": "1000",
               "s3.compression.type": "gzip",
               "s3.compression.level": "9",
               "s3.part.retries" : "10000",
               "s3.part.size": "5242880",

               "locale": "en",
               "partition.duration.ms": "3600000",
               "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
               "path.format": "YYYY/MM/dd/HH",
               "timestamp.extractor": "Record",
               "timestamp.field": "timestamp",
               "timezone": "UTC"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .

# PartitionerConfig values: 
# 	locale = en
# 	partition.duration.ms = 3600000
# 	partition.field.name = []
# 	partitioner.class = class io.confluent.connect.storage.partitioner.TimeBasedPartitioner
# 	path.format = YYYY/MM/dd/HH
# 	timestamp.extractor = Record
# 	timestamp.field = timestamp
# 	timezone = UTC

log "✨ Run 5 java producers which produces to topic customer_avro"
docker exec -d producer-repro-93917 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -d producer-repro-93917 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -d producer-repro-93917 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -d producer-repro-93917 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"
docker exec -d producer-repro-93917 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

register_new_versions

