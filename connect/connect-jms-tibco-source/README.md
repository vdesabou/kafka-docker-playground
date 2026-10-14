# JMS TIBCO Source connector

## Objective

Quickly test the [JMS Source](https://docs.confluent.io/kafka-connectors/jms-source/current/overview.html) connector with TIBCO Enterprise Message Service (EMS).

The TIBCO EMS docker image is built using [mikeschippers/docker-tibco](https://github.com/mikeschippers/docker-tibco).

## Prerequisites

Download [TIBCO EMS Community Edition](https://www.tibco.com/resources/product-download/tibco-enterprise-message-service-community-edition--free-download) and put `TIB_ems-ce_8.5.1_linux_x86_64.zip` into the `docker-tibco` directory.

If you're a Confluent employee, the zip file is downloaded automatically from the playground S3 bucket when AWS credentials are set (see this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900)).

With CP 8.x, the minimum supported connector version is 12.2.0 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-tibco.sh
```

## What the script does

1. Extracts `tibjms.jar` and `jms-2.0.jar` from the TIBCO EMS zip, builds the `tibems:latest` docker image (first run only) and copies both jars into the `confluentinc-kafka-connect-jms` plugin `lib` folder.
2. Starts the environment with a TIBCO EMS container.
3. Sends EMS messages `m1` to `m5` to queue `connector-quickstart` with the `tibjmsMsgProducer` Java sample.
4. Creates the JMS source connector `jms-tibco-source` (`com.tibco.tibjms.naming.TibjmsInitialContextFactory`, `tibjmsnaming://tibco-ems:7222`).
5. Verifies that topic `from-tibco-messages` receives the messages with `playground topic consume`.
6. Asserts, with the `tibjmsMsgConsumer` sample, that queue `connector-quickstart` is empty, i.e. messages were acknowledged and deleted after being committed.

## Notes

The queue `connector-quickstart` is not created with `tibemsadmin` because the TIBCO EMS Community Edition does not contain it. Instead, it is declared in [`docker-tibco/queues.conf`](docker-tibco/queues.conf), copied to `/home/tibusr` in the image:

```text
>
sample

queue.sample

connector-quickstart
```

The connection factory is declared in [`docker-tibco/factories.conf`](docker-tibco/factories.conf):

```text
[ConnectionFactory]
  type                  = generic
  url                   = tcp://7222
```

Example of record:

```text
Struct{messageID=ID:E4EMS-SERVER.15DA9975B3:1,messageType=text,timestamp=1571395609724,deliveryMode=2,destination=Struct{destinationType=queue,name=connector-quickstart},redelivered=false,expiration=0,priority=4,properties={JMSXDeliveryCount=Struct{propertyType=integer,integer=1}},text=m1}
```

## Credits

[mikeschippers/docker-tibco](https://github.com/mikeschippers/docker-tibco)
