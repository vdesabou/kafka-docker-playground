#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.2.99"
then
    logwarn "connector version >= 1.3.0 do not support CP versions < 6.0.0"
    exit 111
fi

handle_aws_credentials

DYNAMODB_TABLE="pgfm${USER}dynamocdc${TAG}"

set +e
aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region $AWS_REGION --query 'Table.TableStatus' --output text 2>/dev/null
if [ $? -eq 0 ]
then
  log "Delete table, this might fail"
  aws dynamodb delete-table --table-name $DYNAMODB_TABLE --region $AWS_REGION
  while true; do
      aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region $AWS_REGION --query 'Table.TableStatus' --output text 2>/dev/null
      if [ $? -ne 0 ]
      then
          break
      fi
      sleep 5
  done
fi
set -e

log "Create dynamodb table $DYNAMODB_TABLE"
aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=first_name,AttributeType=S AttributeName=last_name,AttributeType=S \
    --key-schema AttributeName=first_name,KeyType=HASH AttributeName=last_name,KeyType=RANGE \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --endpoint-url https://dynamodb.$AWS_REGION.amazonaws.com \
    --tags Key=cflt_managed_by,Value=user Key=cflt_managed_id,Value="$USER"

log "Waiting for table to be created"
while true
do
    table_status=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region $AWS_REGION --query 'Table.TableStatus' --output text)
    if [ "$table_status" == "ACTIVE" ]
    then
        break
    fi
    sleep 5
done

log "Enable DynamoDB Streams"
aws dynamodb update-table --table-name "$DYNAMODB_TABLE" --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES --endpoint-url https://dynamodb.$AWS_REGION.amazonaws.com

function cleanup_cloud_resources {
    set +e
    log "Delete table $DYNAMODB_TABLE"
    check_if_continue
    aws dynamodb delete-table --table-name $DYNAMODB_TABLE --region $AWS_REGION
}
trap cleanup_cloud_resources EXIT

bootstrap_ccloud_environment "aws" "$AWS_REGION"

set +e
playground topic delete --topic dynamo_cdc_input
sleep 3
playground topic create --topic dynamo_cdc_input --nb-partitions 1

playground topic delete --topic $DYNAMODB_TABLE
sleep 3
playground topic create --topic $DYNAMODB_TABLE --nb-partitions 1
set -e

log "Sending messages to topic dynamo_cdc_input"
playground topic produce -t dynamo_cdc_input --nb-messages 10 << 'EOF'
{
  "fields": [
    {
      "name": "first_name",
      "type": "string"
    },
    {
      "name": "last_name",
      "type": "string"
    }
  ],
  "name": "Customer",
  "namespace": "com.github.vdesabou",
  "type": "record"
}
EOF

connector_name="DynamoDbSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating AWS DynamoDB sink connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "DynamoDbSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "input.data.format": "AVRO",
    "table.name.format": "$DYNAMODB_TABLE",
    "topics": "dynamo_cdc_input",
    "aws.dynamodb.endpoint": "https://dynamodb.$AWS_REGION.amazonaws.com",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

playground connector show-lag --max-wait 300

log "Verify data is in DynamoDB"
aws dynamodb scan --table-name $DYNAMODB_TABLE --region $AWS_REGION  > /tmp/result.log  2>&1
cat /tmp/result.log
grep "first_name" /tmp/result.log

connector_name2="DynamoDbCdcSource_$USER"
set +e
playground connector delete --connector $connector_name2 > /dev/null 2>&1
set -e

