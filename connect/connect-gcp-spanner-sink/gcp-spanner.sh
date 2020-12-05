#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}
INSTANCE=${2:-test-instance}
DATABASE=${3:-example-db}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Deleting Database and Instance, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases delete $DATABASE --instance $INSTANCE --project $PROJECT << EOF
Y
EOF
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances delete $INSTANCE --project $PROJECT  << EOF
Y
EOF
set -e
log "Create a Spanner Instance and Database"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances create $INSTANCE --project $PROJECT --config=regional-us-east1 --description=playground-spanner-instance --nodes=1
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases create $DATABASE --instance $INSTANCE --project $PROJECT

log "Sending messages to topic products"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic products --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"name","type":"string"},
{"name":"price", "type": "float"}, {"name":"quantity", "type": "int"}]}' << EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF


log "Creating GCP Spanner Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcp.spanner.SpannerSinkConnector",
               "tasks.max" : "1",
               "topics" : "products",
               "auto.create" : "true",
               "table.name.format" : "kafka_${topic}",
               "gcp.spanner.instance.id" : "'"$INSTANCE"'",
               "gcp.spanner.database.id" : "'"$DATABASE"'",
               "gcp.spanner.credentials.path" : "/root/keyfiles/keyfile.json",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/gcp-spanner-sink/config | jq .

sleep 30

log "Verify data is in GCP Spanner"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases execute-sql $DATABASE --instance $INSTANCE --project $PROJECT --sql='select * from kafka_products'

log "Deleting Database and Instance"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases delete $DATABASE --instance $INSTANCE --project $PROJECT << EOF
Y
EOF
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances delete $INSTANCE --project $PROJECT  << EOF
Y
EOF

docker rm -f gcloud-config