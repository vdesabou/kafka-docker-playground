# Tiered storage with Minio

![asciinema](asciinema.gif)

## Objective

Quickly test [Tiered Storage](https://docs.confluent.io/current/kafka/tiered-storage-preview.html#tiered-storage) with [Minio](https://min.io).

## Disclaimer

[Tiered Storage](https://docs.confluent.io/current/kafka/tiered-storage-preview.html#tiered-storage) is a preview feature and only currently supported with AWS.

**⚠️ Minio is not supported**


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
[2020-02-05 16:16:51,092] INFO Uploaded segment for e-RG-7KYTD22ym0zvWaCDA-TieredStorage-2 in 406ms (kafka.tier.tasks.archive.ArchiveTask)
[2020-02-05 16:16:51,109] INFO Uploaded segment for e-RG-7KYTD22ym0zvWaCDA-TieredStorage-1 in 475ms (kafka.tier.tasks.archive.ArchiveTask)
[2020-02-05 16:16:51,427] INFO Uploaded segment for e-RG-7KYTD22ym0zvWaCDA-TieredStorage-0 in 187ms (kafka.tier.tasks.archive.ArchiveTask)
[2020-02-05 16:16:51,520] INFO Uploaded segment for e-RG-7KYTD22ym0zvWaCDA-TieredStorage-3 in 229ms (kafka.tier.tasks.archive.ArchiveTask)
```

![Minio](Screenshot1.png)

Listing objects of bucket `minio-tiered-storage` in Minio:

```bash
$ docker container restart list-buckets
$ docker container logs --tail=100 list-buckets
```

```log
Added `myminio` successfully.
Added `myminio` successfully.
[2020-02-05 16:16:51 UTC]      8B 0/-9twBPT1TWmFRZr_cKeDTA/e-RG-7KYTD22ym0zvWaCDA/1/00000000000000000000_0_v0.epoch-state
[2020-02-05 16:16:51 UTC]    512B 0/-9twBPT1TWmFRZr_cKeDTA/e-RG-7KYTD22ym0zvWaCDA/1/00000000000000000000_0_v0.offset-index
[2020-02-05 16:16:51 UTC]     10B 0/-9twBPT1TWmFRZr_cKeDTA/e-RG-7KYTD22ym0zvWaCDA/1/00000000000000000000_0_v0.producer-state
[2020-02-05 16:16:51 UTC] 1020KiB 0/-9twBPT1TWmFRZr_cKeDTA/e-RG-7KYTD22ym0zvWaCDA/1/00000000000000000000_0_v0.segment
[2020-02-05 16:16:51 UTC]    768B 0/-9twBPT1TWmFRZr_cKeDTA/e-RG-7KYTD22ym0zvWaCDA/1/00000000000000000000_0_v0.timestamp-index
[2020-02-05 16:16:51 UTC]      8B 0/5LYG6KkBTwa-_cPTur3Zsg/e-RG-7KYTD22ym0zvWaCDA/3/00000000000000000000_0_v0.epoch-state
[2020-02-05 16:16:51 UTC]    512B 0/5LYG6KkBTwa-_cPTur3Zsg/e-RG-7KYTD22ym0zvWaCDA/3/00000000000000000000_0_v0.offset-index
[2020-02-05 16:16:51 UTC]     10B 0/5LYG6KkBTwa-_cPTur3Zsg/e-RG-7KYTD22ym0zvWaCDA/3/00000000000000000000_0_v0.producer-state
[2020-02-05 16:16:51 UTC] 1024KiB 0/5LYG6KkBTwa-_cPTur3Zsg/e-RG-7KYTD22ym0zvWaCDA/3/00000000000000000000_0_v0.segment
[2020-02-05 16:16:51 UTC]    768B 0/5LYG6KkBTwa-_cPTur3Zsg/e-RG-7KYTD22ym0zvWaCDA/3/00000000000000000000_0_v0.timestamp-index
[2020-02-05 16:16:51 UTC]      8B 0/ntTwI5g9Q1W7ZcdXYDstCw/e-RG-7KYTD22ym0zvWaCDA/0/00000000000000000000_0_v0.epoch-state
[2020-02-05 16:16:51 UTC]    504B 0/ntTwI5g9Q1W7ZcdXYDstCw/e-RG-7KYTD22ym0zvWaCDA/0/00000000000000000000_0_v0.offset-index
[2020-02-05 16:16:51 UTC]     10B 0/ntTwI5g9Q1W7ZcdXYDstCw/e-RG-7KYTD22ym0zvWaCDA/0/00000000000000000000_0_v0.producer-state
[2020-02-05 16:16:51 UTC] 1024KiB 0/ntTwI5g9Q1W7ZcdXYDstCw/e-RG-7KYTD22ym0zvWaCDA/0/00000000000000000000_0_v0.segment
[2020-02-05 16:16:51 UTC]    768B 0/ntTwI5g9Q1W7ZcdXYDstCw/e-RG-7KYTD22ym0zvWaCDA/0/00000000000000000000_0_v0.timestamp-index
[2020-02-05 16:16:51 UTC]      8B 0/rhJILwoVSI2U6T3CWxAA4g/e-RG-7KYTD22ym0zvWaCDA/2/00000000000000000000_0_v0.epoch-state
[2020-02-05 16:16:51 UTC]    496B 0/rhJILwoVSI2U6T3CWxAA4g/e-RG-7KYTD22ym0zvWaCDA/2/00000000000000000000_0_v0.offset-index
[2020-02-05 16:16:51 UTC]     10B 0/rhJILwoVSI2U6T3CWxAA4g/e-RG-7KYTD22ym0zvWaCDA/2/00000000000000000000_0_v0.producer-state
[2020-02-05 16:16:50 UTC] 1008KiB 0/rhJILwoVSI2U6T3CWxAA4g/e-RG-7KYTD22ym0zvWaCDA/2/00000000000000000000_0_v0.segment
[2020-02-05 16:16:51 UTC]    756B 0/rhJILwoVSI2U6T3CWxAA4g/e-RG-7KYTD22ym0zvWaCDA/2/00000000000000000000_0_v0.timestamp-index
```

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
