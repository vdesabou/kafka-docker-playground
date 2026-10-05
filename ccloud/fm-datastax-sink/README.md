# Fully Managed DataStax Sink connector



## Objective

Quickly test [Fully Managed DataStax Sink](https://docs.confluent.io/cloud/current/connectors/cc-datastax-sink.html) connector with a self-hosted Apache Cassandra running in Docker.

The script:

* starts an Apache Cassandra 4.1 container with username/password authentication enabled (`cassandra`/`cassandra`) and exposes port 9042 over internet using [Ngrok](https://ngrok.com)
* creates keyspace `ks` and table `ks.orders` (the connector does not create keyspaces or tables)
* produces 10 Avro records to topic `orders`
* creates the connector with `deployment.type` `Apache Cassandra or DSE` and `mapping.map` `{"orders.ks.orders":"id=value.id, product=value.product, quantity=value.quantity, price=value.price"}`
* verifies that table `ks.orders` contains 10 rows

To use DataStax Astra instead, set `deployment.type` to `DataStax Astra`, `cloud.secureConnectBundle` to the base64-encoded secure connect bundle (prefixed with `data:application/octet-stream;base64,`), `auth.username` to `token` and `auth.password` to your Astra application token.

## How to run

```
$ just use <playground run> command and search for fully-managed-datastax-sink.sh in this folder
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
