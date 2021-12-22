#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_repro () {
     MAX_WAIT=600
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for error Invalid JWT Signature to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep "Invalid JWT Signature" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Invalid JWT Signature' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "The problem has been reproduced !"
}

for component in producer-v1
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile-rcca-5246.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     log "it should be used with a service account with Service Account Admin and Service Account Key Admin roles !!!"
     exit 1
fi

GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}-rcca-5246
GCS_BUCKET_NAME=${GCS_BUCKET_NAME//[-.]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

log "Creating bucket name <$GCS_BUCKET_NAME>, if required"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil mb -p $(cat ${KEYFILE} | jq -r .project_id) gs://$GCS_BUCKET_NAME
set -e

log "Removing existing objects in GCS, if applicable"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil rm -r gs://$GCS_BUCKET_NAME/topics/gcs_topic
set -e

log "Creating file keyfile-rcca-5246.json that will be used by connector"
KEYFILE_QUICKLY_EXPIRING="${DIR}/keyfile-rcca-5246-quickly-expiring-key.json"
cp $KEYFILE $KEYFILE_QUICKLY_EXPIRING

log "Creating certificate valid for 5 minutes"
go build create-quickly-expiring-certs-repro-rcca-5246.go && go run create-quickly-expiring-certs-repro-rcca-5246.go

iam_account=$(cat $KEYFILE | jq -r .client_email)
log "Uploading cert to GCP"
docker run -i --volumes-from gcloud-config -v ${DIR}/pem:/tmp/pem google/cloud-sdk:latest gcloud iam service-accounts keys upload /tmp/pem --iam-account=$iam_account > results.log 2>&1
cat results.log

PRIVATE_KEY_ID=$(grep "name:" results.log | cut -d "/" -f 6)
log "Adding the new key $PRIVATE_KEY_ID in $KEYFILE_QUICKLY_EXPIRING"
PRIVATE_KEY=$(awk '{printf "%s\n", $0}' key)
jq --arg variable "$PRIVATE_KEY" '.private_key = $variable' $KEYFILE_QUICKLY_EXPIRING > /tmp/tmp
cp /tmp/tmp $KEYFILE_QUICKLY_EXPIRING
jq --arg variable "$PRIVATE_KEY_ID" '.private_key_id = $variable' $KEYFILE_QUICKLY_EXPIRING > /tmp/tmp
cp /tmp/tmp $KEYFILE_QUICKLY_EXPIRING

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.rcca-5246.yml"

log "Run Java producer-v1 in background"
docker exec -d producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"

log "Creating GCS Sink connector using keyfile-rcca-5246-quickly-expiring-key.json"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
               "tasks.max" : "1",
               "topics" : "gcs_topic",
               "gcs.bucket.name" : "'"$GCS_BUCKET_NAME"'",
               "gcs.part.size": "5242880",
               "flush.size": "100000000",
               "gcs.credentials.path": "/tmp/keyfile-rcca-5246-quickly-expiring-key.json",
               "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
               "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DailyPartitioner",
               "rotate.schedule.interval.ms": "300000",
               "locale": "en_US",
               "timezone": "UTC",
               "schema.compatibility": "NONE",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/gcs-sink-rcca-5246/config | jq .

wait_for_repro

