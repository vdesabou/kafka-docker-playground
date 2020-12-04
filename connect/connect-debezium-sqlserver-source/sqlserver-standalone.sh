#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$KSQLDB" ]
then
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-standalone.yml" -a -b
else
     ${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext-standalone.yml" -a -b
fi

log "Load inventory.sql to SQL Server"
cat inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


log "Creating Debezium SQL Server source standalone connector"
docker exec -d connect bash -c 'connect-standalone /tmp/worker.properties /tmp/connector.properties > /tmp/standalone.log 2>&1'

log "Sleeping 60 seconds to let the standalone connector doing the work"
sleep 60

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5

log "Copying standalone logs to /tmp/standalone.log"
docker cp connect:/tmp/standalone.log /tmp/standalone.log