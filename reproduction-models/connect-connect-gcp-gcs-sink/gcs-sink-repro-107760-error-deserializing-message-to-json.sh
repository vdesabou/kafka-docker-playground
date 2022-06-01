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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-107760-error-deserializing-message-to-json.yml"

GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
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
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil -m rm -r gs://$GCS_BUCKET_NAME/topics/gcs_topic_bad
set -e

log "Sending messages to topic gcs_topic_bad"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic gcs_topic_bad << EOF
{"visions":{"sId":"xxxx"},"ctx":{"winId":"xxxx","title":"xxxxx","isIframe":false,"visitId":"xxxx","timing":{"navStart":1653567245664,"loadTime":346},"location":{"protocol":"http","hostname":"toto","pathname":"index.html"}},"wm":{"uId":"xxxxx","permId":-1,"euIdSource":"Identifier","platform":1,"euId":"xxxxx","env":3,"cseuId":"xxxxx"},"time":1653567307179,"misc":"{\"type\":\"pointer\",\"climb\":2}","element":{"xpath":"html[1]/body[1]#page-top/div[4].container/div[1]#schedule.me-row.row.schedule/div[1].col-md-12/ul[1].nav.nav-tabs&role=tablist/li[2]&role=presentation/a[1]&href=\\#day-2&role=tab/small[1].hidden-xs/sup[1]","parentAttributes":["role","href"],"autoQuery":"DIV[id=\"schedule\"] UL LI A","parentIds":["page-top","schedule"],"parentTags":["html","body","div","ul","li","a","small","sup"],"text":"Day 02\n(21\nst\n, October)","parentClasses":["container","me-row","row","schedule","col-md-12","nav","nav-tabs","hidden-xs"]},"version":{"lib":"xxxxx8","abra":"5.0.48","pe":"5.0.2"},"env":{"mobile":false,"ip":"xxxxxx","screen":{"width":800,"height":600},"pageTitle":"xxxxx","url":"xxxx","location":{"city":"Dublin","subdiv":"Leinster","continent":"Europe","country":"Ireland"},"timezone":0,"os":{"version":"10.14.6","name":"MacOS"},"urlWithoutQueryString":"xxxx","browser":{"version":"xxxxx","name":"Chrome"}},"sId":"xxxx","debug":{"eventId":"xxxx","src":"tell","tsDrift":48,"srvTs":1653567306976,"srvTime":"2022-05-26T12:15:06.976Z","srvHst":"xxxxx","uHash":"xxxx","env":"xxxx","fixedTs":1653567307227},"ctm":{},"type":"mousedown"}
EOF


log "Creating GCS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "gcs_topic_bad",
                    "gcs.bucket.name" : "'"$GCS_BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/tmp/keyfile.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.json.JsonFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",

                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/gcs-sink/config | jq .

sleep 10

# [2022-06-01 09:13:39,708] ERROR [gcs-sink|task-0] WorkerSinkTask{id=gcs-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:519)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:494)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:333)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.DataException: Converting byte[] to Kafka Connect data failed due to serialization error: 
#         at org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:324)
#         at org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$5(WorkerSinkTask.java:519)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 13 more
# Caused by: org.apache.kafka.common.errors.SerializationException: Error deserializing message to JSON in topic gcs_topic_bad
#         at org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:66)
#         at org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:322)
#         ... 17 more

log "Listing objects of in GCS"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil ls gs://$GCS_BUCKET_NAME/topics/gcs_topic_bad/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
docker run -i --volumes-from gcloud-config -v /tmp:/tmp/ google/cloud-sdk:latest gsutil cp gs://$GCS_BUCKET_NAME/topics/gcs_topic_bad/partition=0/gcs_topic_bad+0+0000000000.avro /tmp/gcs_topic_bad+0+0000000000.avro

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/gcs_topic_bad+0+0000000000.avro

docker rm -f gcloud-config