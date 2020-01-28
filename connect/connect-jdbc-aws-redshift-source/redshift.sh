#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CLUSTER=${1:-cluster-name.cluster-id.region.redshift.amazonaws.com}
PASSWORD=${2:-myPassword1}
DATABASE="dev"
USER="awsuser"
PORT="5439"

if [ ! -f ${DIR}/RedshiftJDBC4-1.2.20.1043.jar ]
then
     wget https://s3.amazonaws.com/redshift-downloads/drivers/jdbc/1.2.20.1043/RedshiftJDBC4-1.2.20.1043.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

set +e
docker run -i -e CLUSTER="$CLUSTER" -e USER="$USER" -e DATABASE="$DATABASE" -e PORT="$PORT" -e PASSWORD="$PASSWORD" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:10 psql -h "$CLUSTER" -U "$USER" -d "$DATABASE" -p "$PORT" << EOF
$PASSWORD
DROP TABLE CUSTOMERS;
EOF
set -e

log "Create database in Redshift"
docker run -i -e CLUSTER="$CLUSTER" -e USER="$USER" -e DATABASE="$DATABASE" -e PORT="$PORT" -e PASSWORD="$PASSWORD" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:10 psql -h "$CLUSTER" -U "$USER" -d "$DATABASE" -p "$PORT" -f "/tmp/customers.sql" << EOF
$PASSWORD
EOF

log "Verify data is in Redshift"
docker run -i -e CLUSTER="$CLUSTER" -e USER="$USER" -e DATABASE="$DATABASE" -e PORT="$PORT" -e PASSWORD="$PASSWORD" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:10 psql -h "$CLUSTER" -U "$USER" -d "$DATABASE" -p "$PORT" << EOF
$PASSWORD
SELECT * from CUSTOMERS;
EOF

log "Creating JDBC AWS Redshift source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://'"$CLUSTER"':'"$PORT"'/'"$DATABASE"'?user='"$USER"'&password='"$PASSWORD"'&ssl=false",
                    "table.whitelist": "customers",
                    "mode": "timestamp+incrementing",
                    "timestamp.column.name": "update_ts",
                    "incrementing.column.name": "id",
                    "topic.prefix": "redshift-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/redshift-source/config | jq_docker_cli .


sleep 5

log "Verifying topic redshift-customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redshift-customers --from-beginning --max-messages 5
