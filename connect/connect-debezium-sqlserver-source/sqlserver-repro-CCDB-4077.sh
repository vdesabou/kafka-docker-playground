#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.CCDB-4077.yml"


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
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.basic.auth.credentials.source": "USER_INFO",
                    "value.converter.basic.auth.user.info": "admin:admin"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081  --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info='admin:admin' --topic server1.dbo.customers --from-beginning --max-messages 5


# [2022-01-06 10:11:02,053] INFO [debezium-sqlserver-source|task-0] Starting SqlServerConnectorTask with configuration: (io.debezium.connector.common.BaseSourceTask:127)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    connector.class = io.debezium.connector.sqlserver.SqlServerConnector (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    database.user = sa (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    database.dbname = testDB (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    tasks.max = 1 (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    database.history.kafka.bootstrap.servers = broker:9092 (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    database.history.kafka.topic = schema-changes.inventory (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    database.server.name = server1 (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    database.port = 1433 (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,055] INFO [debezium-sqlserver-source|task-0]    value.converter.basic.auth.credentials.source = USER_INFO (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,056] INFO [debezium-sqlserver-source|task-0]    value.converter.schema.registry.url = http://schema-registry:8081 (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,056] INFO [debezium-sqlserver-source|task-0]    value.converter.basic.auth.user.info = admin:admin (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,056] INFO [debezium-sqlserver-source|task-0]    task.class = io.debezium.connector.sqlserver.SqlServerConnectorTask (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,056] INFO [debezium-sqlserver-source|task-0]    database.hostname = sqlserver (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,056] INFO [debezium-sqlserver-source|task-0]    database.password = ******** (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,056] INFO [debezium-sqlserver-source|task-0]    name = debezium-sqlserver-source (io.debezium.connector.common.BaseSourceTask:129)
# [2022-01-06 10:11:02,056] INFO [debezium-sqlserver-source|task-0]    value.converter = io.confluent.connect.avro.AvroConverter (io.debezium.connector.common.BaseSourceTask:129)

# With workaround in place (commit https://github.com/vdesabou/kafka-docker-playground/commit/b603f41505416aca4aca7209c8b70a29c68ae5cb):

# [2022-01-07 10:49:49,084] INFO Starting SqlServerConnectorTask with configuration: (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,087] INFO    connector.class = io.debezium.connector.sqlserver.SqlServerConnector (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,088] INFO    database.user = sa (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,089] INFO    database.dbname = testDB (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,089] INFO    tasks.max = 1 (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,090] INFO    database.history.kafka.bootstrap.servers = broker:9092 (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,091] INFO    database.history.kafka.topic = schema-changes.inventory (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,091] INFO    database.server.name = server1 (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,092] INFO    database.port = 1433 (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,093] INFO    value.converter.basic.auth.credentials.source = USER_INFO (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,094] INFO    value.converter.schema.registry.url = http://schema-registry:8081 (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,094] INFO    task.class = io.debezium.connector.sqlserver.SqlServerConnectorTask (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,095] INFO    database.hostname = sqlserver (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,096] INFO    database.password = ******** (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,096] INFO    name = debezium-sqlserver-source (io.debezium.connector.common.BaseSourceTask)
# [2022-01-07 10:49:49,097] INFO    value.converter = io.confluent.connect.avro.AvroConverter (io.debezium.connector.common.BaseSourceTask)
