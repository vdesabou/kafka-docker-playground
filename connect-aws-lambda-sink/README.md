# AWS Lambda Sink connector

## Objective

Quickly test [AWS Lambda](https://docs.confluent.io/current/connect/kafka-connect-aws-lambda/index.html#kconnect-long-lambda-sink-connector) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* `aws cli`(example `brew install awscli`)

## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html#aws-credentials)

This project assumes `~/.aws/credentials` and `~/.aws/config` are set, see `docker-compose.yml`file for connect:

```yaml
    connect:
    <snip>
    volumes:
        - $HOME/.aws/credentials:/root/.aws/credentials:ro
        - $HOME/.aws/config:/root/.aws/config:ro
```

## How to run

Simply run:

```bash
$ ./lambda.sh
```


## Details of what the script is doing


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
