#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

if ! version_gt $TAG_BASE "5.9.0"; then
    if [[ "$TAG" != *ubi8 ]]
    then
        logwarn "Known issue ! JDBC Source and Sink with MS SQL and JTDS driver does not work with SSL, see https://github.com/vdesabou/kafka-docker-playground/issues/1107"
        # known_issue https://github.com/vdesabou/kafka-docker-playground/issues/1107
        exit 111
    fi
fi

cd ${DIR}/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi

rm -f mssql.pem
rm -f mssql.key

#https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-security?view=sql-server-ver15
#https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-encrypted-connections?view=sql-server-ver15&preserve-view=true#client-initiated-encryption
log "Create a self-signed certificate"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=sqlserver' -keyout /tmp/mssql.key -out /tmp/mssql.pem -days 365

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi

log "Creating JKS from pem files"
rm -f truststore.jks
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -importcert -alias MSSQLCACert -noprompt -file /tmp/mssql.pem -keystore /tmp/truststore.jks -storepass confluent

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi

cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.jtds-ssl.yml"

log "Create table"
docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd -C -No -U sa -P Password! << EOF
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
playground connector create-or-update --connector sqlserver-source-ssl  << EOF
{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433/testDB;ssl=require",
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

docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd -C -No -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic sqlserver-customers"
playground topic consume --topic sqlserver-customers --min-expected-messages 5 --timeout 60
