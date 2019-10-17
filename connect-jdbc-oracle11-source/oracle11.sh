#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/ojdbc6.jar ]
then
     echo "ERROR: ${DIR}/ojdbc6.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# same issue as https://github.com/confluentinc/kafka-connect-jdbc/issues/654

# [2019-10-17 07:40:50,462] WARN [Worker clientId=connect-1, groupId=connect] This member will leave the group because consumer poll timeout has expired. This means the time between subsequent calls to poll() was longer than the configured max.poll.interval.ms, which typically implies that the poll loop is spending too much time processing messages. You can address this either by increasing max.poll.interval.ms or by reducing the maximum size of batches returned in poll() with max.poll.records. (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)

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


# Testing with simple Java program is also working
# root@connect:~/instantclient# javac -classpath /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar OracleSample.java
# root@connect:~/instantclient# java -classpath "/usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar:." OracleSample
# Current Date from Oracle is : 2019-10-17


# // Example Java Program - Oracle Database Connectivity
# import java.sql.Connection;
# import java.sql.Date;
# import java.sql.DriverManager;
# import java.sql.ResultSet;
# import java.sql.SQLException;
# import java.sql.Statement;

# // javac -classpath /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar OracleSample.java
# // java -classpath "/usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar:." OracleSample
# public class OracleSample {

#     public static final String DBURL = "jdbc:oracle:thin:@oracle:1521/XE";
#     public static final String DBUSER = "myuser";
#     public static final String DBPASS = "mypassword";

#     public static void main(String[] args) throws SQLException {

#         // Load Oracle JDBC Driver
#         DriverManager.registerDriver(new oracle.jdbc.driver.OracleDriver());

#         // Connect to Oracle Database
#         Connection con = DriverManager.getConnection(DBURL, DBUSER, DBPASS);

#         Statement statement = con.createStatement();

#         // Execute a SELECT query on Oracle Dummy DUAL Table. Useful for retrieving system values
#         // Enables us to retrieve values as if querying from a table
#         ResultSet rs = statement.executeQuery("SELECT SYSDATE FROM DUAL");


#         if (rs.next()) {
#             Date currentDate = rs.getDate(1); // get first column returned
#             System.out.println("Current Date from Oracle is : "+currentDate);
#         }
#         rs.close();
#         statement.close();
#         con.close();
#     }
# }

# 17-OCT-2019 08:41:35 * (CONNECT_DATA=(CID=(PROGRAM=JDBC Thin Client)(HOST=__jdbc__)(USER=root))(SERVICE_NAME=XE)(CID=(PROGRAM=JDBC Thin Client)(HOST=__jdbc__)(USER=root))) * (ADDRESS=(PROTOCOL=tcp)(HOST=172.19.0.6)(PORT=49788)) * establish * XE * 0


exit 0

# FIXTHIS: not working:
# getting
# {
#   "error_code": 500,
#   "message": "Request timed out"
# }
echo "Creating Oracle source connector"
docker container exec connect \
     curl -X POST --max-time 90000 \
     -H "Content-Type: application/json" \
     --data '{
               "name": "oracle-source3",
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
                    "consumer.max.poll.interval.ms": 900000000,
                    "max.poll.interval.ms": 900000000,
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }}' \
     http://localhost:8083/connectors | jq .


#17-OCT-2019 08:45:27 * (CONNECT_DATA=(CID=(PROGRAM=JDBC Thin Client)(HOST=__jdbc__)(USER=root))(SERVICE_NAME=XE)(CID=(PROGRAM=JDBC Thin Client)(HOST=__jdbc__)(USER=root))) * (ADDRESS=(PROTOCOL=tcp)(HOST=172.19.0.6)(PORT=49980)) * establish * XE * 0
# 172.19.0.6 is ip of connect

# HOST=__jdbc__: This hostname has been hard-coded as a false hostname inside the driver to force an IP address lookup

sleep 5

echo "Verifying topic oracle-mytable"
#docker container exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic oracle-mytable --from-beginning --max-messages 2


