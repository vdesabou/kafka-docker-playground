#!/bin/bash
set -e

# https://github.com/confluentinc/ksql/issues/5503
export TAG=6.0.0

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh

# https://kafka-tutorials.confluent.io/handling-deserialization-errors/ksql.html

log "Create streams"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

CREATE STREAM SENSORS_RAW (id VARCHAR, timestamp VARCHAR, enabled BOOLEAN)
    WITH (KAFKA_TOPIC = 'SENSORS_RAW',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1,
          REPLICAS=1);

CREATE STREAM SENSORS AS
    SELECT
        ID, TIMESTAMP, ENABLED
    FROM SENSORS_RAW
    PARTITION BY ID;
EOF

docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic SENSORS_RAW << EOF
{"id": "e7f45046-ad13-404c-995e-1eca16742801", "timestamp": "2020-01-15 02:20:30", "enabled": true}
{"id": "835226cf-caf6-4c91-a046-359f1d3a6e2e", "timestamp": "2020-01-15 02:25:30", "enabled": true}
{"id": "1a076a64-4a84-40cb-a2e8-2190f3b37465", "timestamp": "2020-01-15 02:30:30", "enabled": "true"}
EOF


log "Check Stream"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

SELECT
    ID,
    TIMESTAMP,
    ENABLED
FROM SENSORS EMIT CHANGES LIMIT 2;

SELECT
    message->deserializationError->errorMessage,
    encode(message->deserializationError->RECORDB64, 'base64', 'utf8') AS MSG,
    message->deserializationError->cause
  FROM KSQL_PROCESSING_LOG
  EMIT CHANGES
  LIMIT 1;

PRINT ksql_processing_log FROM BEGINNING LIMIT 1;
EOF


# ksql> ksql> Successfully changed local property 'auto.offset.reset' to 'earliest'. Use the UNSET command to revert your change.
# ksql> ksql> +-----+-----+-----+
# |ID   |TIMES|ENABL|
# |     |TAMP |ED   |
# +-----+-----+-----+
# |e7f45|2020-|true |
# |046-a|01-15|     |
# |d13-4| 02:2|     |
# |04c-9|0:30 |     |
# |95e-1|     |     |
# |eca16|     |     |
# |74280|     |     |
# |1    |     |     |
# |83522|2020-|true |
# |6cf-c|01-15|     |
# |af6-4| 02:2|     |
# |c91-a|5:30 |     |
# |046-3|     |     |
# |59f1d|     |     |
# |3a6e2|     |     |
# |e    |     |     |
# Limit Reached
# Query terminated
# ksql> ksql> ksql> SELECT
# >    message->deserializationError->errorMessage,
# >    encode(message->deserializationError->RECORDB64, 'base64', 'utf8')+-----+-----+-----+
# |ERROR|MSG  |CAUSE|
# |MESSA|     |     |
# |GE   |     |     |
# +-----+-----+-----+
# |mvn v|{"id"|[Can'|
# |alue |: "1a|t con|
# |from |076a6|vert |
# |topic|4-4a8|type.|
# |: SEN|4-40c| sour|
# |SORS_|b-a2e|ceTyp|
# |RAW  |8-219|e: Te|
# |     |0f3b3|xtNod|
# |     |7465"|e, re|
# |     |, "ti|quire|
# |     |mesta|dType|
# |     |mp": |: BOO|
# |     |"2020|LEAN,|
# |     |-01-1| path|
# |     |5 02:|: $.E|
# |     |30:30|NABLE|
# |     |", "e|D, Ca|
# |     |nable|n't c|
# |     |d": "|onver|
# |     |true"|t typ|
# |     |}    |e. so|
# |     |     |urceT|
# |     |     |ype: |
# |     |     |TextN|
# |     |     |ode, |
# |     |     |requi|
# |     |     |redTy|
# |     |     |pe: B|
# |     |     |OOLEA|
# |     |     |N, pa|
# |     |     |th: .|
# |     |     |ENABL|
# |     |     |ED, C|
# |     |     |an't |
# |     |     |conve|
# |     |     |rt ty|
# |     |     |pe. s|
# |     |     |ource|
# |     |     |Type:|
# |     |     | Text|
# |     |     |Node,|
# |     |     | requ|
# |     |     |iredT|
# |     |     |ype: |
# |     |     |BOOLE|
# |     |     |AN]  |
# Limit Reached
# Query terminated
# ksql> ksql> Key format: ¯\_(ツ)_/¯ - no data processed
# Value format: JSON or KAFKA_STRING
# rowtime: 2021/03/15 10:17:45.965 Z, key: <null>, value: {"level":"ERROR","logger":"processing.CSAS_SENSORS_0.KsqlTopic.Source.deserializer","time":1615803465945,"message":{"type":0,"deserializationError":{"errorMessage":"mvn value from topic: SENSORS_RAW","recordB64":"eyJpZCI6ICIxYTA3NmE2NC00YTg0LTQwY2ItYTJlOC0yMTkwZjNiMzc0NjUiLCAidGltZXN0YW1wIjogIjIwMjAtMDEtMTUgMDI6MzA6MzAiLCAiZW5hYmxlZCI6ICJ0cnVlIn0=","cause":["Can't convert type. sourceType: TextNode, requiredType: BOOLEAN, path: $.ENABLED","Can't convert type. sourceType: TextNode, requiredType: BOOLEAN, path: .ENABLED","Can't convert type. sourceType: TextNode, requiredType: BOOLEAN"],"topic":"SENSORS_RAW"},"recordProcessingError":null,"productionError":null}}
# Topic printing ceased
# ksql> Exiting ksqlDB.
