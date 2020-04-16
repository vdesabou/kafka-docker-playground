# Debezium PostgreSQL source connector

![asciinema](asciinema.gif)

## Objective

Quickly test [Debezium PostGreSQL](https://docs.confluent.io/current/connect/debezium-connect-postgres/index.html#quick-start) connector.




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

Creating Debezium PostgreSQL source connector

```bash
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                    "tasks.max": "1",
                    "database.hostname": "postgres",
                    "database.port": "5432",
                    "database.user": "postgres",
                    "database.password": "postgres",
                    "database.dbname" : "postgres",
                    "database.server.name": "asgard",
                    "key.converter" : "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "transforms": "addTopicSuffix",
                    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.addTopicSuffix.regex":"(.*)",
                    "transforms.addTopicSuffix.replacement":"$1-raw"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .
```

Verifying topic asgard.public.customers-raw

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --max-messages 5
```

Result is:

```json
{
    "before": null,
    "after": {
        "asgard.public.customers.Value": {
            "id": 5,
            "first_name": {
                "string": "Hansiain"
            },
            "last_name": {
                "string": "Coda"
            },
            "email": {
                "string": "hcoda4@senate.gov"
            },
            "gender": {
                "string": "Male"
            },
            "club_status": {
                "string": "platinum"
            },
            "comments": {
                "string": "Centralized full-range approach"
            },
            "create_ts": {
                "long": 1570208046048403
            },
            "update_ts": {
                "long": 1570208046048403
            }
        }
    },
    "source": {
        "version": {
            "string": "0.9.5.Final"
        },
        "connector": {
            "string": "postgresql"
        },
        "name": "asgard",
        "db": "postgres",
        "ts_usec": {
            "long": 1570208093526000
        },
        "txId": {
            "long": 580
        },
        "lsn": {
            "long": 24523120
        },
        "schema": {
            "string": "public"
        },
        "table": {
            "string": "customers"
        },
        "snapshot": {
            "boolean": true
        },
        "last_snapshot_record": {
            "boolean": false
        },
        "xmin": null
    },
    "op": "r",
    "ts_ms": {
        "long": 1570208093526
    }
}
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
