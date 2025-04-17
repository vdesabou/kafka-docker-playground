# TIBCO Sink connector



## Objective

Quickly test [TIBCO Sink](https://docs.confluent.io/current/connect/kafka-connect-tibco/sink/index.html#quick-start) connector.

Using TIBCO Docker [image](https://github.com/mikeschippers/docker-tibco)

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900).

* Download [TIBCO EMS Community Edition](https://www.tibco.com/resources/product-download/tibco-enterprise-message-service-community-edition--free-download) and put `TIB_ems-ce_8.5.1_linux_x86_64.zip`into `docker-file`directory

## How to run

Simply run:

```
$ just use <playground run> command and search for tibco-ems-sink.sh in this folder
```

## Details of what the script is doing

The queue `connector-quickstart` is not created using `tibemsadmin` as described in [Quick Start](https://docs.confluent.io/current/connect/kafka-connect-tibco/source/index.html#quick-start) because the `TIBCO Enterprise Message Service™ - Community Edition` does not contain it.

The queues is created by providing `./docker-tibco/queues.conf`file in `/home/tibusr`directory.

This file contains:

```
>
sample

queue.sample

connector-quickstart
```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.TibcoSinkConnector",
                    "tasks.max": "1",
                    "topics": "sink-messages",
                    "tibco.url": "tcp://tibco-ems:7222",
                    "tibco.username": "admin",
                    "tibco.password": "",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/tibco-ems-sink/config | jq .
```

Sending messages to topic `sink-messages`:

```bash
seq 10 | docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic sink-messages
```

Verify we have received the data in `connector-quickstart` EMS queue:

```bash
$ docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgConsumer -user admin -queue connector-quickstart -nbmessages 10'
```

Results:

```
------------------------------------------------------------------------
tibjmsMsgConsumer SAMPLE
------------------------------------------------------------------------
Server....................... localhost
User......................... admin
Destination.................. connector-quickstart
------------------------------------------------------------------------

Subscribing to destination: connector-quickstart

Received message: TextMessage={ Header={ JMSMessageID={ID:E4EMS-SERVER.16093EDB43:9} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu May 06 13:23:46 UTC 2021} JMSDeliveryTime={Thu May 06 13:23:46 UTC 2021} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} } Text={9} }
Received message: TextMessage={ Header={ JMSMessageID={ID:E4EMS-SERVER.16093EDB43:10} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu May 06 13:23:46 UTC 2021} JMSDeliveryTime={Thu May 06 13:23:46 UTC 2021} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} } Text={10} }
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])

## Credits

[mikeschippers/docker-tibco](https://github.com/mikeschippers/docker-tibco)
