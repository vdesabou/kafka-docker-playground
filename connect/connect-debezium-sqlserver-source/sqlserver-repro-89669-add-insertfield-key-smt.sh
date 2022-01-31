#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-89669-add-insertfield-key-smt.yml"


log "Load inventory.sql to SQL Server"
cat inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


log "Creating Debezium SQL Server source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
               "tasks.max": "1",
               "database.hostname": "sqlserver",
               "database.port": "1433",
               "database.user": "sa",
               "database.password": "Password!",
               "database.server.name": "server1",
               "database.dbname" : "testDB",
               "database.history.kafka.bootstrap.servers": "broker:9092",
               "database.history.kafka.topic": "schema-changes.inventory",
               "key.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "transforms": "unwrap,Transform,Transform2",
               "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
               "transforms.Transform.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
               "transforms.Transform.target.type": "string",
               "transforms.Transform.field": "timestamp",
               "transforms.Transform.format": "yyyy-MM-dd HH:mm:ss",
               "transforms.Transform2.type": "org.apache.kafka.connect.transforms.InsertField$Key",
               "transforms.Transform2.static.field": "projectId",
               "transforms.Transform2.static.value": "test"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source-json/config | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF


log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic server1.dbo.customers --property print.key=true --property key.separator=, --from-beginning --max-messages 5


# {"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":true,"field":"projectId"}],"optional":false,"name":"server1.dbo.customers.Key"},"payload":{"id":1001,"projectId":"test"}},{"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":false,"field":"first_name"},{"type":"string","optional":false,"field":"last_name"},{"type":"string","optional":false,"field":"email"}],"optional":false,"name":"server1.dbo.customers.Value"},"payload":{"id":1001,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com"}}
# {"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":true,"field":"projectId"}],"optional":false,"name":"server1.dbo.customers.Key"},"payload":{"id":1002,"projectId":"test"}},{"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":false,"field":"first_name"},{"type":"string","optional":false,"field":"last_name"},{"type":"string","optional":false,"field":"email"}],"optional":false,"name":"server1.dbo.customers.Value"},"payload":{"id":1002,"first_name":"George","last_name":"Bailey","email":"gbailey@foobar.com"}}
# {"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":true,"field":"projectId"}],"optional":false,"name":"server1.dbo.customers.Key"},"payload":{"id":1003,"projectId":"test"}},{"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":false,"field":"first_name"},{"type":"string","optional":false,"field":"last_name"},{"type":"string","optional":false,"field":"email"}],"optional":false,"name":"server1.dbo.customers.Value"},"payload":{"id":1003,"first_name":"Edward","last_name":"Walker","email":"ed@walker.com"}}
# {"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":true,"field":"projectId"}],"optional":false,"name":"server1.dbo.customers.Key"},"payload":{"id":1004,"projectId":"test"}},{"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":false,"field":"first_name"},{"type":"string","optional":false,"field":"last_name"},{"type":"string","optional":false,"field":"email"}],"optional":false,"name":"server1.dbo.customers.Value"},"payload":{"id":1004,"first_name":"Anne","last_name":"Kretchmar","email":"annek@noanswer.org"}}
# {"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":true,"field":"projectId"}],"optional":false,"name":"server1.dbo.customers.Key"},"payload":{"id":1005,"projectId":"test"}},{"schema":{"type":"struct","fields":[{"type":"int32","optional":false,"field":"id"},{"type":"string","optional":false,"field":"first_name"},{"type":"string","optional":false,"field":"last_name"},{"type":"string","optional":false,"field":"email"}],"optional":false,"name":"server1.dbo.customers.Value"},"payload":{"id":1005,"first_name":"Pam","last_name":"Thomas","email":"pam@office.com"}}
