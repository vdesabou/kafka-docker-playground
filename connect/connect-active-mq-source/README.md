# ActiveMQ Source connector

## Objective

Quickly test the [ActiveMQ Source](https://docs.confluent.io/kafka-connectors/activemq-source/current/overview.html) connector.

ActiveMQ runs with the [rmohr/activemq](https://hub.docker.com/r/rmohr/activemq/) Docker image (`5.15.9`). The ActiveMQ UI is reachable at [http://127.0.0.1:8161](http://127.0.0.1:8161) (`admin/admin`).

## Prerequisites

With CP 8.0+, connector version 12.2.0 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).

## How to run

```bash
playground run -f active-mq-source.sh
```

| Script | Description |
| --- | --- |
| `active-mq-source.sh` | Plaintext connection (`tcp://activemq:61616`), also checks that consumed messages are removed from the queue |
| `active-mq-source-mtls.sh` | SSL encryption + mutual TLS authentication (`ssl://activemq:61617`) |

## What the script does

1. (mTLS only) Generates keys and certificates for ActiveMQ and Connect with `security/certs-create.sh`.
2. Starts the environment with an `activemq` container.
3. Creates the ActiveMQ source connector (`io.confluent.connect.activemq.ActiveMQSourceConnector`) reading the JMS queue `DEV.QUEUE.1` into topic `MyKafkaTopicName`.
4. Sends a message to `DEV.QUEUE.1` with the ActiveMQ REST API (`curl -XPOST -u admin:admin -d "body=message" http://localhost:8161/api/message/DEV.QUEUE.1?type=queue`).
5. Verifies the message is received in `MyKafkaTopicName` with `playground topic consume`.
6. (`active-mq-source.sh` only) Stops the connector with `playground connector stop` and asserts that `DEV.QUEUE.1` is empty, i.e. the message was acknowledged and deleted (`commitRecord` API).

Example of record received:

```json
{
    "bytes": null,
    "correlationID": null,
    "deliveryMode": 2,
    "destination": {
        "io.confluent.connect.jms.Destination": {
            "destinationType": "queue",
            "name": "DEV.QUEUE.1"
        }
    },
    "expiration": 0,
    "map": null,
    "messageID": "ID:activemq-34421-1570550056457-4:2:1:1:1",
    "messageType": "text",
    "priority": 5,
    "properties": {},
    "redelivered": false,
    "replyTo": null,
    "text": {
        "string": "message"
    },
    "timestamp": 1570550394652,
    "type": null
}
```

## mTLS setup details

ActiveMQ is configured with (`activemq.xml`, mounted as `/opt/apache-activemq-5.15.9/conf/activemq.xml`):

```xml
<transportConnector name="ssl" uri="ssl://0.0.0.0:61617?trace=true&amp;needClientAuth=true" />
```

```xml
<sslContext>
    <sslContext keyStore="file:/tmp/kafka.activemq.keystore.jks" keyStorePassword="confluent" trustStore="file:/tmp/kafka.activemq.truststore.jks" trustStorePassword="confluent" />
</sslContext>
```

The Connect worker is configured with:

```yaml
      KAFKA_OPTS: "-Djavax.net.ssl.trustStore=/tmp/truststore.jks -Djavax.net.ssl.trustStorePassword=confluent -Djavax.net.ssl.keyStore=/tmp/keystore.jks -Djavax.net.ssl.keyStorePassword=confluent"
```

and the connector uses `"activemq.url": "ssl://activemq:61617"`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) sends messages to the destination of the connector with `BenchmarkJmsProducer` (`tools/benchmark-jms`), run in the `activemq` container with the `activemq-all` jar of the broker (transactions of 1000 messages), for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to consume a backlog of 1M messages
playground connector benchmark --nb-records 1000000

# same with one persistent send per message instead of transactions of 1000
playground connector benchmark --nb-records 100000 --shape small-txn

# throughput during 2 minutes while batches of 10000 messages are sent
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the messages are sent, then resumed, and the benchmark measures the time it takes to consume them. A topic (publish/subscribe) can only be measured with `--mode steady`: a paused subscriber does not keep the backlog in the broker.
