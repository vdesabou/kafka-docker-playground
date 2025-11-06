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

cd ../../connect/connect-jdbc-sap-hana-sink
if [ ! -f ${PWD}/ngdbc-2.12.9.jar ]
then
     log "Downloading ngdbc-2.12.9.jar "
     wget -q https://repo1.maven.org/maven2/com/sap/cloud/db/jdbc/ngdbc/2.12.9/ngdbc-2.12.9.jar
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


playground container logs --container sap --wait-for-log "Startup finished!" --max-wait 600
log "SAP HANA has started!"

log "Creating SAP HANA JDBC Sink connector"
playground connector create-or-update --connector jdbc-sap-hana-sink  << EOF
{
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
     "topics": "orders",
     "connection.url": "jdbc:sap://sap:39041/?databaseName=HXE&reconnect=true&statementCacheSize=512",
     "connection.user": "LOCALDEV",
     "connection.password" : "Localdev1",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "auto.create": "true"
}
EOF

sleep 5

log "Sending records to orders topic"
playground topic produce -t orders --nb-messages 3 << 'EOF'
{
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
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

sleep 120

log "Check data is in SAP HANA"
docker exec -i sap /usr/sap/HXE/HDB90/exe/hdbsql -i 90 -d HXE -u LOCALDEV -p Localdev1 << EOF
select * from "LOCALDEV"."orders";
EOF
docker exec -i sap /usr/sap/HXE/HDB90/exe/hdbsql -i 90 -d HXE -u LOCALDEV -p Localdev1  > /tmp/result.log  2>&1 <<-EOF
select * from "LOCALDEV"."orders";
EOF
cat /tmp/result.log
grep "product" /tmp/result.log