#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-jdbc-sqlserver-sink
if [ ! -f ${PWD}/sqljdbc_12.2/enu/mssql-jdbc-12.2.0.jre11.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-12.2.0.jre11.jar"
     curl -L https://go.microsoft.com/fwlink/?linkid=2222954 -o sqljdbc_12.2.0.0_enu.tar.gz
     tar xvfz sqljdbc_12.2.0.0_enu.tar.gz
     rm -f sqljdbc_12.2.0.0_enu.tar.gz
fi
cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.microsoft.yml"



log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
playground connector create-or-update --connector sqlserver-sink << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
     "tasks.max": "1",
     "connection.url": "jdbc:sqlserver://sqlserver:1433;encrypt=false",
     "connection.user": "sa",
     "connection.password": "Password!",
     "topics": "orders",
     "auto.create": "true"
}
EOF

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 << 'EOF'
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

playground topic produce -t orders --nb-messages 1 --forced-value = '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
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

log "Show content of orders table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from orders
GO
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log