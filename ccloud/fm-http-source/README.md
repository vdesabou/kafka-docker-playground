# Fully Managed HTTP Source connector

## Objective

Quickly test the [Fully Managed HTTP Source](https://docs.confluent.io/cloud/current/connectors/cc-http-source.html) connector.

A local HTTP server is exposed to Confluent Cloud with Ngrok.

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
playground run -f fully-managed-http-source-simple-incrementing.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-http-source-simple-incrementing.sh` | `SIMPLE_INCREMENTING` offset mode, one record per page from `/wiki/rest/api/space` |
| `fully-managed-http-source-cursor-pagination.sh` | `CURSOR_PAGINATION` offset mode (`/storage/v1/b/test-bucket/o`, 15 records across 3 pages) |
| `fully-managed-http-source-chaining-offset.sh` | `CHAINING` offset mode (POST search on `/test-index/_search`) |
| `fully-managed-http-source-oauth2.sh` | OAuth2 client credentials, `SIMPLE_INCREMENTING` offset mode |

## What the script does

1. Bootstraps the Confluent Cloud environment and starts the HTTP server and Ngrok.
2. Recreates the target topic (`http-topic-<entity>` or `http-topic`).
3. Creates the `HttpSource` fully managed connector pointing to the Ngrok URL, with the variant's offset mode.
4. For the OAuth2 variant, gets a token from the local server and posts a message to `/api/messages`.
5. Verifies that the expected number of records is in the topic (`playground topic consume`).
6. Asks before deleting the connector.
