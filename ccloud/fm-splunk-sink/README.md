# Fully Managed Splunk Sink connector

## Objective

Quickly test the [Splunk Sink](https://docs.confluent.io/cloud/current/connectors/cc-splunk-sink.html) fully managed connector, against a local Splunk HTTP Event Collector exposed through ngrok.

Splunk UI is available at http://127.0.0.1:8000 (`admin`/`password`).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | [ngrok](https://ngrok.com) auth token, used to expose the local container to the fully managed connector. Sign up at https://dashboard.ngrok.com/signup, the token is on https://dashboard.ngrok.com/get-started/your-authtoken |

## Exposing Docker containers over the internet

> [!WARNING]
> Running this example on your personal machine exposes a TCP port to the internet through [ngrok](https://ngrok.com), which is a security risk. Prefer an AWS EC2 instance, and allow only the [Confluent Cloud static egress IP addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (public endpoints on AWS only) in the EC2 security group.

Example to open port 8088 to the Confluent static egress IP addresses:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq -r '.Reservations[] | .Instances[] | .SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 8088 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 8088 --cidr 13.36.88.89/32
# etc. for every static egress IP address of your region
```

The ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-splunk-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-splunk-sink.sh` | String messages sent to HEC, index `main` |

## What the script does

1. Bootstraps the Confluent Cloud environment, starts Splunk and ngrok locally, and recreates topic `splunk-qs` (3 partitions).
2. Waits for Splunk to be started.
3. Creates the fully managed `SplunkSink` connector pointing to the HEC endpoint exposed by ngrok (index `main`, sourcetype `my_sourcetype`).
4. Produces 3 string messages to topic `splunk-qs`.
5. Verifies the events with a `splunk search` in the container.
6. Asks whether to delete the connector.
