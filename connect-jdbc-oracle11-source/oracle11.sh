#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/ojdbc6.jar ]
then
     echo "ERROR: ${DIR}/ojdbc6.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


# installing instantclient (sqlplus) on connect:
# Version 11.2.0.4.0
# https://www.oracle.com/database/technologies/instant-client/linux-x86-64-downloads.html
# apt update
# apt-get install alien
# apt-get install libaio1

# cd /root/instantclient
# alien -i oracle-instantclient*-basic-*.rpm
# alien -i oracle-instantclient*-devel-*.rpm
# alien -i oracle-instantclient*-sqlplus-*.rpm

# echo /usr/lib/oracle/11.2/client64/lib > /etc/ld.so.conf.d/oracle-instantclient.conf
# ldconfig

# sqlplus64 myuser/mypassword@//oracle:1521/XE

# it is working fine
# SQL> select * from mytable;

#         ID DESCRIPTION
# ---------- --------------------------------------------------
# UPDATE_TS
# ---------------------------------------------------------------------------
#          1 kafka
# 16-OCT-19 03.47.32.000000 PM


# 16-OCT-2019 16:02:13 * (CONNECT_DATA=(SERVICE_NAME=XE)(CID=(PROGRAM=sqlplus64)(HOST=connect)(USER=root))) * (ADDRESS=(PROTOCOL=tcp)(HOST=172.30.0.6)(PORT=39520)) * establish * XE * 0

exit 0

# FIXTHIS: not working:
# getting
# {
#   "error_code": 500,
#   "message": "Request timed out"
# }
echo "Creating Oracle source connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "oracle-source",
               "config": {
                    "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/XE",
                    "table.whitelist":"MYTABLE",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"UPDATE_TS",
                    "incrementing.column.name":"ID",
                    "topic.prefix":"oracle-",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }}' \
     http://localhost:8083/connectors | jq .

# Wed Oct 16 15:28:10 2019
#16-OCT-2019 15:28:10 * (CONNECT_DATA=(CID=(PROGRAM=JDBC Thin Client)(HOST=__jdbc__)(USER=root))(SERVICE_NAME=xe)(CID=(PROGRAM=JDBC Thin Client)(HOST=__jdbc__)(USER=root))) * (ADDRESS=(PROTOCOL=tcp)(HOST=172.28.0.6)(PORT=39094)) * establish * xe * 0
# 172.28.0.6 is ip of connect

# HOST=__jdbc__: This hostname has been hard-coded as a false hostname inside the driver to force an IP address lookup

sleep 5

echo "Verifying topic oracle-mytable"
#docker container exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic oracle-mytable --from-beginning --max-messages 2


