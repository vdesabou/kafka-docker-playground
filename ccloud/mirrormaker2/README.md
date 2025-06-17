# Using Mirror Maker 2 with Confluent Cloud

## Objective

[Run Mirror Maker 2](https://cwiki.apache.org/confluence/display/KAFKA/KIP-382%3A+MirrorMaker+2.0) with Confluent Cloud

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

## How to run

```
$ just use <playground run> command and search for mirrormaker2.sh in this folder
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
seq -f "A_sale_%g ${RANDOM}" 20 | docker container exec -i broker1 kafka-console-producer --bootstrap-server localhost:9092 --topic sales_A
```

Consumer with group my-consumer-group reads 10 messages in A cluster (OnPrem)

```bash
docker exec -i connect bash -c "kafka-console-consumer --bootstrap-server broker1:9092 --include 'sales_A' --from-beginning --max-messages 10 --consumer-property group.id=my-consumer-group"
```

sleeping 70 seconds

```bash
sleep 70
```

Consumer with group my-consumer-group reads 10 messages in B cluster (Confluent Cloud), it should start from previous offset (`sync.group.offsets.enabled = true`)

```bash
playground topic consume --topic sales_A --min-expected-messages 10 --timeout 60
```
