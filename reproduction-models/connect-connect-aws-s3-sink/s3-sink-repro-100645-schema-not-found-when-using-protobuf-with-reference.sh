#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

for component in producer-repro-100645 producer-repro-100645-2
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-100645-schema-not-found-when-using-protobuf-with-reference.yml"

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

log "Register schema for address (id will be 1)"
curl -X POST -H "Content-Type: application/json" -d'
{
  "schemaType": "PROTOBUF",
  "schema": "syntax = \"proto3\";\n\npackage com.github.vdesabou;\n\nmessage Address {\n// comment\nstring street = 1;\n}"
}' \
"http://localhost:8081/subjects/address.proto/versions"

log "Register schema for customer (id will be 2)"
curl -X POST -H "Content-Type: application/json" -d'{
  "schemaType": "PROTOBUF",
  "schema": "syntax = \"proto3\";\n\npackage com.github.vdesabou;\n\nimport \"address.proto\";\n\nmessage Customer {\n// comment\nstring firstName = 1;\nstring lastName = 2;\ncom.github.vdesabou.Address address = 3;\n}",
  "references": [
    {
      "name": "address.proto",
      "subject": "address.proto",
      "version": 1
    }
  ]
}' \
"http://localhost:8081/subjects/customer_protobuf-value/versions"


log "Fetch schema id 2"
curl --request GET \
  --url http://localhost:8081/schemas/ids/2

output=$(curl --request GET --url http://localhost:8081/schemas/ids/2)

log "find the Schema using a POST"
curl --request POST \
  --url http://localhost:8081/subjects/customer_protobuf-value \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data "$output"


log "Creating S3 Sink connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "customer_protobuf",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "s3.part.size": 52428801,
               "flush.size": "3",
               "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.enhanced.protobuf.schema.support":"true",
               "value.converter.connect.meta.data":"false",


               "value.converter.use.latest.version" : "true", 
               "value.converter.latest.compatibility.strict" : "false",

               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "schema.compatibility": "NONE"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .


               #"value.converter.normalize.schemas": "true",
log "✨ Run the protobuf java producer which produces to topic customer_protobuf"
docker exec producer-repro-100645 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing objects of in S3"
aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

# log "Getting one of the avro files locally and displaying content with avro-tools"
# aws s3 cp --only-show-errors s3://$AWS_BUCKET_NAME/topics/customer_protobuf/partition=0/customer_protobuf+0+0000000000.avro customer_protobuf+0+0000000000.avro

# docker run --rm -v ${DIR}:/tmp actions/avro-tools tojson /tmp/customer_protobuf+0+0000000000.avro
# rm -f customer_protobuf+0+0000000000.avro

log "Register schema v2 for address (id=3)"
curl -X POST -H "Content-Type: application/json" -d'
{
  "schemaType": "PROTOBUF",
  "schema": "syntax = \"proto3\";\n\npackage com.github.vdesabou;\n\nmessage Address {\nstring street = 1;\n// comment 2\nstring other = 2;\n}"
}' \
"http://localhost:8081/subjects/address.proto/versions (id=4)"

log "Register schema v2 for customer (id=4)"
curl -X POST -H "Content-Type: application/json" -d'{
  "schemaType": "PROTOBUF",
  "schema": "syntax = \"proto3\";\n\npackage com.github.vdesabou;\n\nimport \"address.proto\";\n\nmessage Customer {\n// comment 2\nstring firstName = 1;\nstring lastName = 2;\ncom.github.vdesabou.Address address = 3;\n}",
  "references": [
    {
      "name": "address.proto",
      "subject": "address.proto",
      "version": 2
    }
  ]
}' \
"http://localhost:8081/subjects/customer_protobuf-value/versions"

log "Fetch schema id 4"
curl --request GET \
  --url http://localhost:8081/schemas/ids/4

output=$(curl --request GET --url http://localhost:8081/schemas/ids/4)

log "find the Schema using a POST"
curl --request POST \
  --url http://localhost:8081/subjects/customer_protobuf-value \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data "$output"


# curl --request DELETE \
#   --url http://localhost:8081/subjects/customer_protobuf-value/versions/1

# curl --request DELETE \
#   --url http://localhost:8081/subjects/address.proto/versions/1

log "✨ Run the protobuf java producer which produces to topic customer_protobuf"
docker exec producer-repro-100645 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"