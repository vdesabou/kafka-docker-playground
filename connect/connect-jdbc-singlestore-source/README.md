# JDBC Singlestore sink connector

## Objective

Quickly test [JDBC Singlestore](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.


## How to run

Simply run:

```
$ just use <playground run> command and search for jdbc-singlestore-sink.sh in this folder
```

## Details of what the script is doing


Creating 'db' SingleStore database and table 'application':

```bash
docker exec singlestore memsql -u root -proot -e "
CREATE DATABASE IF NOT EXISTS db;  \
USE db; \
CREATE TABLE IF NOT EXISTS application ( \
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT, \
  name          VARCHAR(255) NOT NULL, \
  team_email    VARCHAR(255) NOT NULL, \
  last_modified DATETIME     NOT NULL \
); \
INSERT INTO application ( \
  id, \
  name, \
  team_email, \
  last_modified \
) VALUES ( \
  1, \
  'kafka', \
  'kafka@apache.org', \
  NOW() \
);"
```

Describing the application table in DB 'db':

```bash
docker exec singlestore memsql -u root -proot -e "USE db;describe application"
```

Show content of application table::

```bash
docker exec singlestore memsql -u root -proot -e "USE db;select * from application"
```

Adding an element to the table:

```bash
docker exec singlestore memsql -u root -proot -e "USE db;
INSERT INTO application (   \
  id,   \
  name, \
  team_email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
); "
```

Show content of application table::

```bash
docker exec singlestore memsql -u root -proot -e "USE db;select * from application"
```

Creating JDBC Singlestore source connector:

```bash
playground connector create-or-update --connector jdbc-singlestore-source  << EOF
{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"1",
               "connection.url":"jdbc:mysql://singlestore:3306/db?user=root&password=root&useSSL=false",
               "table.whitelist":"application",
               "mode":"timestamp+incrementing",
               "timestamp.column.name":"last_modified",
               "incrementing.column.name":"id",
               "topic.prefix":"singlestore-"

          }
EOF
```

sleep 5

Verifying topic singlestore-application:

```bash
playground topic consume --topic singlestore-application --min-expected-messages 2 --timeout 60
```

Results:

```
{"id":1,"name":"kafka","team_email":"kafka@apache.org","last_modified":1644341162000}
{"id":2,"name":"another","team_email":"another@apache.org","last_modified":1644341163000}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
