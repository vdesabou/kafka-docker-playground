# SFTP Sink connector



## Objective

Quickly test [SFTP Sink](https://docs.confluent.io/current/connect/kafka-connect-sftp/sink-connector/index.html#quick-start) connector.



## How to run

Simply run:

```bash
$ just use <playground run> command and search for sftp-sink.sh in this folder
```

or with Kerberos

```bash
$ just use <playground run> command and search for sftp-sink-kerberos.sh in this folder
```

or with SSH key

```bash
$ just use <playground run> command and search for sftp-sink-ssh-key.sh in this folder
```

or with SSH PEM file

```bash
$ just use <playground run> command and search for sftp-sink-ssh-pem-file.sh in this folder
```

## Details of what the script is doing

The connector is created with:

Creating SFTP Sink connector

```bash
$ curl -X PUT \
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
$ playground topic produce -t test_sftp_sink --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF
```

Listing content of `/home/foo/upload/topics/test_sftp_sink/partition\=0/`

```bash
$ docker exec sftp-server bash -c "ls /home/foo/upload/topics/test_sftp_sink/partition\=0/"
test_sftp_sink+0+0000000000.avro  test_sftp_sink+0+0000000003.avro  test_sftp_sink+0+0000000006.avro  test_sftp_sink+0+0000000009.avro
```

```bash
docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/test_sftp_sink+0+0000000000.avro
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
