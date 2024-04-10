# Fully Managed AWS Kinesis Source connector



## Objective

Quickly test [Fully Managed Kinesis Connector](https://docs.confluent.io/cloud/current/connectors/cc-kinesis-source.html) connector.

## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#aws-credentials)

You can either export environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or set files `~/.aws/credentials` and `~/.aws/config`.

Example:

```
[default]
aws_access_key_id=xxx
aws_secret_access_key=xxx
region=eu-west-3
```

Make sure that region corresponds to the one used by the test (eu-west-3 by default), otherwise the connector will fail to start with `Stream does not exist`.

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)


## How to run

Simply run:

```
$ just use <playground run> 
```

