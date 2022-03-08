#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-94375-cast-smt-that-support-add-recursive.yml"


log "Describing the team table in DB 'mydb':"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'describe team'"

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

log "Adding an element to the table"
docker exec mysql mysql --user=root --password=password --database=mydb -e "
INSERT INTO team (   \
  id,   \
  name, \
  email,   \
  last_modified \
) VALUES (  \
  3,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
); "

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

log "Creating Debezium MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.debezium.connector.mysql.MySqlConnector",
                "tasks.max": "1",
                "database.hostname": "mysql",
                "database.port": "3306",
                "database.user": "debezium",
                "database.password": "dbz",
                "database.server.id": "223344",
                "database.server.name": "dbserver1",
                "database.whitelist": "mydb",
                "database.history.kafka.bootstrap.servers": "broker:9092",
                "database.history.kafka.topic": "schema-changes.mydb",
                "transforms": unwrap,Cast",
                "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
                "transforms.Cast.type": "org.apache.kafka.connect.transforms.Cast$Value",
                "transforms.Cast.spec": "id:string"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

log "Verifying topic dbserver1_mydb_team"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1_mydb_team --from-beginning --max-messages 2


# {
#     "after": {
#         "dbserver1.mydb.team.Value": {
#             "email": "kafka@apache.org",
#             "id": 1,
#             "last_modified": 1646657383000,
#             "name": "kafka"
#         }
#     },
#     "before": null,
#     "op": "r",
#     "source": {
#         "connector": "mysql",
#         "db": "mydb",
#         "file": "mysql-bin.000003",
#         "gtid": null,
#         "name": "dbserver1",
#         "pos": 457,
#         "query": null,
#         "row": 0,
#         "sequence": null,
#         "server_id": 0,
#         "snapshot": {
#             "string": "true"
#         },
#         "table": {
#             "string": "team"
#         },
#         "thread": null,
#         "ts_ms": 1646657411312,
#         "version": "1.8.1.Final"
#     },
#     "transaction": null,
#     "ts_ms": {
#         "long": 1646657411318
#     }
# }

# # with ExtractNewRecordState SMT

# {
#     "email": "kafka@apache.org",
#     "id": 1,
#     "last_modified": 1646660200000,
#     "name": "kafka"
# }

# # with Cast:

# {
#     "email": "kafka@apache.org",
#     "id": "1",
#     "last_modified": 1646660573000,
#     "name": "kafka"
# }
