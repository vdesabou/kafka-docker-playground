# JMS Software AG Universal Messaging Sink Connector



## Objective

Quickly test [JMS Sink - SAG Universal Messaging](https://docs.confluent.io/kafka-connect-jms-sink/current/overview.html#features) connector.




## How to run

Simply run:

```
$ playground run -f jms-sag-um-sink<tab>
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

Publish messages to the Solace queue using the REST endpoint

```bash
$ seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages

```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
                    "tasks.max": "1",
                    "topics": "sink-messages",
                    "java.naming.provider.url": "nsp://umserver:9000",
                    "java.naming.factory.initial": "com.pcbsys.nirvana.nSpace.NirvanaContextFactory",
                    "connection.factory.name": "QueueConnectionFactory",
                    "java.naming.security.principal": "admin",
                    "java.naming.security.credentials": "admin",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "test-queue",
                    "nirvana.useJMSEngine": "true",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-sag-um-sink/config | jq .
```
Verify the messages in the topic 

```
$ docker exec -it umserver timeout 30 runUMTool.sh JMSSubscribe -rname=nsp://localhost:9000 -connectionfactory=QueueConnectionFactory -destination=test-queue 
We have initialised JMSSubscribe with: {rname=nsp://localhost:9000, destination=test-queue, connectionfactory=QueueConnectionFactory}
Now receiving messages... press enter to exit
JMS MSG ID : ID:172.22.0.6:36341:116724326203392:1
JMS DELIVERY MODE : 2
JMS TIME STAMP : 1659665628137
JMS PROPERTIES :
----------------------------------------------------------------
----------------------------------------------------------------
JMS MSG ID : ID:172.22.0.6:36341:116724326203392:2
JMS DELIVERY MODE : 2
JMS TIME STAMP : 1659665628158
JMS PROPERTIES :
----------------------------------------------------------------
----------------------------------------------------------------
JMS MSG ID : ID:172.22.0.6:36341:116724326203392:3
JMS DELIVERY MODE : 2
JMS TIME STAMP : 1659665628158
JMS PROPERTIES :
----------------------------------------------------------------
----------------------------------------------------------------
JMS MSG ID : ID:172.22.0.6:36341:116724326203392:4
JMS DELIVERY MODE : 2
JMS TIME STAMP : 1659665628158
JMS PROPERTIES :
----------------------------------------------------------------
----------------------------------------------------------------
JMS MSG ID : ID:172.22.0.6:36341:116724326203392:5
JMS DELIVERY MODE : 2
JMS TIME STAMP : 1659665628158
JMS PROPERTIES :
----------------------------------------------------------------
....
```

