#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi
INSTANCE=${2:-test-instance}
DATABASE=${3:-example-db}

cd ../../connect/connect-gcp-spanner-sink
GCP_KEYFILE="${PWD}/keyfile.json"
if [ ! -f ${GCP_KEYFILE} ] && [ -z "$GCP_KEYFILE_CONTENT" ]
then
     logerror "ERROR: either the file ${GCP_KEYFILE} is not present or environment variable GCP_KEYFILE_CONTENT is not set!"
     exit 1
else 
    if [ -f ${GCP_KEYFILE} ]
    then
        GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`
    else
        log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
        echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    fi
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

set +e
log "Deleting Database and Instance, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases delete $DATABASE --instance $INSTANCE --project $GCP_PROJECT << EOF
Y
EOF
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances delete $INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF
set -e
log "Create a Spanner Instance and Database"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances create $INSTANCE --project $GCP_PROJECT --config=regional-us-east1 --description=playground-spanner-instance --nodes=1
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases create $DATABASE --instance $INSTANCE --project $GCP_PROJECT

log "Sending messages to topic products"
playground topic produce -t products --nb-messages 2 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF

playground topic produce -t products --nb-messages 1 --forced-value '{"name": "notebooks", "price": 1.99, "quantity": 5}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF


log "Creating GCP Spanner Sink connector"
playground connector create-or-update --connector gcp-spanner-sink  << EOF
{
  "connector.class": "io.confluent.connect.gcp.spanner.SpannerSinkConnector",
  "tasks.max" : "1",
  "topics" : "products",
  "auto.create" : "true",
  "table.name.format" : "kafka_\${topic}",
  "gcp.spanner.instance.id" : "$INSTANCE",
  "gcp.spanner.database.id" : "$DATABASE",
  "gcp.spanner.credentials.path" : "/tmp/keyfile.json",
  "confluent.license": "",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1"
}
EOF

sleep 60

log "Verify data is in GCP Spanner"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases execute-sql $DATABASE --instance $INSTANCE --project $GCP_PROJECT --sql='select * from kafka_products' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "notebooks" /tmp/result.log

log "Deleting Database and Instance"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases delete $DATABASE --instance $INSTANCE --project $GCP_PROJECT << EOF
Y
EOF
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances delete $INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF

docker rm -f gcloud-config