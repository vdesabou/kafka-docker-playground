# Fully Managed Solace Source connector

## Objective

Quickly test the [Solace Source](https://docs.confluent.io/cloud/current/connectors/cc-solace-source.html) fully managed connector, against a local Solace PubSub+ broker exposed through ngrok.

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
playground run -f fully-managed-solace-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-solace-source.sh` | Reads queue `connector-quickstart` into topic `from-solace-messages` |

## What the script does

1. Bootstraps the Confluent Cloud environment, starts Solace and ngrok locally and waits for Solace to start.
2. Recreates topic `from-solace-messages` with `message.timestamp.type=LogAppendTime`.
3. Creates queue `connector-quickstart` with the Solace CLI and publishes 3 messages through the Solace REST endpoint.
4. Creates the fully managed `SolaceSource` connector on queue `connector-quickstart`.
5. Verifies the 3 records with `playground topic consume --topic from-solace-messages`.
6. Checks with the SEMP monitoring API that the queue is empty, i.e. the messages were acknowledged and deleted after being committed to Kafka.
7. Asks whether to delete the connector.

In CI, the example is skipped (exit code 111) with the `cfk` environment.
