# Fully Managed S3 Sink connector

## Objective

Quickly test [Fully Managed S3 Sink](https://docs.confluent.io/cloud/current/connectors/cc-s3-sink.html) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials)

This project assumes `~/.aws/credentials` and `~/.aws/config` are set.

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

## How to run

Simply run:

```
$ just use <playground run> command and search for fully-managed-s3-sink.sh in this folder
```
