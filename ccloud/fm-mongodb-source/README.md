# Fully Managed MongoDB Source connector

## Objective

Quickly test the [MongoDB Atlas Source](https://docs.confluent.io/cloud/current/connectors/cc-mongo-db-source.html) fully managed connector with `mongodb.instance.type=MONGODB_SELF_MANAGED`, against a local MongoDB exposed through ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | [ngrok](https://ngrok.com) auth token, used to expose the local container to the fully managed connector. Sign up at https://dashboard.ngrok.com/signup, the token is on https://dashboard.ngrok.com/get-started/your-authtoken |

## Exposing Docker containers over the internet

> [!WARNING]
> Running this example on your personal machine exposes a TCP port to the internet through [ngrok](https://ngrok.com), which is a security risk. Prefer an AWS EC2 instance, and allow only the [Confluent Cloud static egress IP addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (public endpoints on AWS only) in the EC2 security group.

Example to open port 27017 to the Confluent static egress IP addresses:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq -r '.Reservations[] | .Instances[] | .SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 27017 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 27017 --cidr 13.36.88.89/32
# etc. for every static egress IP address of your region
```

The ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-mongodb-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-mongodb-source.sh` | Self-managed MongoDB replica set, JSON output, `startup.mode=copy_existing` |

## What the script does

1. Bootstraps the Confluent Cloud environment and (re)creates topic `mongo.inventory.customers`.
2. Starts MongoDB and ngrok locally, initializes the replica set and creates user `myuser`.
3. Creates the fully managed `MongoDbAtlasSource` connector on database `inventory`, collection `customers`.
4. Inserts a document into `inventory.customers`.
5. Verifies the record with `playground topic consume --topic mongo.inventory.customers`.
6. Asks whether to delete the connector.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-mongodb-source`](../../connect/connect-mongodb-source/README.md#benchmark): it loads documents in the collection of the connector for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to read a backlog of 100k records
playground connector benchmark --nb-records 100000
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
