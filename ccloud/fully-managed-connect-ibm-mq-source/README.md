# Fully Managed IBM MQ Source connector

## Objective

Quickly test [IBM MQ Source](https://docs.confluent.io/cloud/current/connectors/cc-ibmmq-source.html#) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

## Ngrok auth token

An [Ngrok](https://ngrok.com) auth token is necessary in order to expose the Docker Container port to internet, so that fully managed connector can reach it.

You can sign up at https://dashboard.ngrok.com/signup
If you have already signed up, make sure your auth token is setup by exporting environment variable `NGROK_AUTH_TOKEN`

Your auth token is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken

Ngrok web interface available at http://localhost:4551

## Prerequisites

* Properly initialized Confluent Cloud CLI

You must be already logged in with confluent CLI which needs to be setup with correct environment, cluster and api key to use:

Typical commands to run:

```bash
$ confluent login --save

Use environment $ENVIRONMENT_ID:
$ confluent environment use $ENVIRONMENT_ID

Use cluster $CLUSTER_ID:
$ confluent kafka cluster use $CLUSTER_ID

Store api key $API_KEY:
$ confluent api-key store $API_KEY $API_SECRET --resource $CLUSTER_ID --force

Use api key $API_KEY:
$ confluent api-key use $API_KEY --resource $CLUSTER_ID
```

* Create a file `$HOME/.confluent/config`

You should have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";

// Schema Registry specific settings
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR_API_KEY>:<SR_API_SECRET>
schema.registry.url=<SR ENDPOINT>

// license
confluent.license=<YOUR LICENSE>

// ccloud login password
ccloud.user=<ccloud login>
ccloud.password=<ccloud password>
```


## How to run

```
$ ./fully-managed-ibm-mq-source.sh <NGROK_AUTH_TOKEN>
```

Note: you can also export the value as environment variable


