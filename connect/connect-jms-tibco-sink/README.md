# JMS TIBCO Sink connector

## Objective

Quickly test the [JMS Sink](https://docs.confluent.io/kafka-connectors/jms-sink/current/overview.html) connector with TIBCO Enterprise Message Service (EMS).

The TIBCO EMS docker image is built using [mikeschippers/docker-tibco](https://github.com/mikeschippers/docker-tibco).

## Prerequisites

Download [TIBCO EMS Community Edition](https://www.tibco.com/resources/product-download/tibco-enterprise-message-service-community-edition--free-download) and put `TIB_ems-ce_8.5.1_linux_x86_64.zip` into the `docker-tibco` directory.

If you're a Confluent employee, the zip file is downloaded automatically from the playground S3 bucket when AWS credentials are set (see this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900)).

With CP 8.x, the minimum supported connector version is 2.1.16 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-tibco-ems-sink.sh
```

## What the script does

1. Extracts `tibjms.jar` and `jms-2.0.jar` from the TIBCO EMS zip, builds the `tibems:latest` docker image (first run only) and copies `tibjms.jar` into the `confluentinc-kafka-connect-jms-sink` plugin `lib` folder.
2. Starts the environment with a TIBCO EMS container.
3. Produces 10 messages to topic `sink-messages` with `playground topic produce`.
4. Creates the JMS sink connector `jms-tibco-ems-sink` (`com.tibco.tibjms.naming.TibjmsInitialContextFactory`, `tibjmsnaming://tibco-ems:7222`, `QueueConnectionFactory`).
5. Verifies that the messages are in EMS queue `connector-quickstart` by running the `tibjmsMsgConsumer` Java sample inside the `tibco-ems` container.

## Notes

The queue `connector-quickstart` is not created with `tibemsadmin` because the TIBCO EMS Community Edition does not contain it. Instead, it is declared in [`docker-tibco/queues.conf`](docker-tibco/queues.conf), copied to `/home/tibusr` in the image:

```text
>
sample

queue.sample

connector-quickstart
```

Example of output of `tibjmsMsgConsumer`:

```text
Received message: TextMessage={ Header={ JMSMessageID={ID:E4EMS-SERVER.16093EAD44:57} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu May 06 13:16:18 UTC 2021} JMSDeliveryTime={Thu May 06 13:16:18 UTC 2021} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} } Text={16} }
```

## Credits

[mikeschippers/docker-tibco](https://github.com/mikeschippers/docker-tibco)
