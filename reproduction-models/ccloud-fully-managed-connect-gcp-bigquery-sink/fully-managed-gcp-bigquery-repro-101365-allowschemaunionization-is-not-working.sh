#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG}
DATASET=${DATASET//[-._]/}

file="producer-repro-101365-customer.avsc"
mkdir -p producer-repro-101365/src/main/resources/avro
cd producer-repro-101365/src/main/resources/avro/
get_3rdparty_file "$file"
if [ ! -f $file ]
then
     logerror "ERROR: $file is missing"
     exit 1
else
     mv $file customer.avsc
fi
cd -

file="producer-repro-101365-2-customer.avsc"
mkdir -p producer-repro-101365-2/src/main/resources/avro
cd producer-repro-101365-2/src/main/resources/avro/
get_3rdparty_file "$file"
if [ ! -f $file ]
then
     logerror "ERROR: $file is missing"
     exit 1
else
     mv $file customer.avsc
fi
cd -

for component in producer-repro-101365 producer-repro-101365-2
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

docker-compose build
docker-compose down -v --remove-orphans
docker-compose up -d

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop dataset $DATASET, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"
set -e

log "Create dataset $PROJECT.$DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"

log "Creating customer_avro topic in Confluent Cloud"
set +e
delete_topic customer_avro
sleep 5
create_topic customer_avro
set -e

log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-101365 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

cat << EOF > connector.json
{
     "connector.class": "BigQuerySink",
     "name": "BigQuerySink",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "topics": "customer_avro",
     "keyfile" : $KEYFILE_CONTENT,
     "project" : "$PROJECT",
     "datasets" : "$DATASET",
     "input.data.format" : "AVRO",
     "auto.create.tables" : "true",
     "sanitize.topics" : "true",
     "auto.update.schemas" : "true",
     "sanitize.field.names" : "false",
     "allow.schema.unionization" : "true",
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

log "Sleeping 120 seconds"
sleep 120

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log

log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-101365-2 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

# log "Do you want to delete the fully managed connector ?"
# check_if_continue

# log "Deleting fully managed connector"
# delete_ccloud_connector connector.json

# log "Drop dataset $DATASET"
# docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"

# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:597)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:331)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:233)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:202)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1130)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:630)
# 	at java.base/java.lang.Thread.run(Thread.java:831)
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Some write threads encountered unrecoverable errors: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write rows after BQ table creation or schema update within 30 attempts for: GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgec2userds711, tableId=customer_avro}}; See logs for more detail
# 	at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredErrors(KCBQThreadPoolExecutor.java:108)
# 	at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:233)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:565)
# 	... 10 more
