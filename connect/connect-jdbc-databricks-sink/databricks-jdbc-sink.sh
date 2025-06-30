#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

DATABRICKS_HOST=${DATABRICKS_HOST:-$1}
DATABRICKS_TOKEN=${DATABRICKS_TOKEN:-$2}
DATABRICKS_HTTP_PATH=${DATABRICKS_HTTP_PATH:-$3}

cd ../../connect/connect-jdbc-databricks-source
if [ ! -f ${PWD}/DatabricksJDBC42.jar ]
then
     log "Downloading DatabricksJDBC42.jar "
     wget -q https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/jdbc/2.7.3/DatabricksJDBC42-2.7.3.1010.zip
     unzip DatabricksJDBC42-2.7.3.1010.zip -d lib
     mv lib/DatabricksJDBC-2.7.3.1010/DatabricksJDBC42.jar .
     rm -rf DatabricksJDBC42-2.7.3.1010.zip 
     rm -rf lib
fi
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


# need to pre-create otherwise getting ConnectException: null (INT32) type doesn't have a mapping to the SQL database column type
log "Pre-creating the table to avoid the 'ConnectException: null (INT32) type doesn't have a mapping to the SQL database column type error' "
docker exec -i databricks-sql-cli-container bash -c "python databricks_sql_cli.py" <<EOF
CREATE OR REPLACE TABLE orders ( id INT, product STRING, quantity INT, price FLOAT )TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');
exit
EOF


playground connector create-or-update --connector databricks-sink << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "auto.create": "false",
  "auto.evolve": "false",
  "connection.url": "jdbc:databricks://$DATABRICKS_HOST:443/default;transportMode=http;ssl=1;AuthMech=3;httpPath=$DATABRICKS_HTTP_PATH;IgnoreTransactions=1;",
  "connection.user": "token",
  "connection.password" : "$DATABRICKS_TOKEN",
  "topics": "orders"
}
EOF


log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 3 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
       "type":  "string"
    },
    {
      "name": "quantity",
      "type":  "int"
    },
    {
      "name": "price",
       "type": "float"
    }
  ]
}
EOF

playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":88.26}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

sleep 60

log "Verifying topic databricks-customers"
docker exec -i databricks-sql-cli-container bash -c "python databricks_sql_cli.py" <<EOF
select count(*) from orders;
exit
EOF

