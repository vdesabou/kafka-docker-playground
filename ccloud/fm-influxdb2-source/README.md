# Fully Managed InfluxDB 2 Source connector

## Objective

Quickly test the [Fully Managed InfluxDB 2 Source](https://docs.confluent.io/cloud/current/connectors/cc-influxdb2-source.html) connector.

A local InfluxDB 2 (`influxdb:2`) is exposed to Confluent Cloud with Ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Ngrok auth token (can also be passed as first argument) |

### Exposing the local container over the internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over the internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

An Ngrok auth token is necessary so that the fully managed connector can reach the local Docker container. Sign up at https://dashboard.ngrok.com/signup; your auth token is available on https://dashboard.ngrok.com/get-started/your-authtoken. The Ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-influxdb2-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-influxdb2-source.sh` | Reads InfluxDB 2 bucket `mybucket` into topic `influx_mybucket` (JSON) |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `influx_mybucket`.
2. Starts InfluxDB 2 (org `acme`) and Ngrok, then writes one point to bucket `mybucket` with the `influx` CLI.
3. Creates the `InfluxDB2Source` fully managed connector (`topic.prefix` `influx_`).
4. Verifies that at least one record is in `influx_mybucket` (`playground topic consume`).
5. Asks before deleting the connector.
