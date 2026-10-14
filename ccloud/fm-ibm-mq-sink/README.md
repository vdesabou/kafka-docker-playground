# Fully Managed IBM MQ Sink connector

## Objective

Quickly test the [Fully Managed IBM MQ Sink](https://docs.confluent.io/cloud/current/connectors/cc-ibm-mq-sink.html) connector.

Uses the IBM MQ Docker image `icr.io/ibm-messaging/mq`, exposed to Confluent Cloud with Ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Ngrok auth token (can also be passed as first argument) |

### Exposing the local container over the internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over the internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

An Ngrok auth token is necessary so that the fully managed connector can reach the local Docker container. Sign up at https://dashboard.ngrok.com/signup; your auth token is available on https://dashboard.ngrok.com/get-started/your-authtoken. The Ngrok web interface is available at http://localhost:4040.

Example to allow the Confluent Static Egress IP Addresses on port 1414 in an EC2 Security Group:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1414 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1414 --cidr 13.36.88.89/32
# etc...
```

## How to run

```bash
playground run -f fully-managed-ibm-mq-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-ibm-mq-sink.sh` | Plain connection with user/password |
| `fully-managed-ibm-mq-sink-ssl.sh` | TLS (truststore generated with `playground tools certs-create`) |
| `fully-managed-ibm-mq-sink-mtls.sh` | Mutual TLS (`SSLCAUTH(REQUIRED)` on the channel, keystore and truststore, no user/password) |
| `fully-managed-ibm-mq-sink-eos.sh` | Exactly once semantics (`exactly.once.enabled`), using exclusive offsets queue `KAFKA.OFFSETS.QUEUE` |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `sink-messages`.
2. Starts IBM MQ (queue manager `QM1`) and Ngrok; for TLS variants, generates certificates first and configures the `DEV.APP.SVRCONN` channel.
3. For the EOS variant, creates the offsets queue `KAFKA.OFFSETS.QUEUE` with `DEFSOPT(EXCL)` and grants access to user `app`.
4. Produces one string message to `sink-messages`.
5. Creates the `IbmMqSink` fully managed connector writing to queue `DEV.QUEUE.1`.
6. Browses `DEV.QUEUE.1` with `amqsbcg` and checks that the message is there.
7. Asks before deleting the connector.
