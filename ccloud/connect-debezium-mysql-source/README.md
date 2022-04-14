# Debezium MySQL source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-debezium-mysql-source/asciinema.gif?raw=true)

## Objective

Quickly test [Debezium MySQL](https://docs.confluent.io/current/connect/debezium-connect-mysql/index.html#debezium-mysql-source-connector) connector.

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)


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
                    "database.history.kafka.topic": "schema-changes.mydb",
                    "transforms": "RemoveDots",
                    "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
                    "transforms.RemoveDots.replacement": "$1_$2_$3"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .
```


Verifying topic `dbserver1_mydb_team`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1_mydb_team --from-beginning --max-messages 2
```

Result:

```json
{
    "before": null,
    "after": {
        "dbserver1_mydb_team.Value": {
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
