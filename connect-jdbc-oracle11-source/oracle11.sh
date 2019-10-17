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




# This is a stack when connector is being created:


# "Session-HouseKeeper-1e8ab90f" #153 prio=5 os_prio=0 tid=0x00007f8aba648800 nid=0x18c waiting on condition [0x00007f8a0f1e3000]
#    java.lang.Thread.State: TIMED_WAITING (parking)
# 	at sun.misc.Unsafe.park(Native Method)
# 	- parking to wait for  <0x00000000f99812a0> (a java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject)
# 	at java.util.concurrent.locks.LockSupport.parkNanos(LockSupport.java:215)
# 	at java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject.awaitNanos(AbstractQueuedSynchronizer.java:2078)
# 	at java.util.concurrent.ScheduledThreadPoolExecutor$DelayedWorkQueue.take(ScheduledThreadPoolExecutor.java:1093)
# 	at java.util.concurrent.ScheduledThreadPoolExecutor$DelayedWorkQueue.take(ScheduledThreadPoolExecutor.java:809)
# 	at java.util.concurrent.ThreadPoolExecutor.getTask(ThreadPoolExecutor.java:1074)
# 	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1134)
# 	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
# 	at java.lang.Thread.run(Thread.java:748)

# "DistributedHerder-connect-1" #151 prio=5 os_prio=0 tid=0x00007f8aba6a4000 nid=0x18a runnable [0x00007f8a0f3e4000]
#    java.lang.Thread.State: RUNNABLE
# 	at java.net.SocketInputStream.socketRead0(Native Method)
# 	at java.net.SocketInputStream.socketRead(SocketInputStream.java:116)
# 	at java.net.SocketInputStream.read(SocketInputStream.java:171)
# 	at java.net.SocketInputStream.read(SocketInputStream.java:141)
# 	at oracle.net.ns.Packet.receive(Packet.java:308)
# 	at oracle.net.ns.DataPacket.receive(DataPacket.java:106)
# 	at oracle.net.ns.NetInputStream.getNextPacket(NetInputStream.java:324)
# 	at oracle.net.ns.NetInputStream.read(NetInputStream.java:268)
# 	at oracle.net.ns.NetInputStream.read(NetInputStream.java:190)
# 	at oracle.net.ns.NetInputStream.read(NetInputStream.java:107)
# 	at oracle.jdbc.driver.T4CSocketInputStreamWrapper.readNextPacket(T4CSocketInputStreamWrapper.java:124)
# 	at oracle.jdbc.driver.T4CSocketInputStreamWrapper.read(T4CSocketInputStreamWrapper.java:80)
# 	at oracle.jdbc.driver.T4CMAREngine.unmarshalUB1(T4CMAREngine.java:1137)
# 	at oracle.jdbc.driver.T4CTTIfun.receive(T4CTTIfun.java:350)
# 	at oracle.jdbc.driver.T4CTTIfun.doRPC(T4CTTIfun.java:227)
# 	at oracle.jdbc.driver.T4C8Oall.doOALL(T4C8Oall.java:531)
# 	at oracle.jdbc.driver.T4CPreparedStatement.doOall8(T4CPreparedStatement.java:208)
# 	at oracle.jdbc.driver.T4CPreparedStatement.executeForDescribe(T4CPreparedStatement.java:886)
# 	at oracle.jdbc.driver.OracleStatement.executeMaybeDescribe(OracleStatement.java:1175)
# 	at oracle.jdbc.driver.OracleStatement.doExecuteWithTimeout(OracleStatement.java:1296)
# 	at oracle.jdbc.driver.OraclePreparedStatement.executeInternal(OraclePreparedStatement.java:3613)
# 	at oracle.jdbc.driver.OraclePreparedStatement.executeQuery(OraclePreparedStatement.java:3657)
# 	- locked <0x00000000fcdd2820> (a oracle.jdbc.driver.T4CConnection)
# 	at oracle.jdbc.driver.OraclePreparedStatementWrapper.executeQuery(OraclePreparedStatementWrapper.java:1495)
# 	at oracle.jdbc.OracleDatabaseMetaData.getTables(OracleDatabaseMetaData.java:3078)
# 	- locked <0x00000000fcdf50e0> (a oracle.jdbc.driver.OracleDatabaseMetaData)
# 	at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.tableIds(GenericDatabaseDialect.java:361)
# 	at io.confluent.connect.jdbc.source.JdbcSourceConnectorConfig$TableRecommender.validValues(JdbcSourceConnectorConfig.java:607)
# 	at io.confluent.connect.jdbc.source.JdbcSourceConnectorConfig$CachingRecommender.validValues(JdbcSourceConnectorConfig.java:649)
# 	at org.apache.kafka.common.config.ConfigDef.validate(ConfigDef.java:606)
# 	at org.apache.kafka.common.config.ConfigDef.validate(ConfigDef.java:621)
# 	at org.apache.kafka.common.config.ConfigDef.validate(ConfigDef.java:529)
# 	at org.apache.kafka.common.config.ConfigDef.validateAll(ConfigDef.java:512)
# 	at org.apache.kafka.common.config.ConfigDef.validate(ConfigDef.java:494)
# 	at org.apache.kafka.connect.connector.Connector.validate(Connector.java:135)
# 	at org.apache.kafka.connect.runtime.AbstractHerder.validateConnectorConfig(AbstractHerder.java:313)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder$6.call(DistributedHerder.java:669)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder$6.call(DistributedHerder.java:666)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.tick(DistributedHerder.java:296)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.run(DistributedHerder.java:245)
# 	at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
# 	at java.util.concurrent.FutureTask.run(FutureTask.java:266)
# 	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
# 	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
# 	at java.lang.Thread.run(Thread.java:748)



