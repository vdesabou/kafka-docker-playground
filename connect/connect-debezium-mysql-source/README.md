# Debezium MySQL source connector

## Objective

Quickly test [Debezium MySQL](https://docs.confluent.io/current/connect/debezium-connect-mysql/index.html#debezium-mysql-source-connector) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./mysql.sh
```

## Details of what the script is doing


Describing the team table in DB `mydb`

```bash
$ docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'describe team'"
```

Show content of team table:

```bash
$ docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"
```

Adding an element to the table

```bash
docker exec mysql mysql --user=root --password=password --database=mydb -e "
INSERT INTO team (   \
  id,   \
  name, \
  email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
); "
```


Creating Debezium MySQL source connector

```bash
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.mysql.MySqlConnector",
                    "tasks.max": "1",
                    "database.hostname": "mysql",
                    "database.port": "3306",
                    "database.user": "debezium",
                    "database.password": "dbz",
                    "database.server.id": "223344",
                    "database.server.name": "dbserver1",
                    "database.whitelist": "mydb",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.mydb"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq_docker_cli .
```


Verifying topic `dbserver1.mydb.team`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1.mydb.team --from-beginning --max-messages 2
```

Result:

```json
{
    "before": null,
    "after": {
        "dbserver1.mydb.team.Value": {
            "id": 1,
            "name": "kafka",
            "email": "kafka@apache.org",
            "last_modified": 1570207570000
        }
    },
    "source": {
        "version": {
            "string": "0.9.5.Final"
        },
        "connector": {
            "string": "mysql"
        },
        "name": "dbserver1",
        "server_id": 0,
        "ts_sec": 0,
        "gtid": null,
        "file": "mysql-bin.000003",
        "pos": 457,
        "row": 0,
        "snapshot": {
            "boolean": true
        },
        "thread": null,
        "db": {
            "string": "mydb"
        },
        "table": {
            "string": "team"
        },
        "query": null
    },
    "op": "c",
    "ts_ms": {
        "long": 1570207619721
    }
}
```
N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
