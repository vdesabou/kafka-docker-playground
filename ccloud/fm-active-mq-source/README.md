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
