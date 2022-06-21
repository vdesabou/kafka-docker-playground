#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-110472-see-extractfield-limitations.yml"

log "Sending messages to topic filestream"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic filestream << EOF
{"transaction":null,"ts_ms":{"long":1655718360267},"after":{"server1.dbo.customers.Value":{"first_name":"Edward","last_name":"Walker","email":"ed@walker.com","id":1003}},"source":{"commit_lsn":{"string":"00000025:000004c0:001a"},"name":"server1","sequence":null,"ts_ms":1655718360267,"db":"testDB","connector":"sqlserver","version":"1.9.2.Final","event_serial_no":null,"table":"customers","snapshot":{"string":"true"},"change_lsn":null,"schema":"dbo"},"before":null,"op":"r"}
EOF


# {
#     "after": {
#         "server1.dbo.customers.Value": {
#             "email": "ed@walker.com",
#             "first_name": "Edward",
#             "id": 1003,
#             "last_name": "Walker"
#         }
#     },
#     "before": null,
#     "op": "r",
#     "source": {
#         "change_lsn": null,
#         "commit_lsn": {
#             "string": "00000025:000004c0:001a"
#         },
#         "connector": "sqlserver",
#         "db": "testDB",
#         "event_serial_no": null,
#         "name": "server1",
#         "schema": "dbo",
#         "sequence": null,
#         "snapshot": {
#             "string": "true"
#         },
#         "table": "customers",
#         "ts_ms": 1655718360267,
#         "version": "1.9.2.Final"
#     },
#     "transaction": null,
#     "ts_ms": {
#         "long": 1655718360267
#     }
# }

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "filestream",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "transforms": "ExtractField",
               "transforms.ExtractField.type": "org.apache.kafka.connect.transforms.ExtractField$Value",
               "transforms.ExtractField.field": "after"
          }' \
     http://localhost:8083/connectors/filestream-sink/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

# {server1.dbo.customers.Value={last_name=Walker, id=1003, first_name=Edward, email=ed@walker.com}}
