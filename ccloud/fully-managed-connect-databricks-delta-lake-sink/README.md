# Fully Managed Databricks Delta Lake Sink connector


## Objective

Quickly test [Databricks Delta Lake Sink](https://docs.confluent.io/cloud/current/connectors/cc-databricks-delta-lake-sink/cc-databricks-delta-lake-sink.html) connector.

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

## Databricks Setup

Follow all steps from [here](https://docs.confluent.io/kafka-connect-databricks-delta-lake-sink/current/databricks-aws-setup.html#set-up-databricks-delta-lake-aws)

## How to run

Simply run:

```
$ just use <playground run> command and search for fully-managed-databricks-delta-lake-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <DATABRICKS_AWS_BUCKET_NAME> <DATABRICKS_AWS_BUCKET_REGION> <DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID> <DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY> <DATABRICKS_SERVER_HOSTNAME> <DATABRICKS_HTTP_PATH> .sh in this folder
```

Note: you can also export these values as environment variable
