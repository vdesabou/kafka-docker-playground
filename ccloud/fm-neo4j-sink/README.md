# Fully Managed Neo4j Sink connector

## Objective

Quickly test the [Neo4j Sink](https://docs.confluent.io/cloud/current/connectors/cc-neo4j-sink/cc-neo4j-sink.html) fully managed connector, against a local Neo4j exposed through ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | [ngrok](https://ngrok.com) auth token, used to expose the local container to the fully managed connector. Sign up at https://dashboard.ngrok.com/signup, the token is on https://dashboard.ngrok.com/get-started/your-authtoken |

## Exposing Docker containers over the internet

> [!WARNING]
> Running this example on your personal machine exposes a TCP port to the internet through [ngrok](https://ngrok.com), which is a security risk. Prefer an AWS EC2 instance, and allow only the [Confluent Cloud static egress IP addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (public endpoints on AWS only) in the EC2 security group.

Example to open port 7687 to the Confluent static egress IP addresses:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq -r '.Reservations[] | .Instances[] | .SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 7687 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 7687 --cidr 13.36.88.89/32
# etc. for every static egress IP address of your region
```

The ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-neo4j-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-neo4j-sink.sh` | Basic authentication, unencrypted `neo4j://` connection, Cypher strategy |

## What the script does

1. Bootstraps the Confluent Cloud environment and deletes topic `users`.
2. Starts Neo4j and ngrok locally.
3. Produces 10000 Avro records to topic `users` (datagen `users` schema, string keys).
4. Creates the fully managed `Neo4jSink` connector with a `neo4j.cypher.topic.map` that `MERGE`s one `User` node per record.
5. Verifies the nodes with `cypher-shell` (`MATCH (n) RETURN n;`). When not running in CI, it also opens the Neo4j browser at http://localhost:7474.
6. Asks whether to delete the connector.
