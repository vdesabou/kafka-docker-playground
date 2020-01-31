# SFTP Source connector

## Objective

Quickly test [SFTP Source](https://docs.confluent.io/current/connect/kafka-connect-sftp/source-connector/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

* With CSV (no schema)

Simply run:

```bash
$ ./sftp-source-csv.sh
```

* With CSV (with schema)

Simply run:

```bash
$ ./sftp-source-csv-with-schema.sh
```

* With TSV

Simply run:

```bash
$ ./sftp-source-tsv.sh
```

* With JSON (no schema)

Simply run:

```bash
$ ./sftp-source-json.sh
```

* With JSON (with schema)

Simply run:

```bash
$ ./sftp-source-json-with-schema.sh
```


## Details of what the script is doing

Creating CSV SFTP Source connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
               "cleanup.policy":"NONE",
               "behavior.on.error":"IGNORE",
               "input.path": "/upload/input",
               "error.path": "/upload/error",
               "finished.path": "/upload/finished",
               "input.file.pattern": "csv-sftp-source.csv",
               "sftp.username":"foo",
               "sftp.password":"pass",
               "sftp.host":"sftp-server",
               "sftp.port":"22",
               "kafka.topic": "sftp-testing-topic",
               "csv.first.row.as.header": "true",
               "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/sftp-source-csv/config | jq .
```

Verifying topic `sftp-testing-topic`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sftp-testing-topic --from-beginning --max-messages 2
```

Results:

```json
{"id":{"string":"1"},"first_name":{"string":"Salmon"},"last_name":{"string":"Baitman"},"email":{"string":"sbaitman0@feedburner.com"},"gender":{"string":"Male"},"ip_address":{"string":"120.181.75.98"},"last_login":{"string":"2015-03-01T06:01:15Z"},"account_balance":{"string":"17462.66"},"country":{"string":"IT"},"favorite_color":{"string":"#f09bc0"}}
{"id":{"string":"2"},"first_name":{"string":"Debby"},"last_name":{"string":"Brea"},"email":{"string":"dbrea1@icio.us"},"gender":{"string":"Female"},"ip_address":{"string":"153.239.187.49"},"last_login":{"string":"2018-10-21T12:27:12Z"},"account_balance":{"string":"14693.49"},"country":{"string":"CZ"},"favorite_color":{"string":"#73893a"}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
