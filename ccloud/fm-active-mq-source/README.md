# Fully Managed ActiveMQ Source connector

## Objective

Quickly test the [Fully Managed ActiveMQ Source](https://docs.confluent.io/cloud/current/connectors/cc-activemq-source.html) connector.

ActiveMQ runs locally (Docker [image](https://hub.docker.com/r/rmohr/activemq/)) and is exposed to the fully managed connector through an ngrok TCP tunnel.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | ngrok auth token ([sign up](https://dashboard.ngrok.com/signup), token available [here](https://dashboard.ngrok.com/get-started/your-authtoken)) |

> [!WARNING]
> The local ActiveMQ broker is exposed on the internet through ngrok. The script asks for confirmation before continuing.

## How to run

```bash
export NGROK_AUTH_TOKEN="<your ngrok token>"
playground run -f fully-managed-active-mq-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-active-mq-source.sh` | ActiveMQ Source connector reading queue `DEV.QUEUE.1` |

## What the script does

1. Bootstraps the Confluent Cloud environment and deletes topic `MyKafkaTopicName`.
2. Starts ActiveMQ and ngrok locally, and gets the public ngrok TCP endpoint.
3. Creates the fully managed connector `ActiveMQSource_<USER>` (Avro output) and waits for it to be running.
4. Sends a message to the JMS queue `DEV.QUEUE.1` through the ActiveMQ REST API.
5. Verifies that topic `MyKafkaTopicName` contains the message with `playground topic consume`.
6. Asks for confirmation before deleting the connector.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-active-mq-source`](../../connect/connect-active-mq-source/README.md#benchmark): it loads messages in the ActiveMQ queue for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to read a backlog of 100k records
playground connector benchmark --nb-records 100000
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
