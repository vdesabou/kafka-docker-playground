# JMS Solace Sink connector



## Objective

Quickly test [JMS Source - Solace](https://docs.confluent.io/kafka-connect-jms-source/current/overview.html#features) connector.




## How to run

Simply run:

```
$ playground run -f jms-solace-source<tab>
```

Solace UI is available at [127.0.0.1:8080](http://127.0.0.1:8080) `admin/admin`

## Details of what the script is doing

Create `connector-quickstart` queue in the default Message VPN using CLI

```bash
$ docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/create_queue_cmd"
```

With create_queue_cmd script:

```
enable
configure
message-spool message-vpn default
create queue connector-quickstart
permission all consume
no shutdown full
```


Publish messages to the Solace queue using the REST endpoint

```bash
$ for i in 1000 1001 1002
do
     curl -X POST -d "m1" http://localhost:9000/Queue/connector-quickstart -H "Content-Type: text/plain" -H "Solace-Message-ID: $i"
done
```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
                    "tasks.max": "1",
                    "topics": "source-messages",
                    "java.naming.factory.initial": "com.solacesystems.jndi.SolJNDIInitialContextFactory",
                    "java.naming.provider.url": "smf://solace:55555",
                    "java.naming.security.principal": "admin",
                    "java.naming.security.credentials": "admin",
                    "connection.factory.name": "/jms/cf/default",
                    "Solace_JMS_VPN": "default",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-solace-source/config | jq .
```
Verify topic

```
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic source-messages --from-beginning --max-messages 2
Struct{messageID=1000,messageType=text,timestamp=0,deliveryMode=2,destination=Struct{destinationType=queue,name=connector-quickstart},redelivered=false,expiration=0,priority=0,properties={JMS_Solace_isXML=Struct{propertyType=boolean,boolean=false}, JMS_Solace_DeliverToOne=Struct{propertyType=boolean,boolean=false}, JMS_Solace_DeadMsgQueueEligible=Struct{propertyType=boolean,boolean=false}, JMS_Solace_ElidingEligible=Struct{propertyType=boolean,boolean=false}, Solace_JMS_Prop_IS_Reply_Message=Struct{propertyType=boolean,boolean=false}, JMS_Solace_HTTPContentType=Struct{propertyType=string,string=text/plain}, JMSXDeliveryCount=Struct{propertyType=integer,integer=1}},text=m1}
Struct{messageID=1001,messageType=text,timestamp=0,deliveryMode=2,destination=Struct{destinationType=queue,name=connector-quickstart},redelivered=false,expiration=0,priority=0,properties={JMS_Solace_isXML=Struct{propertyType=boolean,boolean=false}, JMS_Solace_DeliverToOne=Struct{propertyType=boolean,boolean=false}, JMS_Solace_DeadMsgQueueEligible=Struct{propertyType=boolean,boolean=false}, JMS_Solace_ElidingEligible=Struct{propertyType=boolean,boolean=false}, Solace_JMS_Prop_IS_Reply_Message=Struct{propertyType=boolean,boolean=false}, JMS_Solace_HTTPContentType=Struct{propertyType=string,string=text/plain}, JMSXDeliveryCount=Struct{propertyType=integer,integer=1}},text=m1}
Processed a total of 2 messages
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
