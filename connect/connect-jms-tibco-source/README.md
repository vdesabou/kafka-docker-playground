# JMS TIBCO Source connector

## Objective

Quickly test [JMS TIBCO Source](https://docs.confluent.io/current/connect/kafka-connect-jms/index.html#using-with-tibco-ems) connector.

Using TIBCO Docker [image](https://github.com/mikeschippers/docker-tibco)

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)

* Download [TIBCO EMS Community Edition](https://www.tibco.com/resources/product-download/tibco-enterprise-message-service-community-edition--free-download) and put `TIB_ems-ce_8.5.1_linux_x86_64.zip`into `docker-file`directory

## How to run

Simply run:

```
$ ./jms-tibco.sh
```

## Details of what the script is doing

The queue `connector-quickstart` is not created using `tibemsadmin` as described in [Quick Start](https://docs.confluent.io/current/connect/kafka-connect-tibco/source/index.html#quick-start) because the `TIBCO Enterprise Message Service™ - Community Edition` does not contain it.

The queues are created by providing `./docker-tibco/queues.conf`file in `/home/tibusr`directory.

This file contains:

```
>
sample

queue.sample

connector-quickstart
```

The ConnectionFactory is created by providing `./docker-tibco/factories.conf`file in `/home/tibusr`directory.

This file contains:

```
[ConnectionFactory]
  type                  = generic
  url                   = tcp://7222
```

Sending EMS messages m1 m2 m3 m4 m5 in queue connector-quickstart

```bash
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgProducer -user admin -queue connector-quickstart m1 m2 m3 m4 m5'
```

The connector is created with:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "from-tibco-messages",
                    "java.naming.factory.initial": "com.tibco.tibjms.naming.TibjmsInitialContextFactory",
                    "java.naming.provider.url": "tibjmsnaming://tibco-ems:7222",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-tibco-source/config | jq .
```


Verify we have received the data in `from-tibco-messages` topic:

```bash
$ docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic from-tibco-messages --from-beginning --max-messages 2
```

Results:

```
Struct
{
    messageID=ID:E4EMS-SERVER.15DA9975B3:1,
    messageType=text,
    timestamp=1571395609724,
    deliveryMode=2,
    destination=
    Struct
    {
        destinationType=queue,name=connector-quickstart
    }
    ,redelivered=false,
    expiration=0,
    priority=4,
    properties=
    {
        JMSXDeliveryCount=Struct
        {
            propertyType=integer,integer=1
        }
    },
    text=m1
}
Processed a total of 2 messages
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])

## Credits

[mikeschippers/docker-tibco](https://github.com/mikeschippers/docker-tibco)
