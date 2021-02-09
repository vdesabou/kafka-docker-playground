#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# This is required even though we use a local instance !
if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ ! -f $HOME/.aws/credentials ]
then
     logerror "ERROR: $HOME/.aws/credentials is not set"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-local-instance.yml"

log "Create a Kinesis stream my_kinesis_stream"
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ create-stream --stream-name my_kinesis_stream --shard-count 1

log "Sleep 10 seconds to let the Kinesis stream being fully started"
sleep 10

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into my_kinesis_stream.
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ put-record --stream-name my_kinesis_stream --partition-key 123 --data test-message-1


log "Creating Kinesis Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.base.url": "http://kinesis-local:4567",
               "kinesis.stream": "my_kinesis_stream",
               "kinesis.region": "eu-west-3",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kinesis-source-local/config | jq .


# FIXTHIS: getting
# [2021-02-09 16:54:53,860] DEBUG Sending Request: POST http://kinesis-local:4567 / Headers: (amz-sdk-invocation-id: e41a01ed-f579-61fa-45a4-6eb3d1e1bc4b, Content-Length: 102, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.GetShardIterator, )  (com.amazonaws.request)
# [2021-02-09 16:54:53,861] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:e41a01ed-f579-61fa-45a4-6eb3d1e1bc4b
# amz-sdk-retry:0/0/500
# content-length:102
# content-type:application/x-amz-json-1.1
# host:kinesis-local:4567
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210209T165453Z
# x-amz-target:Kinesis_20131202.GetShardIterator

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 4c81a23bb5cd2f4e42a9ca1ffa06397e7d16642c791f7286c00486792cbcb640" (com.amazonaws.auth.AWS4Signer)
# [2021-02-09 16:54:53,861] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210209T165453Z
# 20210209/us-east-1/kinesis/aws4_request
# 68fcd0964b91c98de04caa00689160e87f978cb4c8322891003c93bd277268a1" (com.amazonaws.auth.AWS4Signer)
# [2021-02-09 16:54:53,865] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-09 16:54:53,866] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-09 16:54:53,866] DEBUG Received successful response: 200, AWS Request ID: 88264d50-6af7-11eb-a670-e55cd1c7861a (com.amazonaws.request)
# [2021-02-09 16:54:53,866] DEBUG x-amzn-RequestId: 88264d50-6af7-11eb-a670-e55cd1c7861a (com.amazonaws.requestId)
# [2021-02-09 16:54:53,866] DEBUG AWS Extended Request ID: K1infnseI8vX8J03iFjQp7/vtUX5I+iFfYqkEy0ngN4qfpaVKyZr+nHb2MGSN7aninO93T+Wl/3H4pc1bMPJC2QBGX4V0JOI (com.amazonaws.requestId)
# [2021-02-09 16:54:53,866] INFO Using shard iterator AAAAAAAAAAH/ue7Q4Z1g4mn0K+QwEY6rbpZKLkyPCgHu9xP3lbhocPgfDnVAuF1sn2Qisfe8aSOjZkeRJ1Ieu5/yydt7JB/kIXuziW1iOX8+7k/UqGVEckxP5OFlOb/H6De5UeJXwcD89pFjpEtsHyU8omUJZ8U1wu9PXUMcgkKMC76V253oRkoSPm5G4bXxMGVZDBdmJT4PXfL7T5V1Jb7VPb+Lbdc2 for shard shardId-000000000000 (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-09 16:54:53,866] INFO WorkerSourceTask{id=kinesis-source-local-0} Source task finished initialization and start (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-02-09 16:54:53,866] TRACE Polling Kinesis using the following requests: {shardId-000000000000={ShardIterator: AAAAAAAAAAH/ue7Q4Z1g4mn0K+QwEY6rbpZKLkyPCgHu9xP3lbhocPgfDnVAuF1sn2Qisfe8aSOjZkeRJ1Ieu5/yydt7JB/kIXuziW1iOX8+7k/UqGVEckxP5OFlOb/H6De5UeJXwcD89pFjpEtsHyU8omUJZ8U1wu9PXUMcgkKMC76V253oRkoSPm5G4bXxMGVZDBdmJT4PXfL7T5V1Jb7VPb+Lbdc2,Limit: 500}} (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-09 16:54:53,867] TRACE Getting records for the following request: {ShardIterator: AAAAAAAAAAH/ue7Q4Z1g4mn0K+QwEY6rbpZKLkyPCgHu9xP3lbhocPgfDnVAuF1sn2Qisfe8aSOjZkeRJ1Ieu5/yydt7JB/kIXuziW1iOX8+7k/UqGVEckxP5OFlOb/H6De5UeJXwcD89pFjpEtsHyU8omUJZ8U1wu9PXUMcgkKMC76V253oRkoSPm5G4bXxMGVZDBdmJT4PXfL7T5V1Jb7VPb+Lbdc2,Limit: 500}(1 out of 1), shard ID: shardId-000000000000 (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-09 16:54:53,869] DEBUG Sending Request: POST http://kinesis-local:4567 / Headers: (amz-sdk-invocation-id: 0d553d81-0c7a-bb25-b814-2c38c371b1e3, Content-Length: 256, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.GetRecords, )  (com.amazonaws.request)
# [2021-02-09 16:54:53,869] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:0d553d81-0c7a-bb25-b814-2c38c371b1e3
# amz-sdk-retry:0/0/500
# content-length:256
# content-type:application/x-amz-json-1.1
# host:kinesis-local:4567
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210209T165453Z
# x-amz-target:Kinesis_20131202.GetRecords

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# bcdd9709c3d448a9c0e229c05f4b367c7d59628c537a9a8dae75b137721717f4" (com.amazonaws.auth.AWS4Signer)
# [2021-02-09 16:54:53,869] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210209T165453Z
# 20210209/us-east-1/kinesis/aws4_request
# 9377f57e12176ef00b38c460d184547bb536ba159a4a6e55058eeeb79da62f72" (com.amazonaws.auth.AWS4Signer)
# [2021-02-09 16:54:53,879] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-09 16:54:53,892] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-09 16:54:53,892] DEBUG Received successful response: 200, AWS Request ID: 8827ace0-6af7-11eb-a670-e55cd1c7861a (com.amazonaws.request)
# [2021-02-09 16:54:53,892] DEBUG x-amzn-RequestId: 8827ace0-6af7-11eb-a670-e55cd1c7861a (com.amazonaws.requestId)
# [2021-02-09 16:54:53,892] DEBUG AWS Extended Request ID: t2AuLUXgZHC4MWbi8C5FEL2cqILnoRIXRmoQISWmd8HVFNRIBICaEOZ2iqKeJZF0fqXWQSfLy+YpxxK1OVa7GeKSdZezmBAb (com.amazonaws.requestId)
# [2021-02-09 16:54:53,893] TRACE 0 record(s) returned from shard shardId-000000000000. (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-09 16:54:53,893] TRACE Adding record {SequenceNumber: 49615355574873509266424379217405079513857573374438408194,Data: java.nio.HeapByteBuffer[pos=0 lim=9 cap=9],PartitionKey: 123,} to the result (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-09 16:54:53,896] INFO WorkerSourceTask{id=kinesis-source-local-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-02-09 16:54:53,896] INFO WorkerSourceTask{id=kinesis-source-local-0} flushing 0 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-02-09 16:54:53,896] ERROR WorkerSourceTask{id=kinesis-source-local-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# java.lang.NullPointerException
#         at io.confluent.connect.kinesis.RecordConverter.sourceRecord(RecordConverter.java:63)
#         at io.confluent.connect.kinesis.KinesisSourceTask.poll(KinesisSourceTask.java:143)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:289)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:256)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# [2021-02-09 16:54:53,896] ERROR WorkerSourceTask{id=kinesis-source-local-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# [2021-02-09 16:54:53,896] INFO [Producer clientId=connect-worker-producer] Closing the Kafka producer with timeoutMillis = 30000 ms. (org.apache.kafka.clients.producer.KafkaProducer)

log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ delete-stream --stream-name my_kinesis_stream