# File Pulse Source connector

## Objective

Quickly test [File Pulse Source](https://github.com/streamthoughts/kafka-connect-file-pulse) connector.


## How to run

Simply run:

```
$ ./csv.sh
```

## Details of what the script is doing

### CSV Example


Generating data

```bash
$ docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL https://raw.githubusercontent.com/streamthoughts/kafka-connect-file-pulse/master/datasets/quickstart-musics-dataset.csv -o /tmp/kafka-connect/examples/quickstart-musics-dataset.csv"
```

Creating CSV FilePulse Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data @connect-file-pulse-quickstart-csv.json \
     http://localhost:8083/connectors/filepulse-source-csv/config | jq .
```

Verify we have received the data in `connect-file-pulse-quickstart-csv` topic

```bash
$ 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic connect-file-pulse-quickstart-csv --from-beginning --max-messages 10
```

Results:

```json
{"title":{"string":"40"},"album":{"string":"War"},"duration":{"string":"02:38"},"release":{"string":"1983"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Acrobat"},"album":{"string":"Achtung Baby"},"duration":{"string":"04:30"},"release":{"string":"1991"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Bullet the Blue Sky"},"album":{"string":"The Joshua Tree"},"duration":{"string":"04:31"},"release":{"string":"1987"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Drowning Man"},"album":{"string":"War"},"duration":{"string":"04:14"},"release":{"string":"1983"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Even Better Than the Real Thing"},"album":{"string":"Achtung Baby"},"duration":{"string":"03:41"},"release":{"string":"1991"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Exit"},"album":{"string":"The Joshua Tree"},"duration":{"string":"04:13"},"release":{"string":"1987"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"In God's Country"},"album":{"string":"The Joshua Tree"},"duration":{"string":"02:56"},"release":{"string":"1987"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"I Still Haven't Found What I'm Looking For"},"album":{"string":"The Joshua Tree"},"duration":{"string":"04:37"},"release":{"string":"1987"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Like a Song..."},"album":{"string":"War"},"duration":{"string":"04:47"},"release":{"string":"1983"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Love is Blindness"},"album":{"string":"Achtung Baby"},"duration":{"string":"04:23"},"release":{"string":"1991"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
