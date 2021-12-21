# How to use kafka-avro-console-producer and kafka-avro-console-consumer when Schema Registry is behind a proxy

## Objective

Quickly test how to use kafka-avro-console-producer and kafka-avro-console-consumer when Schema Registry is behind a proxy.


## How to run

Simply run:

```
$ ./start.sh
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
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property proxy.host=nginx-proxy -property proxy.port=8888 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 20
```

Verify data was sent to broker using `--property schema.proxy.host=nginx-proxy -property schema.proxy.port=8888`:

```bash
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 20
```