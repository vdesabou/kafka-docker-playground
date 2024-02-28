# How to use Kafka clients when Schema Registry is behind a proxy

## Objective

Quickly test how to use Kafka clients when Schema Registry is behind a proxy.


## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

## Details of what the script is doing



Blocking schema-registry `$IP` from connect to make sure proxy is used:

```bash
IP=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep schema-registry | cut -d " " -f 3)
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"

producing using `--property proxy.host=nginx-proxy -property proxy.port=8888`:

```bash
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property proxy.host=nginx-proxy -property proxy.port=8888 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

producing using `--property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888`:

```bash
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Verify data was sent to broker using `--property proxy.host=nginx-proxy -property proxy.port=8888`:

```bash
playground topic consume --topic a-topic --min-expected-messages 20 --timeout 60
```

Verify data was sent to broker using `--property schema.proxy.host=nginx-proxy -property schema.proxy.port=8888`:

```bash
playground topic consume --topic a-topic --min-expected-messages 20 --timeout 60
```

With connector:

```
log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink  << EOF
{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
               "topics": "a-topic",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.proxy.host": "nginx-proxy",
               "value.converter.proxy.port": "8888"
          }
EOF
```


With Java producer `schema.registry.proxy.host` and `schema.registry.proxy.port` should be set:

```
      KAFKA_SCHEMA_REGISTRY_PROXY_HOST: "nginx-proxy"
      KAFKA_SCHEMA_REGISTRY_PROXY_PORT: "8888"
```

