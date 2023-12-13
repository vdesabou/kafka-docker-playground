# JMS Software AG Universal Messaging Source Connector



## Objective

Quickly test [JMS Source - SAG Universal Messaging](https://docs.confluent.io/kafka-connect-jms-source/current/overview.html#features) connector.


## How to run

Simply run:

```
$ playground run -f jms-sag-um-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Create `QueueConnectionFactory` queue connection faftory in the SAG Universal Messaging Server 

```bash
$ docker exec umserver runUMTool.sh CreateConnectionFactory -rname=nsp://localhost:9000 -connectionurl=nsp://umserver:9000 -factoryname=QueueConnectionFactory -factorytype=queue

```

Create `test.queue` queue  in the SAG Universal Messaging Server 

```bash
$ docker exec umserver runUMTool.sh CreateJMSQueue -rname=nsp://localhost:9000 -queuename=test.queue

```

Publish messages to the SAG Universal Messaging queue

```bash
$ for i in 1000 1001 1002
do
   docker exec umserver runUMTool.sh JMSPublish  -rname=nsp://localhost:9000 -connectionfactory=QueueConnectionFactory -destination=test.queue -message=hello$i
done
```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "source-messages",
                    "java.naming.provider.url": "nsp://umserver:9000",
                    "java.naming.factory.initial": "com.pcbsys.nirvana.nSpace.NirvanaContextFactory",
                    "connection.factory.name": "QueueConnectionFactory",
                    "__java.naming.security.principal": "admin",
                    "__java.naming.security.credentials": "admin",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "test.queue",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-sag-um-source/config | jq .

```
Verify topic

```
playground topic consume --topic source-messages --min-expected-messages 3 --timeout 60
Struct{messageID=ID:172.20.0.2:34661:98195837288448:1,messageType=text,timestamp=1659664813908,deliveryMode=2,destination=Struct{destinationType=queue,name=test.queue},redelivered=false,expiration=0,priority=4,properties={},text=hello1000}
Struct{messageID=ID:172.20.0.2:37603:98204427223040:1,messageType=text,timestamp=1659664815508,deliveryMode=2,destination=Struct{destinationType=queue,name=test.queue},redelivered=false,expiration=0,priority=4,properties={},text=hello1001}
Struct{messageID=ID:172.20.0.2:47379:98213017157632:1,messageType=text,timestamp=1659664817508,deliveryMode=2,destination=Struct{destinationType=queue,name=test.queue},redelivered=false,expiration=0,priority=4,properties={},text=hello1002}
Processed a total of 3 messages
```

