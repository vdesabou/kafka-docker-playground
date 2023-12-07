# Capture Authentication logs

## Objective

Confluent Audit Logs does not (yet) capture authentication logs.
Authentication success/failures are collected as JMX bean however if you want to get further details like the incoming IP or userID the current solution is to rely on the logs

This example showcase how to capture the auhentication logs.

## How to run

```
$ playground run -f start-sasl.plain.sh
```

## Details of what the script is doing

Broker's `Selector` logger log level is configured to DEBUG
```
KAFKA_LOG4J_LOGGERS: "org.apache.kafka.common.network.Selector=DEBUG"
```

We first produce data with valid credentials
```
seq 10 | docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic test-topic --producer.config /tmp/good-credentials-client.properties
```

The `Selector` generate [DEBUG](https://github.com/apache/kafka/blob/trunk/clients/src/main/java/org/apache/kafka/common/network/Selector.java#L560) logs formatted like following:
```
[2023-05-05 16:05:09,254] DEBUG [SocketServer listenerType=ZK_BROKER, nodeId=1] Successfully authenticated with /127.0.0.1 (org.apache.kafka.common.network.Selector)
```

We can extract the incoming IP using a regex
```
docker logs broker | sed -rn 's/^.*SocketServer.*Successfully authent.*\/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*$/Authentication success from IP: \1/p'
```

Then, we try to produce records with invalid credenials
```
docker exec -i broker kafka-console-producer --bootstrap-server localhost:9092 --topic foo --producer.config /tmp/bad-credentials-client.properties
```

The `Selector` generate [INFO](https://github.com/apache/kafka/blob/trunk/clients/src/main/java/org/apache/kafka/common/network/Selector.java#L616) logs formatted like following:
```
[2023-05-05 16:05:09,254] INFO [SocketServer listenerType=ZK_BROKER, nodeId=1] Failed authentication with /127.0.0.1 (channelId=127.0.0.1:9098-127.0.0.1:33004-8) (userId=badmin, errorMessage=Authentication failed: Invalid username or password) (org.apache.kafka.common.network.Selector)
```

We can extract the incoming IP and user ID using a regex
```
docker logs broker | sed -rn 's/^.*SocketServer.*Failed authent.*\/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*userId=(.*),.*$/Authentication failed from IP: \1 with userId: \2/p'
```