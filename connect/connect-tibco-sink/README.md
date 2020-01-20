# TIBCO Sink connector

## Objective

Quickly test [TIBCO Sink](https://docs.confluent.io/current/connect/kafka-connect-tibco/sink/index.html#quick-start) connector.

Using TIBCO Docker [image](https://github.com/mikeschippers/docker-tibco)

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)

* Download [TIBCO EMS Community Edition](https://www.tibco.com/resources/product-download/tibco-enterprise-message-service-community-edition--free-download) and put `TIB_ems-ce_8.5.1_linux_x86_64.zip`into `docker-file`directory

## How to run

Simply run:

```
$ ./tibco-ems-sink.sh
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
$ docker exec connect \
     curl -X PUT \
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
     http://localhost:8083/connectors/tibco-ems-sink/config | jq_docker_cli .
```

Sending messages to topic `sink-messages`:

```bash
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages
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

Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:1} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:1} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:2} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:2} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:3} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:3} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:4} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:4} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:5} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:5} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:6} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:6} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:7} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:7} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:8} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:8} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:9} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:9} }
Received message:  Header={ JMSMessageID={ID:E4EMS-SERVER.15DA88A7B4:10} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Oct 17 15:37:24 UTC 2019} JMSDeliveryTime={Thu Oct 17 15:37:24 UTC 2019} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} msg_num={Integer:10} }
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])

## Credits

[mikeschippers/docker-tibco](https://github.com/mikeschippers/docker-tibco)
