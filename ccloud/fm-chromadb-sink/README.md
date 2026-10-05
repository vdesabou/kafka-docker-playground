# Fully Managed ChromaDB Sink connector



## Objective

Quickly test [Fully Managed ChromaDB Sink](https://docs.confluent.io/cloud/current/connectors/cc-chromadb-sink.html) connector with a self-hosted ChromaDB running in Docker.

The script:

* starts a ChromaDB container (`chromadb/chroma`) and exposes it over internet using [Ngrok](https://ngrok.com)
* produces 10 Avro records with the fields expected by the connector: `id`, `document`, `embedding` (pre-computed, same dimension for all records) and `metadata`
* creates the connector with tenant `default_tenant`, database `default_database` and collection `playground-collection` (auto-created by the connector)
* verifies that the collection contains 10 records

Note: self-hosted ChromaDB 1.x has no server-side authentication, so `chromadb.api.key` (required by the connector and sent as `X-Chroma-Token` header) is set to a dummy value. With Chroma Cloud, use `https://api.trychroma.com:8000` as endpoint, together with your API key, tenant and database.

## How to run

```
$ just use <playground run> command and search for fully-managed-chromadb-sink.sh in this folder
```

## Exposing docker container over internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on a AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using EC2 Security Group.

An [Ngrok](https://ngrok.com) auth token is necessary in order to expose the Docker Container port to internet, so that fully managed connector can reach it.

You can sign up at https://dashboard.ngrok.com/signup
If you have already signed up, make sure your auth token is setup by exporting environment variable `NGROK_AUTH_TOKEN`

Your auth token is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken

Ngrok web interface available at http://localhost:4040

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)
