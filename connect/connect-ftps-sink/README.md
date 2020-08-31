# FTPS Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-ftps-sink/asciinema.gif?raw=true)

## Objective

Quickly test [FTPS Sink](https://docs.confluent.io/current/connect/kafka-connect-ftps/sink/index.html#ftps-sink-connector-for-cp) connector.



## How to run


Simply run:

```bash
$ ./ftps-sink.sh
```


## Details of what the script is doing

The connector is created with:

Creating FTPS Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "3",
               "connector.class": "io.confluent.connect.ftps.FtpsSinkConnector",
               "ftps.working.dir": "/",
               "ftps.username":"bob",
               "ftps.password":"test",
               "ftps.host":"ftps-server",
               "ftps.port":"220",
               "ftps.security.mode": "EXPLICIT",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "ftps.ssl.truststore.location": "/etc/kafka/secrets/kafka.ftps-server.truststore.jks",
               "ftps.ssl.truststore.password": "confluent",
               "ftps.ssl.keystore.location": "/etc/kafka/secrets/kafka.ftps-server.keystore.jks",
               "ftps.ssl.key.password": "confluent",
               "ftps.ssl.keystore.password": "confluent",
               "topics": "test_ftps_sink",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "format.class": "io.confluent.connect.ftps.sink.format.avro.AvroFormat",
               "flush.size": "1"
          }' \
     http://localhost:8083/connectors/ftps-sink/config | jq .
```

Sending messages to topic `test_ftps_sink`

```bash
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_ftps_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Listing content of `/home/vsftpd/bob/test_ftps_sink/partition\=0/`

```bash
$ docker exec sftp-server bash -c "ls /home/vsftpd/bob/test_ftps_sink/partition\=0/"
test_ftps_sink+0+0000000000.avro
test_ftps_sink+0+0000000001.avro
test_ftps_sink+0+0000000002.avro
test_ftps_sink+0+0000000003.avro
test_ftps_sink+0+0000000004.avro
test_ftps_sink+0+0000000005.avro
test_ftps_sink+0+0000000006.avro
test_ftps_sink+0+0000000007.avro
test_ftps_sink+0+0000000008.avro
test_ftps_sink+0+0000000009.avro
```

```bash
docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/test_ftps_sink+0+0000000000.avro
{"f1":"value1"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
