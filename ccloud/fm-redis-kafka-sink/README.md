# Fully Managed Redis Kafka Sink connector

## Objective

Quickly test the [Redis Kafka Sink](https://docs.confluent.io/cloud/current/connectors/cc-redis-kafka-db-sink.html) fully managed connector, against a local Redis exposed through ngrok.

Redis Insight UI is available at http://localhost:5540.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | [ngrok](https://ngrok.com) auth token, used to expose the local container to the fully managed connector. Sign up at https://dashboard.ngrok.com/signup, the token is on https://dashboard.ngrok.com/get-started/your-authtoken |

## Exposing Docker containers over the internet

> [!WARNING]
> Running this example on your personal machine exposes a TCP port to the internet through [ngrok](https://ngrok.com), which is a security risk. Prefer an AWS EC2 instance, and allow only the [Confluent Cloud static egress IP addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (public endpoints on AWS only) in the EC2 security group.

Example to open port 6379 to the Confluent static egress IP addresses:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq -r '.Reservations[] | .Instances[] | .SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 6379 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 6379 --cidr 13.36.88.89/32
# etc. for every static egress IP address of your region
```

The ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-redis-kafka-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-redis-kafka-sink.sh` | Standalone Redis, Avro values and string keys |

## What the script does

1. Bootstraps the Confluent Cloud environment and deletes topic `redis_users`.
2. Starts Redis, Redis Insight and ngrok locally.
3. Produces 3 Avro records with key `key1` to topic `redis_users`.
4. Creates the fully managed `RedisKafkaSink` connector (`redis.server.mode=Standalone`).
5. Checks Redis with `redis-cli`.
6. Asks whether to delete the connector.
