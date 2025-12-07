#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

# https://docs.confluent.io/cloud/current/connectors/cc-http-source.html#cursor-pagination-offset-mode-with-the-gcs-list-objects-rest-api
# This example demonstrates cursor pagination with Google Cloud Storage API-style responses
# The HTTP server returns paginated data with the following structure:
# {
#   "kind": "storage#objects",
#   "nextPageToken": "CkV0b3BpY3MvZGVtby9MS9ob3V...=",
#   "items": [ {...}, {...}, ... ]
# }
# The connector makes requests to http://httpserver:9006/storage/v1/b/test-bucket/o?pageToken=<token>
# and uses the nextPageToken from the response to fetch subsequent pages

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "0.1.99"
then
     logwarn "minimal supported connector version is 0.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

cd ../../connect/connect-http-source/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -


cd ../../connect/connect-http-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-http-source/lib/
cp ../../connect/connect-http-source/jcl-over-slf4j-2.0.7.jar ../../confluent-hub/confluentinc-kafka-connect-http-source/lib/jcl-over-slf4j-2.0.7.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.cursor-pagination.yml"

playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-source connector with cursor pagination (Google Cloud Storage API style)"
playground connector create-or-update --connector http-source  << EOF
{
    "tasks.max": "1",
    "connector.class": "io.confluent.connect.http.HttpSourceConnector",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "topic.name.pattern":"http-topic-\${entityName}",
    "entity.names": "messages",
    "url": "http://httpserver:9006/storage/v1/b/test-bucket/o",
    "http.offset.mode": "CURSOR_PAGINATION",
    "http.request.method": "GET",
    "http.request.parameters": "pageToken=\${offset}",
    "http.response.data.json.pointer": "/items",
    "http.next.page.json.pointer": "/nextPageToken",
    "request.interval.ms": "1000"
}
EOF

sleep 10

log "Verify we have received the data in http-topic-messages topic (expecting 15 messages across 3 pages)"
playground topic consume --topic http-topic-messages --min-expected-messages 15 --timeout 60

