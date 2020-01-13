# JDBC PostgreSQL source connector

## Objective

Quickly test [JDBC PostGreSQL](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./postgres.sh
```

## Details of what the script is doing

Show content of CUSTOMERS table:

```bash
$ docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"
```

Adding an element to the table

```bash
$ docker exec postgres psql -U postgres -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"
```


Show content of CUSTOMERS table:

```bash
$ docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"
```

Creating JDBC PostgreSQL source connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://postgres/postgres?user=postgres&password=postgres&ssl=false",
                    "table.whitelist": "customers",
                    "mode": "timestamp+incrementing",
                    "timestamp.column.name": "update_ts",
                    "incrementing.column.name": "id",
                    "topic.prefix": "postgres-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/postgres-source/config | jq_docker_cli .
```

Verifying topic `postgres-customers`

```bash
$ docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic postgres-customers --from-beginning --max-messages 5
```

Result is:

```json
{
    "id": 1,
    "first_name": {
        "string": "Rica"
    },
    "last_name": {
        "string": "Blaisdell"
    },
    "email": {
        "string": "rblaisdell0@rambler.ru"
    },
    "gender": {
        "string": "Female"
    },
    "club_status": {
        "string": "bronze"
    },
    "comments": {
        "string": "Universal optimal hierarchy"
    },
    "create_ts": {
        "long": 1571844488922
    },
    "update_ts": {
        "long": 1571844488922
    }
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
