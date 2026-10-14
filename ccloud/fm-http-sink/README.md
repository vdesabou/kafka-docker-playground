# Fully Managed HTTP Sink connector

## Objective

Quickly test the [Fully Managed HTTP Sink](https://docs.confluent.io/cloud/current/connectors/cc-http-sink.html) connector.

A local HTTP server (from `connect/connect-http-sink`) is exposed to Confluent Cloud with Ngrok.

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
playground run -f fully-managed-http-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-http-sink.sh` | No authentication |
| `fully-managed-http-basic-auth.sh` | Basic authentication (`auth.type` BASIC) |
| `fully-managed-http-sink-oauth2.sh` | OAuth2 client credentials (`auth.type` OAUTH2) |
| `fully-managed-http-sink-mtls-auth.sh` | HTTPS with mutual TLS (keystore and truststore from `connect/connect-http-sink/security`) |

## What the script does

1. Bootstraps the Confluent Cloud environment and starts the HTTP server and Ngrok (`docker-compose.<variant>.yml`).
2. Recreates topic `http-topic` and produces 10 Avro records.
3. Creates the `HttpSink` fully managed connector pointing to the Ngrok URL, with the variant's authentication.
4. Verifies that 10 records land in the `success-<connector id>` topic (`playground topic consume`). The mTLS variant also reads the messages back from the HTTP server.
5. Asks before deleting the connector.
