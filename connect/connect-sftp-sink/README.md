# SFTP Sink connector

## Objective

Quickly test [SFTP Sink](https://docs.confluent.io/current/connect/kafka-connect-sftp/sink-connector/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)

## How to run

Simply run:

```bash
$ ./sftp-sink.sh
```

## Details of what the script is doing

The connector is created with:

Creating SFTP Sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpSinkConnector",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
               "flush.size": "3",
               "schema.compatibility": "NONE",
               "format.class": "io.confluent.connect.sftp.sink.format.avro.AvroFormat",
               "storage.class": "io.confluent.connect.sftp.sink.storage.SftpSinkStorage",
               "sftp.host": "sftp-server",
               "sftp.port": "22",
               "sftp.username": "foo",
               "sftp.password": "pass",
               "sftp.working.dir": "/upload",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/sftp-sink/config | jq .
```

Sending messages to topic `test_sftp_sink`

```bash
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic test_sftp_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Listing content of `./upload/topics/test_sftp_sink/partition\=0/`

```bash
$ ls ./upload/topics/test_sftp_sink/partition\=0/
test_sftp_sink+0+0000000000.avro  test_sftp_sink+0+0000000003.avro  test_sftp_sink+0+0000000006.avro  test_sftp_sink+0+0000000009.avro
```

```bash
docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/test_sftp_sink+0+0000000000.avro
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
