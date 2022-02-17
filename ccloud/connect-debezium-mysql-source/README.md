# Debezium MySQL source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-debezium-mysql-source/asciinema.gif?raw=true)

## Objective

Quickly test [Debezium MySQL](https://docs.confluent.io/current/connect/debezium-connect-mysql/index.html#debezium-mysql-source-connector) connector.

## Prerequisites

* Properly initialized Confluent Cloud CLI

You must be already logged in with confluent CLI which needs to be setup with correct environment, cluster and api key to use:

Typical commands to run:

```bash
$ confluent login --save

Use environment $ENVIRONMENT_ID:
$ confluent environment use $ENVIRONMENT_ID

Use cluster $CLUSTER_ID:
$ confluent kafka cluster use $CLUSTER_ID

Store api key $API_KEY:
$ confluent api-key store $API_KEY $API_SECRET --resource $CLUSTER_ID --force

Use api key $API_KEY:
$ confluent api-key use $API_KEY --resource $CLUSTER_ID
```

* Create a file `$HOME/.confluent/config`

You should have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";

// Schema Registry specific settings
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR_API_KEY>:<SR_API_SECRET>
schema.registry.url=<SR ENDPOINT>

// license
confluent.license=<YOUR LICENSE>

// ccloud login password
ccloud.user=<ccloud login>
ccloud.password=<ccloud password>
```


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
