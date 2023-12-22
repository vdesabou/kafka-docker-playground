#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

playground start-environment --environment plaintext

log "Create the ksqlDB streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
CREATE STREAM SENSORS_RAW (id VARCHAR, timestamp VARCHAR, enabled BOOLEAN)
    WITH (KAFKA_TOPIC = 'SENSORS_RAW',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1);

CREATE STREAM SENSORS AS
    SELECT
        ID, TIMESTAMP, ENABLED
    FROM SENSORS_RAW
    PARTITION BY ID;
EOF

log "Insert records to the stream"
log "The last record with the error contains the field ENABLED specified as string instead of a boolean"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic SENSORS_RAW << EOF
{"id": "e7f45046-ad13-404c-995e-1eca16742801", "timestamp": "2020-01-15 02:20:30", "enabled": true}
{"id": "835226cf-caf6-4c91-a046-359f1d3a6e2e", "timestamp": "2020-01-15 02:25:30", "enabled": true}
{"id": "1a076a64-4a84-40cb-a2e8-2190f3b37465", "timestamp": "2020-01-15 02:30:30", "enabled": "true"}
EOF


# Wait for the stream to be initialized
sleep 10

log "Run a Pull query against stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT
    ID,
    TIMESTAMP,
    ENABLED
FROM SENSORS EMIT CHANGES LIMIT 2;
EOF

# The output should look similar to:
# +-------------------------------------------+-------------------------------------------+-------------------------------------------+
# |ID                                         |TIMESTAMP                                  |ENABLED                                    |
# +-------------------------------------------+-------------------------------------------+-------------------------------------------+
# |e7f45046-ad13-404c-995e-1eca16742801       |2020-01-15 02:20:30                        |true                                       |
# |835226cf-caf6-4c91-a046-359f1d3a6e2e       |2020-01-15 02:25:30                        |true                                       |
# Limit Reached
# Query terminated


log "Run a Pull query against stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT
    message->deserializationError->errorMessage,
    encode(message->deserializationError->RECORDB64, 'base64', 'utf8') AS MSG,
    message->deserializationError->cause
  FROM KSQL_PROCESSING_LOG
  EMIT CHANGES
  LIMIT 1;

PRINT ksql_processing_log FROM BEGINNING LIMIT 1;

EOF

# This query should produce the following output:
# +-------------------------------------------+-------------------------------------------+-------------------------------------------+
# |ERRORMESSAGE                               |MSG                                        |CAUSE                                      |
# +-------------------------------------------+-------------------------------------------+-------------------------------------------+
# |Failed to deserialize value from topic: SEN|{"id": "1a076a64-4a84-40cb-a2e8-2190f3b3746|[Can't convert type. sourceType: TextNode, |
# |SORS_RAW. Can't convert type. sourceType: T|5", "timestamp": "2020-01-15 02:30:30", "en|requiredType: BOOLEAN, path: $.ENABLED, Can|
# |extNode, requiredType: BOOLEAN, path: $.ENA|abled": "true"}                            |'t convert type. sourceType: TextNode, requ|
# |BLED                                       |                                           |iredType: BOOLEAN, path: .ENABLED, Can't co|
# |                                           |                                           |nvert type. sourceType: TextNode, requiredT|
# |                                           |                                           |ype: BOOLEAN]                              |
# Limit Reached
# Query terminated
