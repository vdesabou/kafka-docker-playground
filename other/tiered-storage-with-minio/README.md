# Tiered storage with Minio

![asciinema](asciinema.gif)

## Objective

Quickly test [Tiered Storage](https://docs.confluent.io/current/kafka/tiered-storage-preview.html#tiered-storage) with [Minio](https://min.io).

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)


## How to run

Simply run:

```
$ ./start.sh
```

Minio UI is accessible at [http://127.0.0.1:9000](http://127.0.0.1:9000]) (`AKIAIOSFODNN7EXAMPLE`/`wJalrXUtnFEMI7K7MDENG8bPxRfiCYEXAMPLEKEY`)

## Details of what the script is doing

Broker has following configuration:

```yml
    environment:
      # Tiered Storage Configuration Parameters (v5.4.0)
      KAFKA_CONFLUENT_TIER_FEATURE: "true"
      KAFKA_CONFLUENT_TIER_ENABLE: "true"
      KAFKA_CONFLUENT_TIER_BACKEND: "S3"
      KAFKA_CONFLUENT_TIER_S3_AWS_ENDPOINT_OVERRIDE: "http://minio:9000"
      KAFKA_CONFLUENT_TIER_S3_SSE_ALGORITHM: "none"
      KAFKA_CONFLUENT_TIER_S3_BUCKET: "minio-tiered-storage"
      KAFKA_CONFLUENT_TIER_S3_REGION: "us-west-1"
      KAFKA_CONFLUENT_TIER_METADATA_REPLICATION_FACTOR: 1
      KAFKA_CONFLUENT_TIER_S3_AWS_ACCESS_KEY_ID: "AKIAIOSFODNN7EXAMPLE"
      KAFKA_CONFLUENT_TIER_S3_AWS_SECRET_ACCESS_KEY: "wJalrXUtnFEMI7K7MDENG8bPxRfiCYEXAMPLEKEY"
      KAFKA_LOG_SEGMENT_BYTES: 1048576 #1Mb
```

Create topic `TieredStorage`

```bash
$ docker exec broker kafka-topics --bootstrap-server 127.0.0.1:9092 --create --topic TieredStorage --partitions 6 --replication-factor 1 --config confluent.tier.enable=true --config confluent.tier.local.hotset.ms=60000 --config retention.ms=86400000
```

Sending messages to topic `TieredStorage`

```bash
$ seq -f "This is a message %g" 200000 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic TieredStorage
```

Check for uploaded log segments

```bash
$ docker container logs broker | grep "Uploaded"
```

```log
[2020-02-05 14:41:40,972] INFO Uploaded segment for NolqVXePTAGo3NdXJ0d0-g-TieredStorage-3 in 389ms (kafka.tier.tasks.archive.ArchiveTask)
[2020-02-05 14:41:40,976] INFO Uploaded segment for NolqVXePTAGo3NdXJ0d0-g-TieredStorage-2 in 342ms (kafka.tier.tasks.archive.ArchiveTask)
[2020-02-05 14:41:42,072] INFO Uploaded segment for NolqVXePTAGo3NdXJ0d0-g-TieredStorage-0 in 63ms (kafka.tier.tasks.archive.ArchiveTask)
[2020-02-05 14:46:07,165] INFO Uploaded segment for 7-5PbXoAS1WpPa62CVfvKQ-_confluent-controlcenter-5-4-0-1-MetricsAggregateStore-repartition-0 in 66ms (kafka.tier.tasks.archive.ArchiveTask)
[2020-02-05 14:51:07,263] INFO Uploaded segment for 7-5PbXoAS1WpPa62CVfvKQ-_confluent-controlcenter-5-4-0-1-MetricsAggregateStore-repartition-0 in 63ms (kafka.tier.tasks.archive.ArchiveTask)
```

![Minio](Screenshot1.png)

Sleep 5 minutes (confluent.tier.local.hotset.ms=60000)

```bash
$ sleep 300
```

Check for deleted log segments:

```bash
$ docker container logs broker | grep "Found deletable segments"
```

```log
[2020-02-05 14:46:19,554] INFO [Log partition=TieredStorage-0, dir=/var/lib/kafka/data] Found deletable segments with base offsets [0] due to HotsetRetention time 60000ms breach (kafka.log.Log)
[2020-02-05 14:46:19,558] INFO [Log partition=TieredStorage-3, dir=/var/lib/kafka/data] Found deletable segments with base offsets [0] due to HotsetRetention time 60000ms breach (kafka.log.Log)
[2020-02-05 14:46:19,560] INFO [Log partition=TieredStorage-2, dir=/var/lib/kafka/data] Found deletable segments with base offsets [0] due to HotsetRetention time 60000ms breach (kafka.log.Log)
```

Control Center showing rolled and migrated segments (partitions 0, 2, 3 4 and 5)

![TieredStorage topic](Screenshot2.png)

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
