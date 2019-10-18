# InfluxDB Source connector

## Objective

Quickly test [InfluxDB Source](https://docs.confluent.io/current/connect/kafka-connect-influxdb/influx-db-source-connector/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)


## How to run

Simply run:

```
$ ./influxdb.sh
```

## Details of what the script is doing

Creating mydb database

```bash
$ curl -i -XPOST 'http://localhost:8086/query' --data-urlencode "q=CREATE DATABASE mydb"
```

Inserting data in database

```bash
$ curl -i -XPOST 'http://localhost:8086/write?db=mydb' --data-binary 'cpu_load_short,host=server01,region=us-west value=0.64 1434055562000000000'
```

Verifying data in mydb

```bash
$ curl -G 'http://localhost:8086/query?pretty=true' --data-urlencode "db=mydb" --data-urlencode "q=SELECT \"value\" FROM \"cpu_load_short\" WHERE \"region\"='us-west'"
```

Results:

```json
{
    "results": [
        {
            "statement_id": 0,
            "series": [
                {
                    "name": "cpu_load_short",
                    "columns": [
                        "time",
                        "value"
                    ],
                    "values": [
                        [
                            "2015-06-11T20:46:02Z",
                            0.64
                        ]
                    ]
                }
            ]
        }
    ]
}
```

Creating InfluxDB source connector

```bash
$ docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "InfluxDBSourceConnector",
               "config": {
                    "connector.class": "io.confluent.influxdb.source.InfluxdbSourceConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "influxdb.db": "mydb",
                    "mode": "timestamp",
                    "topic.prefix": "influx_",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
          }}' \
     http://localhost:8083/connectors | jq .
```

Verifying topic influx_cpu_load_short

```bash
$ docker container exec broker kafka-console-consumer --bootstrap-server localhost:9092 --topic influx_cpu_load_short --from-beginning --max-messages 1
```

Results:

```json
{
    "measurement": "cpu_load_short",
    "tags": {
        "host": "server01",
        "region": "us-west"
    },
    "time": "2015-06-11T20:46:02Z",
    "value": 0.64
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