# CreateTime:2025-11-28 16:14:03.692|Partition:0|Offset:0|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_0","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_0","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_0","name":"file_0.txt","bucket":"test-bucket","generation":"1669124982018940","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14552","md5Hash":"md5_hash_0","crc32c":"crc32c_0","etag":"etag_0","timeCreated":1764342843462,"updated":1764342843462,"timeStorageClassUpdated":1764342843462}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.693|Partition:0|Offset:1|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_1","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_1","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_1","name":"file_1.txt","bucket":"test-bucket","generation":"1669124982018941","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14553","md5Hash":"md5_hash_1","crc32c":"crc32c_1","etag":"etag_1","timeCreated":1764341843462,"updated":1764341843462,"timeStorageClassUpdated":1764341843462}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.693|Partition:0|Offset:2|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_2","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_2","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_2","name":"file_2.txt","bucket":"test-bucket","generation":"1669124982018942","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14554","md5Hash":"md5_hash_2","crc32c":"crc32c_2","etag":"etag_2","timeCreated":1764340843462,"updated":1764340843462,"timeStorageClassUpdated":1764340843462}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.693|Partition:0|Offset:3|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_3","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_3","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_3","name":"file_3.txt","bucket":"test-bucket","generation":"1669124982018943","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14555","md5Hash":"md5_hash_3","crc32c":"crc32c_3","etag":"etag_3","timeCreated":1764339843462,"updated":1764339843462,"timeStorageClassUpdated":1764339843462}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.693|Partition:0|Offset:4|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_4","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_4","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_4","name":"file_4.txt","bucket":"test-bucket","generation":"1669124982018944","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14556","md5Hash":"md5_hash_4","crc32c":"crc32c_4","etag":"etag_4","timeCreated":1764338843462,"updated":1764338843462,"timeStorageClassUpdated":1764338843462}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.795|Partition:0|Offset:5|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_5","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_5","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_5","name":"file_5.txt","bucket":"test-bucket","generation":"1669124982018945","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14557","md5Hash":"md5_hash_5","crc32c":"crc32c_5","etag":"etag_5","timeCreated":1764337843697,"updated":1764337843697,"timeStorageClassUpdated":1764337843697}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.795|Partition:0|Offset:6|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_6","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_6","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_6","name":"file_6.txt","bucket":"test-bucket","generation":"1669124982018946","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14558","md5Hash":"md5_hash_6","crc32c":"crc32c_6","etag":"etag_6","timeCreated":1764336843697,"updated":1764336843697,"timeStorageClassUpdated":1764336843697}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.795|Partition:0|Offset:7|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_7","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_7","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_7","name":"file_7.txt","bucket":"test-bucket","generation":"1669124982018947","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14559","md5Hash":"md5_hash_7","crc32c":"crc32c_7","etag":"etag_7","timeCreated":1764335843697,"updated":1764335843697,"timeStorageClassUpdated":1764335843697}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.795|Partition:0|Offset:8|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_8","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_8","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_8","name":"file_8.txt","bucket":"test-bucket","generation":"1669124982018948","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14560","md5Hash":"md5_hash_8","crc32c":"crc32c_8","etag":"etag_8","timeCreated":1764334843697,"updated":1764334843697,"timeStorageClassUpdated":1764334843697}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.795|Partition:0|Offset:9|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_9","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_9","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_9","name":"file_9.txt","bucket":"test-bucket","generation":"1669124982018949","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14561","md5Hash":"md5_hash_9","crc32c":"crc32c_9","etag":"etag_9","timeCreated":1764333843697,"updated":1764333843697,"timeStorageClassUpdated":1764333843697}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.897|Partition:0|Offset:10|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_10","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_10","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_10","name":"file_10.txt","bucket":"test-bucket","generation":"16691249820189410","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14562","md5Hash":"md5_hash_10","crc32c":"crc32c_10","etag":"etag_10","timeCreated":1764332843799,"updated":1764332843799,"timeStorageClassUpdated":1764332843799}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.898|Partition:0|Offset:11|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_11","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_11","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_11","name":"file_11.txt","bucket":"test-bucket","generation":"16691249820189411","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14563","md5Hash":"md5_hash_11","crc32c":"crc32c_11","etag":"etag_11","timeCreated":1764331843799,"updated":1764331843799,"timeStorageClassUpdated":1764331843799}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.898|Partition:0|Offset:12|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_12","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_12","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_12","name":"file_12.txt","bucket":"test-bucket","generation":"16691249820189412","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14564","md5Hash":"md5_hash_12","crc32c":"crc32c_12","etag":"etag_12","timeCreated":1764330843799,"updated":1764330843799,"timeStorageClassUpdated":1764330843799}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.898|Partition:0|Offset:13|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_13","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_13","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_13","name":"file_13.txt","bucket":"test-bucket","generation":"16691249820189413","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14565","md5Hash":"md5_hash_13","crc32c":"crc32c_13","etag":"etag_13","timeCreated":1764329843799,"updated":1764329843799,"timeStorageClassUpdated":1764329843799}|ValueSchemaId:
# CreateTime:2025-11-28 16:14:03.898|Partition:0|Offset:14|Headers:NO_HEADERS|Key:null|Value:{"kind":"storage#object","id":"object_id_14","selfLink":"https://www.googleapis.com/storage/v1/b/test-bucket/o/object_14","mediaLink":"https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_14","name":"file_14.txt","bucket":"test-bucket","generation":"16691249820189414","metageneration":"1","contentType":"text/plain","storageClass":"STANDARD","size":"14566","md5Hash":"md5_hash_14","crc32c":"crc32c_14","etag":"etag_14","timeCreated":1764328843799,"updated":1764328843799,"timeStorageClassUpdated":1764328843799}|ValueSchemaId:
