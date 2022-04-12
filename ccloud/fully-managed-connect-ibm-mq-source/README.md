# Fully Managed IBM MQ Source connector

## Objective

Quickly test [IBM MQ Source](https://docs.confluent.io/cloud/current/connectors/cc-ibmmq-source.html#) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

## Exposing docker container over internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on a AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using EC2 Security Group.

An [Ngrok](https://ngrok.com) auth token is necessary in order to expose the Docker Container port to internet, so that fully managed connector can reach it.

You can sign up at https://dashboard.ngrok.com/signup
If you have already signed up, make sure your auth token is setup by exporting environment variable `NGROK_AUTH_TOKEN`

Your auth token is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken

Ngrok web interface available at http://localhost:4551

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider` (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2)
* `CLUSTER_CREDS`: The API_KEY:API_KEY_SECRET to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set new ones will be used): The Schema Registry API_KEY:API_KEY_SECRET to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)


## How to run

```
$ ./fully-managed-ibm-mq-source.sh <NGROK_AUTH_TOKEN>
```

Note: you can also export the value as environment variable


