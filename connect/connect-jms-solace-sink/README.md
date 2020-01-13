# JMS Solace Sink connector

## Objective

Quickly test [Solace Sink](https://docs.confluent.io/current/connect/kafka-connect-jms/sink/index.html#solace-quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./jms-solace-sink.sh
```

Solace UI is available at [127.0.0.1:8080](http://127.0.0.1:8080) `admin/admin`

## Details of what the script is doing

Create `connector-quickstart` queue in the default Message VPN using CLI

```bash
$ docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/create_queue_cmd"
```

With create_queue_cmd script:

```
home
enable
configure
message-spool message-vpn "default"
! pragma:interpreter:ignore-already-exists
  create queue "connector-quickstart" primary
! pragma:interpreter:no-ignore-already-exists
    access-type "exclusive"
    permission all "delete"
    no shutdown
    exit
  exit
```

Sending messages to topic `sink-messages`

```bash
$ seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages
```

The connector is created with:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
                    "tasks.max": "1",
                    "topics": "sink-messages",
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
     http://localhost:8083/connectors/jms-solace-sink/config | jq_docker_cli .
```

Confirm the messages were delivered to the `connector-quickstart` queue in the `default` Message VPN using CLI:


```bash
$ docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/show_queue_cmd"
```

The solace commands executed in script `show_queue_cmd`are:

```
enable
show
queue connector-quickstart
```

Output is:

```bash
Solace PubSub+ Standard Version 9.1.0.77

The Solace PubSub+ Standard is proprietary software of
Solace Corporation. By accessing the Solace PubSub+ Standard
you are agreeing to the license terms and conditions located at
http://www.solace.com/license-software

Copyright 2004-2019 Solace Corporation. All rights reserved.

To purchase product support, please contact Solace at:
https://solace.com/contact-us/

Operating Mode: Message Routing Node


solace> enable

solace# show

solace(show)> queue connector-quickstart

Flags Legend:
I - Ingress Admin State (U=Up, D=Down)
E - Egress  Admin State (U=Up, D=Down)
A - Access-Type         (E=Exclusive, N=Non-Exclusive)
S - Selector            (Y=Yes, N=No)
R - Redundancy          (P=Primary, B=Backup)
D - Durability          (D=Durable, N=Non-Durable)
P - Priority            (Y=Yes, N=No)

Queue Name                   Messages      Spool             Bind Status
Message VPN                   Spooled  Usage(MB)   HWM (MB) Count I E A S R D P
------------------------- ----------- ---------- ---------- ----- -------------
connector-quickstart
default                            10       0.00       0.00     0 U U E N P D N
```

Note: this could also be verified manually using [Solace UI](http://127.0.0.1:8080)

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
