# Tiered storage with AWS S3



## Objective

Quickly test [Tiered Storage](https://docs.confluent.io/current/kafka/tiered-storage-preview.html#tiered-storage).


## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials)

You can either export environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or set files `~/.aws/credentials` and `~/.aws/config`.

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
