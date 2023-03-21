# JDBC Sybase source connector

## Objective

Quickly test [JDBC Sybase](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.


## How to run

Simply run:

```
$ ./sybase-source.sh
```

## Details of what the script is doing

Create the table and insert data.

```bash
docker exec -i sybase /sybase/isql -S -Usa -Ppassword << EOF
CREATE DATABASE testDB
GO
USE testDB

CREATE TABLE customers(id INTEGER IDENTITY,first_name VARCHAR(255) NOT NULL,last_name VARCHAR(255) NOT NULL,email VARCHAR(255) NOT NULL,primary key( id ))
GO
INSERT INTO customers(first_name,last_name,email) VALUES ('Sally','Thomas','sally.thomas@acme.com')
INSERT INTO customers(first_name,last_name,email) VALUES ('George','Bailey','gbailey@foobar.com')
INSERT INTO customers(first_name,last_name,email) VALUES ('Edward','Walker','ed@walker.com')
INSERT INTO customers(first_name,last_name,email) VALUES ('Anne','Kretchmar','annek@noanswer.org')
GO
EOF
```

Creating JDBC Sybase source connector

```bash
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class" : "io.confluent.connect.jdbc.JdbcSourceConnector",
                "tasks.max" : "1",
                "connection.url": "jdbc:jtds:sybase://sybase:5000/testDB",
                "connection.user": "sa",
                "connection.password": "password",
                "table.whitelist": "customers",
                "mode": "incrementing",
                "incrementing.column.name": "id",
                "topic.prefix": "sybase-",
                "validate.non.null":"false",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/jdbc-sybase-source/config | jq .
```

Insert another record

```bash
docker exec -i sybase /sybase/isql -S -Usa -Ppassword << EOF
USE testDB
GO
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com')
GO
EOF
```

Verifying topic sybase-customers

```bash
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sybase-customers --from-beginning --max-messages 5
```

Results:

```json
{"id":1,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com"}
{"id":2,"first_name":"George","last_name":"Bailey","email":"gbailey@foobar.com"}
{"id":3,"first_name":"Edward","last_name":"Walker","email":"ed@walker.com"}
{"id":4,"first_name":"Anne","last_name":"Kretchmar","email":"annek@noanswer.org"}
{"id":5,"first_name":"Pam","last_name":"Thomas","email":"pam@office.com"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
