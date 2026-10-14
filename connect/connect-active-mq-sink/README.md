# ActiveMQ Sink connector

## Objective

Quickly test the [ActiveMQ Sink](https://docs.confluent.io/kafka-connectors/activemq-sink/current/overview.html) connector.

ActiveMQ runs with the [rmohr/activemq](https://hub.docker.com/r/rmohr/activemq/) Docker image (`5.15.9`). The ActiveMQ UI is reachable at [http://127.0.0.1:8161](http://127.0.0.1:8161) (`admin/admin`).

## Prerequisites

With CP 8.0+, connector version 2.1.16 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).

## How to run

```bash
playground run -f active-mq-sink.sh
```

| Script | Description |
| --- | --- |
| `active-mq-sink.sh` | Plaintext connection (`tcp://activemq:61616`) |
| `active-mq-sink-mtls.sh` | SSL encryption + mutual TLS authentication (`ssl://activemq:61617`) |

## What the script does

1. (mTLS only) Generates keys and certificates for ActiveMQ and Connect with `security/certs-create.sh`.
2. Starts the environment with an `activemq` container.
3. Produces one message (`This is my message`) to topic `sink-messages` with `playground topic produce`.
4. Creates the ActiveMQ sink connector (`io.confluent.connect.jms.ActiveMqSinkConnector`) writing to the JMS queue `DEV.QUEUE.1`.
5. Reads the message from `DEV.QUEUE.1` with the ActiveMQ REST API (`http://localhost:8161/api/message/DEV.QUEUE.1?type=queue`) and verifies its content.

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