#   private static class TableRecommender implements Recommender {

#     @SuppressWarnings("unchecked")
#     @Override
#     public List<Object> validValues(String name, Map<String, Object> config) {
#       String dbUrl = (String) config.get(CONNECTION_URL_CONFIG);
#       if (dbUrl == null) {
#         throw new ConfigException(CONNECTION_URL_CONFIG + " cannot be null.");
#       }
#       // Create the dialect to get the tables ...
#       AbstractConfig jdbcConfig = new AbstractConfig(CONFIG_DEF, config);
#       DatabaseDialect dialect = DatabaseDialects.findBestFor(dbUrl, jdbcConfig);
#       try (Connection db = dialect.getConnection()) {
#         List<Object> result = new LinkedList<>();
#         for (TableId id : dialect.tableIds(db)) {   <---- BLOCKING
#           // Just add the unqualified table name
#           result.add(id.tableName());
#         }
#         return result;
#       } catch (SQLException e) {
#         throw new ConfigException("Couldn't open connection to " + dbUrl, e);
#       }
#     }

#   @Override
#   public List<TableId> tableIds(Connection conn) throws SQLException {
#     DatabaseMetaData metadata = conn.getMetaData();
#     String[] tableTypes = tableTypes(metadata, this.tableTypes);

#     try (ResultSet rs = metadata.getTables(catalogPattern(), schemaPattern(), "%", tableTypes)) {
#       List<TableId> tableIds = new ArrayList<>();
#       while (rs.next()) {
#         String catalogName = rs.getString(1);
#         String schemaName = rs.getString(2);
#         String tableName = rs.getString(3);
#         TableId tableId = new TableId(catalogName, schemaName, tableName);
#         if (includeTable(tableId)) {
#           tableIds.add(tableId);
#         }
#       }
#       return tableIds;
#     }
#   }

# docker exec -it connect bash
# cd /root/instantclient
# javac -classpath /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar Metadata.java
# java -classpath "/usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar:." Metadata


# Output:

# root@connect:~/instantclient# java -classpath "/usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar:." Metadata
# The connection is successfully obtained
# Database Product Name: Oracle
# Database Product Version: Oracle Database 11g Express Edition Release 11.2.0.2.0 - 64bit Production
# Logged User: MYUSER
# JDBC Driver: Oracle JDBC driver
# Driver Version: 11.2.0.4.0