#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.plaintext.standalone-worker.yml" -a -b


#############

set +e
playground topic delete --topic server1.testDB.dbo.customers
set -e

log "Create table"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
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
EXEC sys.sp_cdc_enable_table @source_schema = 'dbo', @source_name = 'customers', @role_name = NULL, @supports_net_changes = 0;
GO
EOF


log "Creating Debezium SQL Server source standalone connector"
docker exec -d connect bash -c 'connect-standalone /tmp/worker.properties /tmp/connector.properties > /tmp/standalone.log 2>&1'

log "Sleeping 60 seconds to let the standalone connector doing the work"
sleep 60

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic server1.testDB.dbo.customers"
playground topic consume --topic server1.testDB.dbo.customers --min-expected-messages 5 --timeout 60

log "Copying standalone logs to /tmp/standalone.log"
docker cp connect:/tmp/standalone.log /tmp/standalone.log