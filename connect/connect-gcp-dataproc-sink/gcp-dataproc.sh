#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


logerror "Connector must be deployed on a VM on same GCP subnet as the Dataproc cluster. Hence it cannot be working with the playground."
exit 1


KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

PROJECT=${1:-vincent-de-saboulin-lab}
CLUSTER_NAME=${2:-playground-cluster}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -ti -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json


log "Creating Dataproc cluster $CLUSTER_NAME"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud dataproc clusters create "$CLUSTER_NAME" --region us-east1 --project "$PROJECT"

log "Sending messages to topic test_dataproc"
seq -f "{\"f1\": \"value%g-`date`\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_dataproc --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'


log "Creating GCP Dataproc Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcp.dataproc.DataprocSinkConnector",
               "tasks.max" : "1",
               "flush.size": "3",
               "topics" : "test_dataproc",
               "gcp.dataproc.projectId": "'"$PROJECT"'",
               "gcp.dataproc.region": "us-east1",
               "gcp.dataproc.cluster": "'"$CLUSTER_NAME"'",
               "gcp.dataproc.credentials.path" : "/root/keyfiles/keyfile.json",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/gcp-dataproc-sink/config | jq .

sleep 10

# [2020-02-03 14:51:05,609] INFO Shutting down DataprocSinkConnector. (io.confluent.connect.gcp.dataproc.hdfs.HdfsSinkTask)
# [2020-02-03 14:51:05,611] ERROR WorkerSinkTask{id=gcp-dataproc-sink-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: java.lang.reflect.InvocationTargetException
#         at io.confluent.connect.storage.StorageFactory.createStorage(StorageFactory.java:55)
#         at io.confluent.connect.gcp.dataproc.hdfs.DataWriter.<init>(DataWriter.java:196)
#         at io.confluent.connect.gcp.dataproc.hdfs.DataWriter.<init>(DataWriter.java:92)
#         at io.confluent.connect.gcp.dataproc.hdfs.HdfsSinkTask.start(HdfsSinkTask.java:72)
#         at io.confluent.connect.gcp.dataproc.DataprocSinkTask.start(DataprocSinkTask.java:56)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.initializeAndStart(WorkerSinkTask.java:301)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.lang.reflect.InvocationTargetException
#         at sun.reflect.NativeConstructorAccessorImpl.newInstance0(Native Method)
#         at sun.reflect.NativeConstructorAccessorImpl.newInstance(NativeConstructorAccessorImpl.java:62)
#         at sun.reflect.DelegatingConstructorAccessorImpl.newInstance(DelegatingConstructorAccessorImpl.java:45)
#         at java.lang.reflect.Constructor.newInstance(Constructor.java:423)
#         at io.confluent.connect.storage.StorageFactory.createStorage(StorageFactory.java:50)
#         ... 13 more
# Caused by: java.lang.IllegalArgumentException: java.net.UnknownHostException: playground-cluster-m
#         at org.apache.hadoop.security.SecurityUtil.buildTokenService(SecurityUtil.java:443)
#         at org.apache.hadoop.hdfs.NameNodeProxiesClient.createProxyWithClientProtocol(NameNodeProxiesClient.java:132)
#         at org.apache.hadoop.hdfs.DFSClient.<init>(DFSClient.java:351)
#         at org.apache.hadoop.hdfs.DFSClient.<init>(DFSClient.java:285)
#         at org.apache.hadoop.hdfs.DistributedFileSystem.initialize(DistributedFileSystem.java:164)
#         at org.apache.hadoop.fs.FileSystem.createFileSystem(FileSystem.java:3242)
#         at org.apache.hadoop.fs.FileSystem.access$200(FileSystem.java:121)
#         at org.apache.hadoop.fs.FileSystem$Cache.getInternal(FileSystem.java:3291)
#         at org.apache.hadoop.fs.FileSystem$Cache.getUnique(FileSystem.java:3265)
#         at org.apache.hadoop.fs.FileSystem.newInstance(FileSystem.java:523)
#         at io.confluent.connect.gcp.dataproc.hdfs.storage.HdfsStorage.<init>(HdfsStorage.java:44)
#         ... 18 more
# Caused by: java.net.UnknownHostException: playground-cluster-m
#         ... 29 more

# log "Listing content of /topics/test_hdfs in HDFS"
# docker exec hadoop bash -c "/usr/local/hadoop/bin/hdfs dfs -ls /topics/test_hdfs"

# log "Getting one of the avro files locally and displaying content with avro-tools"
# docker exec hadoop bash -c "/usr/local/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/f1=value1/test_hdfs+0+0000000000+0000000000.avro /tmp"
# docker cp hadoop:/tmp/test_hdfs+0+0000000000+0000000000.avro /tmp/


docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000000.avro

docker rm -f gcloud-config

log "Deleting Dataproc cluster $CLUSTER_NAME"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest echo y | gcloud dataproc clusters delete "$CLUSTER_NAME" --region us-east1 --project "$PROJECT"
