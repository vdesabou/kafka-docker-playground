# AMPS Source connector



## Objective

Quickly test [AMPS Source](https://docs.confluent.io/current/connect/kafka-connect-amps/index.html#quick-start) connector.

## Prerequisites

Create an account [here](https://www.crankuptheamps.com/developer) and download `AMPS Server v5.x.x / Linux (64 bit)`, then rename it to `AMPS.tar.gz` and put it into `docker-amps` directory

![Download](Screenshot1.png)

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900).

## How to run

Simply run:

```
$ playground run -f amps-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Use the spark utility to quickly publish few records to the Orders topic

```bash
$ docker exec -i amps /AMPS/bin/spark publish -server localhost:9007 -topic Orders -type json << EOF
{"id": 1, "order": "Apples"}
{"id": 2, "order": "Oranges"}
EOF
```

Creating AMPS source connector:

```bash
playground connector create-or-update --connector amps-source  << EOF
{
               "connector.class": "io.confluent.connect.amps.AmpsSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "AMPS_Orders",
               "amps.servers": "tcp://amps:9007",
               "amps.topic": "Orders",
               "amps.topic.type": "sow",
               "amps.command": "sow_and_subscribe",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF
```


Verify we have received the data in `AMPS_Orders` topic

```bash
playground topic consume --topic AMPS_Orders --min-expected-messages 2 --timeout 60
```

Results:

```json
8{"id": 1, "order": "Apples"}
:{"id": 2, "order": "Oranges"}
Processed a total of 2 messages
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
