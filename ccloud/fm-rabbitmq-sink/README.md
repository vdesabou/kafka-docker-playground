# Fully Managed RabbitMQ Sink connector

## Objective

Quickly test the [RabbitMQ Sink](https://docs.confluent.io/cloud/current/connectors/cc-rabbitmq-sink.html) fully managed connector, against a local RabbitMQ exposed through ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | [ngrok](https://ngrok.com) auth token, used to expose the local container to the fully managed connector. Sign up at https://dashboard.ngrok.com/signup, the token is on https://dashboard.ngrok.com/get-started/your-authtoken |

## Exposing Docker containers over the internet

> [!WARNING]
> Running this example on your personal machine exposes a TCP port to the internet through [ngrok](https://ngrok.com), which is a security risk. Prefer an AWS EC2 instance, and allow only the [Confluent Cloud static egress IP addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (public endpoints on AWS only) in the EC2 security group.

Example to open port 5672 to the Confluent static egress IP addresses:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq -r '.Reservations[] | .Instances[] | .SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 5672 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 5672 --cidr 13.36.88.89/32
# etc. for every static egress IP address of your region
```

The ngrok web interface is available at http://localhost:4040.

For the SSL variant, the exposed port is `5671`.

## How to run

```bash
playground run -f fully-managed-rabbitmq-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-rabbitmq-sink.sh` | Plain AMQP connection (port 5672) |
| `fully-managed-rabbitmq-sink-ssl.sh` | SSL connection (port 5671), keystore and truststore generated with `playground tools certs-create` |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `rabbitmq-messages`.
2. Starts RabbitMQ and ngrok locally (the SSL variant first generates certificates in `security/`).
3. Declares exchange `exchange1`, queue `queue1` and a binding with routing key `rkey1` using `rabbitmqadmin`.
4. Produces 10 messages to topic `rabbitmq-messages`.
5. Creates the fully managed `RabbitMQSink` connector publishing to `exchange1` with routing key `rkey1`.
6. Verifies the messages landed in `queue1` with `rabbitmqadmin get`.
7. Asks whether to delete the connector.
