# JMS Solace Source connector

## Objective

Quickly test the [JMS Source](https://docs.confluent.io/kafka-connectors/jms-source/current/overview.html) connector with a Solace PubSub+ broker.

## Prerequisites

With CP 8.x, the minimum supported connector version is 12.2.0 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-solace-source.sh
```

Solace UI is available at [127.0.0.1:8080](http://127.0.0.1:8080) (`admin`/`admin`).

## What the script does

1. Downloads `sol-jms-10.6.4.jar` and `commons-lang-2.6.jar` and copies them into the `confluentinc-kafka-connect-jms` plugin `lib` folder.
2. Starts the environment with a Solace PubSub+ container and waits for it to be ready.
3. Creates queue `connector-quickstart` in the `default` Message VPN with the Solace CLI script [`create_queue_cmd`](create_queue_cmd).
4. Creates topic `source-messages` with `message.timestamp.type=LogAppendTime` (otherwise records get `CreateTime:0`).
5. Publishes 3 messages to the queue through the Solace REST endpoint (`http://localhost:9000/Queue/connector-quickstart`).
6. Creates the JMS source connector `jms-solace-source` (`com.solacesystems.jndi.SolJNDIInitialContextFactory`, `smf://solace:55555`, connection factory `/jms/cf/default`).
7. Verifies that topic `source-messages` receives 3 messages with `playground topic consume`.
8. Asserts, with the Solace SEMP v2 monitoring API, that queue `connector-quickstart` is empty, i.e. messages were acknowledged and deleted after being committed.

Example of record:

```text
Struct{messageID=1000,messageType=text,timestamp=0,deliveryMode=2,destination=Struct{destinationType=queue,name=connector-quickstart},redelivered=false,expiration=0,priority=0,properties={JMS_Solace_isXML=Struct{propertyType=boolean,boolean=false}, JMS_Solace_DeliverToOne=Struct{propertyType=boolean,boolean=false}, JMS_Solace_DeadMsgQueueEligible=Struct{propertyType=boolean,boolean=false}, JMS_Solace_ElidingEligible=Struct{propertyType=boolean,boolean=false}, Solace_JMS_Prop_IS_Reply_Message=Struct{propertyType=boolean,boolean=false}, JMS_Solace_HTTPContentType=Struct{propertyType=string,string=text/plain}, JMSXDeliveryCount=Struct{propertyType=integer,integer=1}},text=m1}
```

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) sends messages to the destination of the connector through the REST messaging port of the broker (`curl`, keep-alive, 16 parallel transfers), for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to consume a backlog of 1M messages
playground connector benchmark --nb-records 1000000

# throughput during 2 minutes while batches of 10000 messages are sent
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the messages are sent, then resumed, and the benchmark measures the time it takes to consume them. A topic (publish/subscribe) can only be measured with `--mode steady`: a paused subscriber does not keep the backlog in the broker.
