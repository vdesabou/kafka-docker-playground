# Fully Managed ChromaDB Sink connector

## Objective

Quickly test the [Fully Managed ChromaDB Sink](https://docs.confluent.io/cloud/current/connectors/cc-chromadb-sink.html) connector with a self-hosted ChromaDB running in Docker.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose ChromaDB to the internet so that the fully managed connector can reach it ([sign up](https://dashboard.ngrok.com/signup), [get your token](https://dashboard.ngrok.com/get-started/your-authtoken)) |

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

The Ngrok web interface is available at http://localhost:4040.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fully-managed-chromadb-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-chromadb-sink.sh` | Avro records with pre-computed embeddings written to a self-hosted ChromaDB collection |

## What the script does

1. Starts a ChromaDB container (`chromadb/chroma`) and ngrok locally, and checks the ChromaDB health endpoint.
2. Produces 10 Avro records to topic `chromadb-topic` with the fields expected by the connector: `id`, `document`, `embedding` (pre-computed, same dimension for all records) and `metadata`.
3. Creates the fully managed `ChromaDBSink` connector with tenant `default_tenant`, database `default_database` and collection `playground-collection` (auto-created by the connector).
4. Shows the connector lag and verifies through the ChromaDB API that the collection contains 10 records.
5. Deletes the connector at the end of the run.

## Notes

Self-hosted ChromaDB 1.x has no server-side authentication, so `chromadb.api.key` (required by the connector and sent as `X-Chroma-Token` header) is set to a dummy value. With Chroma Cloud, use `https://api.trychroma.com:8000` as endpoint, together with your API key, tenant and database.
