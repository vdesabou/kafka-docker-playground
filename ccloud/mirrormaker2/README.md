# Using Mirror Maker 2 with Confluent Cloud

## Objective

[Run Mirror Maker 2](https://cwiki.apache.org/confluence/display/KAFKA/KIP-382%3A+MirrorMaker+2.0) with Confluent Cloud

## How to run

```
$ ./mirrormaker2.sh
```

## Details of what the script is doing

Start MirrorMaker2 (logs are in mirrormaker.log):

```bash
docker cp ${DIR}/connect-mirror-maker.properties connect:/tmp/connect-mirror-maker.properties
docker exec -i connect /usr/bin/connect-mirror-maker /tmp/connect-mirror-maker.properties > mirrormaker.log 2>&1 &
```

sleeping 30 seconds

```bash
sleep 30
```

Sending messages in A cluster (OnPrem)

```bash
seq -f "A_sale_%g ${RANDOM}" 20 | docker container exec -i broker1 kafka-console-producer --broker-list localhost:9092 --topic sales_A
```

Consumer with group my-consumer-group reads 10 messages in A cluster (OnPrem)

```bash
docker exec -i connect bash -c "kafka-console-consumer --bootstrap-server broker1:9092 --whitelist 'sales_A' --from-beginning --max-messages 10 --consumer-property group.id=my-consumer-group"
```

sleeping 70 seconds

```bash
sleep 70
```

Consumer with group my-consumer-group reads 10 messages in B cluster (Confluent Cloud), it should start from previous offset

```bash
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" connect bash -c 'kafka-console-consumer --topic sales_A --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --max-messages 10 --consumer-property group.id=my-consumer-group'
```
