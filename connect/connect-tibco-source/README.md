# TIBCO Source connector

## Objective

Quickly test the [TIBCO Source](https://docs.confluent.io/current/connect/kafka-connect-tibco/source/index.html#quick-start) connector.

TIBCO EMS runs in a Docker image built from [mikeschippers/docker-tibco](https://github.com/mikeschippers/docker-tibco).

## Prerequisites

* With CP 8.x, connector version 1.2.0 or later.
* Download [TIBCO EMS Community Edition](https://www.tibco.com/resources/product-download/tibco-enterprise-message-service-community-edition--free-download) and put `TIB_ems-ce_8.5.1_linux_x86_64.zip` into the `docker-tibco` directory. If it is missing, the script tries to download it from the playground S3 bucket (Confluent employees only, with AWS credentials set). Confluent employees can also check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900).

## How to run

```bash
playground run -f tibco-ems.sh
```

## What the script does

1. Extracts `tibjms.jar` and `jms-2.0.jar` from the EMS zip (if not already present), copies `tibjms.jar` into the connector `lib` folder, and builds the `tibems:latest` Docker image (first run only, it can take a while).
2. Sends 5 messages (`m1` to `m5`) to the EMS queue `connector-quickstart` with the TIBCO `tibjmsMsgProducer` Java sample in the `tibco-ems` container.
3. Creates the TIBCO Source connector reading the queue on `tcp://tibco-ems:7222` and writing to topic `from-tibco-messages`.
4. Verifies the messages with `playground topic consume --topic from-tibco-messages`.

## Queue creation

The queue `connector-quickstart` is not created with `tibemsadmin` as described in the Quick Start, because TIBCO Enterprise Message Service Community Edition does not contain it. Instead, the image ships `docker-tibco/queues.conf` in `/home/tibusr`, which contains:

```
>
sample

queue.sample

connector-quickstart
```
