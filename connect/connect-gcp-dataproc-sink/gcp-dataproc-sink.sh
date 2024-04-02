#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


logerror "Connector must be deployed on a VM on same GCP subnet as the Dataproc cluster. Hence it cannot be working with the playground."
exit 1


cd ../../connect/connect-gcp-cloud-functions-sink
GCP_KEYFILE="${PWD}/keyfile.json"
if [ ! -f ${GCP_KEYFILE} ] && [ -z "$GCP_KEYFILE_CONTENT" ]
then
     logerror "ERROR: either the file ${GCP_KEYFILE} is not present or environment variable GCP_KEYFILE_CONTENT is not set!"
     exit 1
else 
    if [ -f ${GCP_KEYFILE} ]
    then
        GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
    else
        log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
        echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    fi
fi
cd -

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi
CLUSTER_NAME=${2:-playground-cluster}

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json


log "Creating Dataproc cluster $CLUSTER_NAME"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud dataproc clusters create "$CLUSTER_NAME" --region us-east1 --project "$GCP_PROJECT"

log "Sending messages to topic test_dataproc"
playground topic produce -t test_dataproc --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

log "Creating GCP Dataproc Sink connector"
playground connector create-or-update --connector gcp-dataproc-sink  << EOF
{
    "connector.class": "io.confluent.connect.gcp.dataproc.DataprocSinkConnector",
    "tasks.max" : "1",
    "flush.size": "3",
    "topics" : "test_dataproc",
    "gcp.dataproc.projectId": "$GCP_PROJECT",
    "gcp.dataproc.region": "us-east1",
    "gcp.dataproc.cluster": "$CLUSTER_NAME",
    "gcp.dataproc.credentials.path" : "/tmp/keyfile.json",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

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


docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000000.avro

docker rm -f gcloud-config

log "Deleting Dataproc cluster $CLUSTER_NAME"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest echo y | gcloud dataproc clusters delete "$CLUSTER_NAME" --region us-east1 --project "$GCP_PROJECT"
