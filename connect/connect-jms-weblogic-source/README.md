# Oracle Weblogic JMS Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-jms-weblogic-source/asciinema.gif?raw=true)

## Objective

Quickly test [Oracle Weblogic JMS Source](https://docs.confluent.io/kafka-connect-weblogic-source/current/index.html) connector.

Using Oracle WebLogic Server (Developer Tier, version `12.2.1.3`) Docker [image](https://hub.docker.com/_/oracle-weblogic-server-12c). You need to register to get the image.

## How to run

Simply run:

```
$ ./jms-weblogic-queue.sh
```

or

```
$ ./jms-weblogic-topic.sh
```

N.B: Weblogic console is reachable at [http://127.0.0.1:7001/console](http://127.0.0.1:7001/console]) (`weblogic`/`welcome1`)

## Details of what the script is doing

### Queue example

Creating JMS weblogic source connector

```bash
$ curl -X PUT \
     -H "Conten```
     t-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.weblogic.WeblogicSourceConnector",
               "kafka.topic": "from-weblogic-messages",
               "java.naming.factory.initial": "weblogic.jndi.WLInitialContextFactory",
               "jms.destination.name": "myJMSServer/mySystemModule!myJMSServer@MyDistributedQueue",
               "jms.destination.type": "QUEUE",
               "java.naming.provider.url": "t3://weblogic-jms:7001",
               "connection.factory.name": "myFactory",
               "java.naming.security.principal": "weblogic",
               "java.naming.security.credentials": "welcome1",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "tasks.max" : "1",
               "batch.size": "1",
               "max.pending.messages": "1",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-weblogic-queue-source/config | jq .
```

Sending one message in JMS queue myQueue

```bash
$ docker exec jms-sender bash -c 'java -cp "/tmp/weblogic.jar:/tmp/wlthint3client.jar:/jms-sender-1.0.0.jar" com.sample.jms.toolkit.JMSSender'
```

Verify we have received the data in `from-weblogic-messages` topic

```bash
$ docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic from-weblogic-messages --from-beginning --max-messages 1
```

Results:

```
Struct{messageID=ID:<576249.1618314788338.0>,messageType=text,timestamp=1618314788338,deliveryMode=2,destination=Struct{destinationType=queue,name=mySystemModule!myJMSServer@MyDistributedQueue},redelivered=false,expiration=0,priority=4,properties={JMS_BEA_DeliveryTime=Struct{propertyType=long,long=1618314788338}, JMSXDeliveryCount=Struct{propertyType=integer,integer=1}},text=Hello Queue World!}
```

### Topic example

Creating JMS weblogic source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.weblogic.WeblogicSourceConnector",
               "kafka.topic": "from-weblogic-messages",
               "java.naming.factory.initial": "weblogic.jndi.WLInitialContextFactory",
               "jms.destination.name": "myJMSServer/mySystemModule!myJMSServer@MyDistributedTopic",
               "jms.destination.type": "TOPIC",
               "java.naming.provider.url": "t3://weblogic-jms:7001",
               "connection.factory.name": "myFactory",
               "java.naming.security.principal": "weblogic",
               "java.naming.security.credentials": "welcome1",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "tasks.max" : "1",
               "batch.size": "1",
               "max.pending.messages": "1",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-weblogic-topic-source/config | jq .
```

Sending one message in JMS topic myTopic

```bash
$ docker exec jms-sender bash -c 'java -cp "/tmp/weblogic.jar:/tmp/wlthint3client.jar:/jms-sender-1.0.0.jar" com.sample.jms.toolkit.JMSSender'
```

Verify we have received the data in `from-weblogic-messages` topic

```bash
$ docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic from-weblogic-messages --from-beginning --max-messages 1
```

Results:

```
Struct{messageID=ID:<366463.1618317131446.0>,messageType=text,timestamp=1618317131446,deliveryMode=2,destination=Struct{destinationType=topic,name=mySystemModule!myJMSServer@MyDistributedTopic},redelivered=false,expiration=0,priority=4,properties={JMS_BEA_DeliveryTime=Struct{propertyType=long,long=1618317131446}, JMSXDeliveryCount=Struct{propertyType=integer,integer=1}},text=Hello Topic World!}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])

