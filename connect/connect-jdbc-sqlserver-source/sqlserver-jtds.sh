#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.jtds.yml"

log "Create table"
playground container exec --container sqlserver --command '/opt/mssql-tools18/bin/sqlcmd -C -No -U sa -P Password!' << EOF
-- Create the test database
CREATE DATABASE testDB;
GO
USE testDB;
EXEC sys.sp_cdc_enable_db;

-- Create some customers ...
CREATE TABLE customers (
  id INTEGER IDENTITY(1001,1) NOT NULL PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL
);
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Sally','Thomas','sally.thomas@acme.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('George','Bailey','gbailey@foobar.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Edward','Walker','ed@walker.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Anne','Kretchmar','annek@noanswer.org');
GO
EOF

log "Creating JDBC SQL Server (with JTDS driver) source connector"
playground connector create-or-update --connector sqlserver-source  << EOF
{
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "tasks.max": "1",
    "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433/testDB",
    "connection.user": "sa",
    "connection.password": "Password!",
    "table.whitelist": "customers",
    "mode": "incrementing",
    "incrementing.column.name": "id",
    "topic.prefix": "sqlserver-",
    "validate.non.null":"false",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 5

playground container exec --container sqlserver --command '/opt/mssql-tools18/bin/sqlcmd -C -No -U sa -P Password!' << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic sqlserver-customers"
playground topic consume --topic sqlserver-customers --min-expected-messages 5 --timeout 60

