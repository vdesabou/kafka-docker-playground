# Fully Managed GCP firestore Sink connector



## Objective

Quickly test [Fully Managed GCP firestore Sink](https://docs.confluent.io/cloud/current/connectors/cc-gcp-firestore-sink.html) connector.

* Active Google Cloud Platform (GCP) account with authorization to create resources

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)


Add permissions to service account as per [here](https://docs.cloud.google.com/firestore/mongodb-compatibility/docs/create-databases#permissions)

You also need to add "Project IAM Admin" role to the service account to be able to setup Firestore user.

## How to run

Simply run:

```bash
just use <playground run> command
```