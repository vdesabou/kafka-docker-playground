#!/bin/bash
set -e

# to be run with --tag 7.3.1 --connector-tag 10.3.3

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

handle_aws_credentials

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000001-stackoverflowerror-with-s3-sink-connector.yml"

AWS_BUCKET_NAME=pg-bucket-${USER}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}


log "Create bucket <$AWS_BUCKET_NAME>, if required"
set +e
if [ "$AWS_REGION" == "us-east-1" ]
then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
    aws s3api put-bucket-tagging --bucket $AWS_BUCKET_NAME --tagging "TagSet=[{Key=cflt_managed_by,Value=user},{Key=cflt_managed_id,Value=$USER}]"
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
    aws s3api put-bucket-tagging --bucket $AWS_BUCKET_NAME --tagging "TagSet=[{Key=cflt_managed_by,Value=user},{Key=cflt_managed_id,Value=$USER}]"
fi
set -e
log "Empty bucket <$AWS_BUCKET_NAME/$TAG>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME/$TAG --recursive --region $AWS_REGION
set -e


log "Creating S3 Sink connector with bucket name <$AWS_BUCKET_NAME>"
playground connector create-or-update --connector s3-sink  << EOF
{
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "tasks.max": "1",
    "topics": "customer_avro",
    "s3.region": "$AWS_REGION",
    "s3.bucket.name": "$AWS_BUCKET_NAME",
    "topics.dir": "$TAG",
    "s3.part.size": "52428801",
    "flush.size": "3",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat",
    "schema.compatibility": "NONE"
}
EOF


playground topic produce -t customer_avro --nb-messages 1 --verbose << 'EOF'
{
    "type": "record",
    "namespace": "acme",
    "name": "Characteristic",
    "fields": [
        {
            "name": "physicalCharacteristic",
            "type": [
                "null",
                {
                    "type": "record",
                    "name": "PhysicalCharacteristic",
                    "fields": [
                        {
                            "name": "children",
                            "type": [
                                "null",
                                {
                                    "type": "array",
                                    "items": "PhysicalCharacteristic"
                                }
                            ],
                            "default": null
                        }
                    ]
                }
            ]
        }
    ]
}
EOF

sleep 10

playground connector status

# 15:18:58 ℹ️ 🧩 Displaying connector(s) status
# Name                           Status       Tasks                          Stack Trace                                       
# -------------------------------------------------------------------------------------------------------------
# s3-sink                        ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:256)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.StackOverflowError
#         at org.apache.avro.Schema$RecordSchema.getFields(Schema.java:902)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:163)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:169)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertUnion(AvroSchemaConverter.java:226)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:182)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:141)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:244)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertFields(AvroSchemaConverter.java:135)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:163)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:169)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertUnion(AvroSchemaConverter.java:226)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:182)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:141)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:244)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertFields(AvroSchemaConverter.java:135)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:163)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:169)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertUnion(AvroSchemaConverter.java:226)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:182)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:141)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:244)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertFields(AvroSchemaConverter.java:135)
#         at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:163)

playground container logs -c connect --wait-for-log "StackOverflowError"
# 15:25:00 ℹ️ ⌛ Waiting up to 600 seconds for message StackOverflowError to be present in connect container logs...
# java.lang.StackOverflowError
# Caused by: java.lang.StackOverflowError
# 15:25:00 ℹ️ The log is there !