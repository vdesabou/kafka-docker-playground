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

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-jdbc-oracle19-sink/ora-setup-scripts"

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground container logs --container oracle --wait-for-log "DATABASE IS READY TO USE" --max-wait 600
log "Oracle DB has started!"
log "Setting up Oracle Database Prerequisites"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     CREATE USER  C##MYUSER IDENTIFIED BY mypassword;
     GRANT CONNECT TO  C##MYUSER;
     GRANT CREATE SESSION TO  C##MYUSER;
     GRANT CREATE TABLE TO  C##MYUSER;
     GRANT CREATE SEQUENCE TO  C##MYUSER;
     GRANT CREATE TRIGGER TO  C##MYUSER;
     ALTER USER  C##MYUSER QUOTA 100M ON users;
     exit;
EOF

log "Creating Oracle sink connector"

playground connector create-or-update --connector oracle-sink  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.user": "C##MYUSER",
  "connection.password": "mypassword",
  "connection.url": "jdbc:oracle:thin:@oracle:1521/ORCLCDB",
  "topics": "ORDERS",
  "auto.create": "true",
  "insert.mode":"insert",
  "auto.evolve":"true"
}
EOF


log "Sending messages to topic ORDERS"
playground topic produce -t ORDERS --nb-messages 1 << 'EOF'
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

playground topic produce -t ORDERS --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
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

sleep 5


log "Show content of ORDERS table:"
docker exec oracle bash -c "echo 'select * from ORDERS;' | sqlplus C##MYUSER/mypassword@//localhost:1521/ORCLCDB" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log

