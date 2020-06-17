# Adding a second Connect worker

## Objective

Verify that a task rebalance is happening when a new Kafka Connect worker is added to a distributed Connect cluster


## How to run

Simply run:

```bash
$ ./start.sh
```

## Details of what the script is doing

Creating SFTP Sink connector with 4 tasks

```
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "4",
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

Getting tasks placement

```bash
$ curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq
```

```json
{
  "name": "sftp-sink",
  "connector": {
    "state": "RUNNING",
    "worker_id": "connect:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "connect:8083"
    },
    {
      "id": 1,
      "state": "RUNNING",
      "worker_id": "connect:8083"
    },
    {
      "id": 2,
      "state": "RUNNING",
      "worker_id": "connect:8083"
    },
    {
      "id": 3,
      "state": "RUNNING",
      "worker_id": "connect:8083"
    }
  ],
  "type": "sink"
}
```

Adding a second connect worker

```bash
$ docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" -f "${PWD}/docker-compose.add-connect-worker.yml" up -d
```

Getting tasks placement

```bash
$ curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq
```

```json
{
  "name": "sftp-sink",
  "connector": {
    "state": "RUNNING",
    "worker_id": "connect:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "connect2:8083"
    },
    {
      "id": 1,
      "state": "RUNNING",
      "worker_id": "connect2:8083"
    },
    {
      "id": 2,
      "state": "RUNNING",
      "worker_id": "connect:8083"
    },
    {
      "id": 3,
      "state": "RUNNING",
      "worker_id": "connect:8083"
    }
  ],
  "type": "sink"
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
