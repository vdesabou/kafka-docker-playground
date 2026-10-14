# Fully Managed Elasticsearch v2 Sink connector

## Objective

Quickly test the [Fully Managed Elasticsearch v2 Sink](https://docs.confluent.io/cloud/current/connectors/cc-elasticsearch-sink-v2/cc-elasticsearch-sink-v2.html) connector with a self-hosted Elasticsearch 9 running in Docker.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose Elasticsearch to the internet so that the fully managed connector can reach it ([sign up](https://dashboard.ngrok.com/signup), [get your token](https://dashboard.ngrok.com/get-started/your-authtoken)) |

### Exposing docker container over internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

Example to set an EC2 Security Group with Confluent Static Egress IP Addresses and port 9200:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 9200 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 9200 --cidr 13.36.88.89/32
# etc...
```

The Ngrok web interface is available at http://localhost:4040.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fully-managed-elasticsearch-v2-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-elasticsearch-v2-sink.sh` | Avro records indexed into a local Elasticsearch 9.3 with security disabled (`auth.type` `NONE`, `elastic.server.version` `V9`) |

## What the script does

1. Creates topic `test-elasticsearch-sink`.
2. Starts Elasticsearch (xpack security disabled) and ngrok locally (`docker-compose.yml`).
3. Creates the fully managed `ElasticsearchSinkV2` connector with `connection.url` pointing to the ngrok endpoint.
4. Produces 10 Avro records with `playground topic produce`.
5. Searches index `test-elasticsearch-sink` and checks that `value1` and `value10` are present.
6. Deletes the connector at the end of the run.
