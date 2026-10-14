# Fully Managed Solace Sink connector

## Objective

Quickly test the [Solace Sink](https://docs.confluent.io/cloud/current/connectors/cc-solace-sink.html) fully managed connector, against a local Solace PubSub+ broker exposed through ngrok.

Solace UI is available at http://127.0.0.1:8080 (`admin`/`admin`).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | [ngrok](https://ngrok.com) auth token, used to expose the local container to the fully managed connector. Sign up at https://dashboard.ngrok.com/signup, the token is on https://dashboard.ngrok.com/get-started/your-authtoken |

## Exposing Docker containers over the internet

> [!WARNING]
> Running this example on your personal machine exposes a TCP port to the internet through [ngrok](https://ngrok.com), which is a security risk. Prefer an AWS EC2 instance, and allow only the [Confluent Cloud static egress IP addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (public endpoints on AWS only) in the EC2 security group.

Example to open port 55555 to the Confluent static egress IP addresses:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq -r '.Reservations[] | .Instances[] | .SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 55555 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 55555 --cidr 13.36.88.89/32
# etc. for every static egress IP address of your region
```

The ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-solace-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-solace-sink.sh` | String messages to queue `connector-quickstart` (dynamic durables) |

## What the script does

1. Bootstraps the Confluent Cloud environment, starts Solace and ngrok locally and waits for Solace to start.
2. Recreates topic `solace-topic` (3 partitions) and produces 10 string messages.
3. Creates the fully managed `SolaceSink` connector writing to queue `connector-quickstart` (`solace.dynamic.durables=true`).
4. Verifies with the Solace CLI (`show_queue_cmd`) that the queue holds 10 messages.
5. Asks whether to delete the connector.

In CI, the example is skipped (exit code 111) with the `cfk` environment.
