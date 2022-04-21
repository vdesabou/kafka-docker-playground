# Databricks Delta Lake Sink connector


## Objective

Quickly test [Databricks Delta Lake Sink](https://docs.confluent.io/kafka-connect-databricks-delta-lake-sink/current/overview.html) connector.


## Databricks Setup

Follow all steps from [here](https://docs.confluent.io/kafka-connect-databricks-delta-lake-sink/current/databricks-aws-setup.html#set-up-databricks-delta-lake-aws)

## How to run

Simply run:

```
$ ./databricks-delta-lake-sink.sh <DATABRICKS_AWS_BUCKET_NAME> <DATABRICKS_AWS_BUCKET_REGION> <DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID> <DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY> <DATABRICKS_SERVER_HOSTNAME> <DATABRICKS_HTTP_PATH> <DATABRICKS_TOKEN> 
```

Note: you can also export these values as environment variable

## Details of what the script is doing



N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
