# ActiveMQ Source connector



## Objective

Quickly test [ActiveMQ Source](https://docs.confluent.io/current/connect/kafka-connect-activemq/index.html#kconnect-long-activemq-source-connector) connector.

Using ActiveMQ Docker [image](https://hub.docker.com/r/rmohr/activemq/)

## How to run

Simply run:

```
$ playground run -f active-mq-source<tab>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f active-mq-source-mtls<tab>
```

## Details of what the script is doing

ActiveMQ UI is reachable at [http://127.0.0.1:8161](http://127.0.0.1:8161]) (`admin/admin`)

### Without SSL

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.activemq.ActiveMQSourceConnector",
                    "kafka.topic": "MyKafkaTopicName",
                    "activemq.url": "tcp://activemq:61616",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/active-mq-source/config | jq .
```

Messages are sent to IBM MQ using curl:

```bash
$ curl -XPOST -u admin:admin -d "body=message" http://localhost:8161/api/message/DEV.QUEUE.1?type=queue
```

Verify we have received the data in MyKafkaTopicName topic:

```bash
playground topic consume --topic MyKafkaTopicName --expected-messages 1
```

We get:

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

### With SSL encryption + Mutual TLS auth

Active QM is set with (file `/opt/apache-activemq-5.15.9/conf/activemq.xml`):

```xml
<transportConnector name="ssl" uri="ssl://0.0.0.0:61617?trace=true&amp;needClientAuth=true" />
```

and

```xml
    <sslContext>
        <sslContext keyStore="file:/tmp/kafka.activemq.keystore.jks" keyStorePassword="confluent" trustStore="file:/tmp/kafka.activemq.truststore.jks" trustStorePassword="confluent" />
    </sslContext>
```

Connect is set with:

```yml
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/truststore.jks
                  -Djavax.net.ssl.trustStorePassword=confluent
                  -Djavax.net.ssl.keyStore=/tmp/keystore.jks
                  -Djavax.net.ssl.keyStorePassword=confluent
```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.activemq.ActiveMQSourceConnector",
               "kafka.topic": "MyKafkaTopicName",
               "activemq.url": "ssl://activemq:61617",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/active-mq-source-mtls/config | jq .
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