log "Creating AWS DynamodDB CDC Source connector"
playground connector create-or-update --connector $connector_name2 << EOF
{
    "connector.class": "DynamoDbCdcSource",
    "name": "$connector_name2",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "output.data.format": "AVRO",
    "dynamodb.service.endpoint": "https://dynamodb.$AWS_REGION.amazonaws.com",
    "dynamodb.table.includelist": "$DYNAMODB_TABLE",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name2 180


log "Verify we have received the data in $DYNAMODB_TABLE topic"
playground topic consume --topic $DYNAMODB_TABLE --min-expected-messages 10 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name

log "Do you want to delete the fully managed connector $connector_name2 ?"
check_if_continue

playground connector delete --connector $connector_name2


# 17:38:00 ℹ️ ✨ Display content of topic pgvsaboulindynamocdc7.6.1, it contains 10 messages
# 17:38:01 ℹ️ 🔮🔰 topic is using avro for key
# 17:38:03 ℹ️ 🔰 subject pgvsaboulindynamocdc7.6.1-key 💯 version 1 (id 105050)
# {
#   "type": "record",
#   "name": "ConnectDefault",
#   "namespace": "io.confluent.connect.avro",
#   "fields": [
#     {
#       "name": "first_name",
#       "type": "string"
#     },
#     {
#       "name": "last_name",
#       "type": "string"
#     }
#   ]
# }
# 17:38:03 ℹ️ 🔮🔰 topic is using avro for value
# 17:38:05 ℹ️ 🔰 subject pgvsaboulindynamocdc7.6.1-value 💯 version 1 (id 105051)
# [
#   "null",
#   {
#     "type": "record",
#     "name": "Envelope",
#     "namespace": "io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1",
#     "fields": [
#       {
#         "name": "op",
#         "type": "string"
#       },
#       {
#         "name": "ts_ms",
#         "type": "long"
#       },
#       {
#         "name": "ts_us",
#         "type": "long"
#       },
#       {
#         "name": "ts_ns",
#         "type": "long"
#       },
#       {
#         "name": "source",
#         "type": [
#           "null",
#           {
#             "type": "record",
#             "name": "Source",
#             "namespace": "io.confluent.connector.dynamodb",
#             "fields": [
#               {
#                 "name": "version",
#                 "type": [
#                   "null",
#                   "string"
#                 ],
#                 "default": null
#               },
#               {
#                 "name": "tableName",
#                 "type": "string"
#               },
#               {
#                 "name": "sync_mode",
#                 "type": "string"
#               },
#               {
#                 "name": "ts_ms",
#                 "type": "long"
#               },
#               {
#                 "name": "ts_us",
#                 "type": "long"
#               },
#               {
#                 "name": "ts_ns",
#                 "type": "long"
#               },
#               {
#                 "name": "snapshotStartTime",
#                 "type": [
#                   "null",
#                   "long"
#                 ],
#                 "default": null
#               },
#               {
#                 "name": "snapshotCount",
#                 "type": [
#                   "null",
#                   "int"
#                 ],
#                 "default": null
#               },
#               {
#                 "name": "segment",
#                 "type": [
#                   "null",
#                   "int"
#                 ],
#                 "default": null
#               },
#               {
#                 "name": "totalSegments",
#                 "type": [
#                   "null",
#                   "int"
#                 ],
#                 "default": null
#               },
#               {
#                 "name": "shard_id",
#                 "type": [
#                   "null",
#                   "string"
#                 ],
#                 "default": null
#               },
#               {
#                 "name": "seq_no",
#                 "type": [
#                   "null",
#                   "string"
#                 ],
#                 "default": null
#               }
#             ],
#             "connect.name": "io.confluent.connector.dynamodb.Source"
#           }
#         ],
#         "default": null
#       },
#       {
#         "name": "before",
#         "type": [
#           "null",
#           {
#             "type": "record",
#             "name": "Value",
#             "fields": [
#               {
#                 "name": "document",
#                 "type": [
#                   "null",
#                   "string"
#                 ],
#                 "default": null
#               }
#             ],
#             "connect.name": "io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value"
#           }
#         ],
#         "default": null
#       },
#       {
#         "name": "after",
#         "type": [
#           "null",
#           "Value"
#         ],
#         "default": null
#       }
#     ],
#     "connect.name": "io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Envelope"
#   }
# ]
# CreateTime:2024-07-10 17:35:16.683|Partition:0|Offset:0|Headers:NO_HEADERS|Key:{"first_name":"August","last_name":"Helen"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711347,"ts_us":1720625711347098,"ts_ns":1720625711347098433,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711347,"ts_us":1720625711347073,"ts_ns":1720625711347073734,"snapshotStartTime":{"long":1720625711297},"snapshotCount":{"int":1},"segment":{"int":0},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"7\"},\"last_name\":{\"S\":\"Helen\"},\"first_name\":{\"S\":\"August\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.683|Partition:0|Offset:1|Headers:NO_HEADERS|Key:{"first_name":"Reggie","last_name":"Elva"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711347,"ts_us":1720625711347270,"ts_ns":1720625711347270342,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711347,"ts_us":1720625711347266,"ts_ns":1720625711347266257,"snapshotStartTime":{"long":1720625711297},"snapshotCount":{"int":2},"segment":{"int":0},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"6\"},\"last_name\":{\"S\":\"Elva\"},\"first_name\":{\"S\":\"Reggie\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.684|Partition:0|Offset:2|Headers:NO_HEADERS|Key:{"first_name":"Madisyn","last_name":"Terrance"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711348,"ts_us":1720625711348377,"ts_ns":1720625711348377581,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711348,"ts_us":1720625711348372,"ts_ns":1720625711348372254,"snapshotStartTime":{"long":1720625711301},"snapshotCount":{"int":1},"segment":{"int":2},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"3\"},\"last_name\":{\"S\":\"Terrance\"},\"first_name\":{\"S\":\"Madisyn\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.684|Partition:0|Offset:3|Headers:NO_HEADERS|Key:{"first_name":"Kamille","last_name":"Noelia"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711348,"ts_us":1720625711348498,"ts_ns":1720625711348498453,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711348,"ts_us":1720625711348494,"ts_ns":1720625711348494758,"snapshotStartTime":{"long":1720625711301},"snapshotCount":{"int":2},"segment":{"int":2},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"1\"},\"last_name\":{\"S\":\"Noelia\"},\"first_name\":{\"S\":\"Kamille\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.685|Partition:0|Offset:4|Headers:NO_HEADERS|Key:{"first_name":"Horace","last_name":"Scotty"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711348,"ts_us":1720625711348596,"ts_ns":1720625711348596075,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711348,"ts_us":1720625711348592,"ts_ns":1720625711348592918,"snapshotStartTime":{"long":1720625711301},"snapshotCount":{"int":3},"segment":{"int":2},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"9\"},\"last_name\":{\"S\":\"Scotty\"},\"first_name\":{\"S\":\"Horace\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.685|Partition:0|Offset:5|Headers:NO_HEADERS|Key:{"first_name":"Carmen","last_name":"Fiona"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711351,"ts_us":1720625711351026,"ts_ns":1720625711351026720,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711351,"ts_us":1720625711351022,"ts_ns":1720625711351022179,"snapshotStartTime":{"long":1720625711302},"snapshotCount":{"int":1},"segment":{"int":3},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"0\"},\"last_name\":{\"S\":\"Fiona\"},\"first_name\":{\"S\":\"Carmen\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.685|Partition:0|Offset:6|Headers:NO_HEADERS|Key:{"first_name":"Jay","last_name":"Lucius"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711351,"ts_us":1720625711351132,"ts_ns":1720625711351132408,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711351,"ts_us":1720625711351129,"ts_ns":1720625711351129243,"snapshotStartTime":{"long":1720625711302},"snapshotCount":{"int":2},"segment":{"int":3},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"5\"},\"last_name\":{\"S\":\"Lucius\"},\"first_name\":{\"S\":\"Jay\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.685|Partition:0|Offset:7|Headers:NO_HEADERS|Key:{"first_name":"Lolita","last_name":"Tamara"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711351,"ts_us":1720625711351214,"ts_ns":1720625711351214633,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711351,"ts_us":1720625711351211,"ts_ns":1720625711351211888,"snapshotStartTime":{"long":1720625711302},"snapshotCount":{"int":3},"segment":{"int":3},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"2\"},\"last_name\":{\"S\":\"Tamara\"},\"first_name\":{\"S\":\"Lolita\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.686|Partition:0|Offset:8|Headers:NO_HEADERS|Key:{"first_name":"Linwood","last_name":"Martina"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711351,"ts_us":1720625711351911,"ts_ns":1720625711351911572,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711351,"ts_us":1720625711351905,"ts_ns":1720625711351905788,"snapshotStartTime":{"long":1720625711302},"snapshotCount":{"int":1},"segment":{"int":4},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"4\"},\"last_name\":{\"S\":\"Martina\"},\"first_name\":{\"S\":\"Linwood\"}}"}}}}|ValueSchemaId:105051
# CreateTime:2024-07-10 17:35:16.686|Partition:0|Offset:9|Headers:NO_HEADERS|Key:{"first_name":"Brady","last_name":"Santa"}|KeySchemaId:105050|Value:{"op":"r","ts_ms":1720625711352,"ts_us":1720625711352044,"ts_ns":1720625711352044831,"source":{"io.confluent.connector.dynamodb.Source":{"version":null,"tableName":"pgvsaboulindynamocdc7.6.1","sync_mode":"SNAPSHOT","ts_ms":1720625711352,"ts_us":1720625711352041,"ts_ns":1720625711352041857,"snapshotStartTime":{"long":1720625711302},"snapshotCount":{"int":2},"segment":{"int":4},"totalSegments":{"int":5},"shard_id":null,"seq_no":null}},"before":null,"after":{"io.confluent.connect.dynamodb.pgvsaboulindynamocdc7.6.1.Value":{"document":{"string":"{\"partition\":{\"N\":\"0\"},\"offset\":{\"N\":\"8\"},\"last_name\":{\"S\":\"Santa\"},\"first_name\":{\"S\":\"Brady\"}}"}}}}|ValueSchemaId:105051