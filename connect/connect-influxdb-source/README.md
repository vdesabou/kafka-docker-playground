# InfluxDB Source connector

![asciinema](asciinema.gif)

## Objective

Quickly test [InfluxDB Source](https://docs.confluent.io/current/connect/kafka-connect-influxdb/influx-db-source-connector/index.html#quick-start) connector.




## How to run

Simply run:

```
$ ./influxdb.sh
```

## Details of what the script is doing

log "Creating testdb database and inserting into coin table"

```bash

$ docker exec -i influxdb bash -c "influx -execute 'create database testdb'"
$ docker exec -i influxdb bash -c "influx -execute 'INSERT coin,id=1 value=100' -database testdb"
```

Verifying data in `testdb`

```bash
$ docker exec -i influxdb bash -c "influx -execute 'SELECT * from coin' -database testdb"
```

Results:

```
name: coin
time                id value
----                -- -----
1578663954475848300 1  100
1578663969811495300 1  100
```

Creating InfluxDB source connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.influxdb.source.InfluxdbSourceConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "influxdb.db": "testdb",
                    "mode": "timestamp",
                    "topic.prefix": "influx_",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/influxdb-source/config | jq .
```

Verifying topic `influx_testdb`

```bash
$ docker exec broker kafka-console-consumer --bootstrap-server localhost:9092 --topic influx_testdb --from-beginning --max-messages 1
```

Results:

```json
{
    "measurement": "coin",
    "tags": {
        "id": "1"
    },
    "time": "2020-01-10T13:48:37.0833919Z",
    "value": 100.0
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
