#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

cd ../../connect/connect-jdbc-azure-synapse-analytics-source
if [ ! -f ${PWD}/sqljdbc_12.2/enu/mssql-jdbc-12.2.0.jre11.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-12.2.0.jre11.jar"
     curl -k -L https://go.microsoft.com/fwlink/?linkid=2222954 -o sqljdbc_12.2.0.0_enu.tar.gz
     tar xvfz sqljdbc_12.2.0.0_enu.tar.gz
     rm -f sqljdbc_12.2.0.0_enu.tar.gz
fi
cd -

login_and_maybe_set_azure_subscription

AZURE_NAME=pg${USER}wh${GITHUB_RUN_NUMBER}${TAG_BASE}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_SQL_NAME=$AZURE_NAME
AZURE_FIREWALL_RULL_NAME=$AZURE_NAME
AZURE_DATA_WAREHOUSE_NAME=$AZURE_NAME
AZURE_REGION=${AZURE_REGION:-westeurope}
AZURE_SQL_URL="jdbc:sqlserver://$AZURE_SQL_NAME.database.windows.net:1433;databaseName=$AZURE_DATA_WAREHOUSE_NAME"
PASSWORD=$(date +%s | cksum | base64 | head -c 32 ; echo)
PASSWORD="${PASSWORD}1"

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER cflt_managed_by=user cflt_managed_id="$USER"
function cleanup_cloud_resources {
    set +e
    log "Deleting resource group $AZURE_RESOURCE_GROUP"
    check_if_continue
    az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
}
trap cleanup_cloud_resources EXIT
log "Creating SQL server instance $AZURE_SQL_NAME"
# https://github.com/Azure/azure-cli/issues/17052 tags cannot be set
az sql server create \
    --name $AZURE_SQL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION  \
    --admin-user myadmin \
    --admin-password $PASSWORD
	
if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
    # running with CI
    # connect-jdbc-azure-synapse-analytics-source is failing #131
    # allow applications from Azure IP addresses to connect to your Azure Database for MySQL server, provide the IP address 0.0.0.0 as the Start IP and End IP
    az sql server firewall-rule create \
    --name $AZURE_FIREWALL_RULL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0
else
    log "Enable a server-level firewall rule"
    MY_IP=$(curl https://ipinfo.io/ip)
    az sql server firewall-rule create \
    --name $AZURE_FIREWALL_RULL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME \
    --start-ip-address $MY_IP \
    --end-ip-address $MY_IP
fi

log "Create a SQL Data Warehouse instance"
az sql dw create \
    --name $AZURE_DATA_WAREHOUSE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME \
    --tags cflt_managed_by=user cflt_managed_id="$USER"

# generate data file for externalizing secrets
sed -e "s|:AZURE_SQL_URL:|$AZURE_SQL_URL|g" \
    -e "s|:PASSWORD:|$PASSWORD|g" \
    -e "s|:AZURE_DATA_WAREHOUSE_NAME:|$AZURE_DATA_WAREHOUSE_NAME|g" \
    ../../connect/connect-jdbc-azure-synapse-analytics-source/data.template > ../../connect/connect-jdbc-azure-synapse-analytics-source/data


cd ../../connect/connect-jdbc-azure-synapse-analytics-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/
cp ../../connect/connect-jdbc-azure-synapse-analytics-source/sqljdbc_12.2/enu/mssql-jdbc-12.2.0.jre11.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/mssql-jdbc-12.2.0.jre11.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create table"
docker run -i fabiang/sqlcmd -S "$AZURE_SQL_NAME.database.windows.net,1433" -I -U "myadmin" -P "$PASSWORD" -d "$AZURE_DATA_WAREHOUSE_NAME" << EOF
-- Create some customers ...

DECLARE @Date DATETIME;
SET @Date = GETDATE();

CREATE TABLE customers (
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  last_update DATETIME2
);
INSERT INTO customers(first_name,last_name,email,last_update)
  VALUES ('Sally','Thomas','sally.thomas@acme.com',  @Date);
INSERT INTO customers(first_name,last_name,email,last_update)
  VALUES ('George','Bailey','gbailey@foobar.com',  @Date);
INSERT INTO customers(first_name,last_name,email,last_update)
  VALUES ('Edward','Walker','ed@walker.com',  @Date);
INSERT INTO customers(first_name,last_name,email,last_update)
  VALUES ('Anne','Kretchmar','annek@noanswer.org',  @Date);
GO
EOF

log "Creating JDBC Azure Synapse Analytics Source connector"
playground connector create-or-update --connector jdbc-synapse-source  << EOF
{
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "tasks.max": "1",
    "connection.url": "\${file:/data:AZURE_SQL_URL}",
    "connection.user": "myadmin",
    "connection.password": "\${file:/data:PASSWORD}",
    "table.whitelist": "customers",
    "mode": "timestamp",
    "timestamp.column.name": "last_update",
    "topic.prefix": "synapse-",
    "validate.non.null":"false",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 15

playground topic consume --topic synapse-customers --min-expected-messages 4
