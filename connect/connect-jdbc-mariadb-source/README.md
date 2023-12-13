# JDBC MariaDB Source connector



## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector with MariaDB.




## How to run

```
$ playground run -f mariadb<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

Creates the team table and insert some rows

```bash
CREATE TABLE team (
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(255) NOT NULL,
  email         VARCHAR(255) NOT NULL,
  last_modified DATETIME     NOT NULL
);

INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'kafka',
  'kafka@apache.org',
  NOW()
);
```

Creating MariaDB source connector

```bash
playground connector create-or-update --connector mariadb-source << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max": "1",
     "connection.url": "jdbc:mariadb://mariadb:3306/db?user=user&password=password&useSSL=false",
     "table.whitelist": "team",
     "mode": "timestamp+incrementing",
     "timestamp.column.name": "last_modified",
     "incrementing.column.name": "id",
     "topic.prefix": "mariadb-"
}
EOF
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])