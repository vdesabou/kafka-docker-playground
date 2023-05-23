# AWS Kinesis Source connector



## Objective

Quickly test [Kinesis Connector](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#quick-start) connector with Confluent Cloud.

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)


## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#aws-credentials)

You can either export environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or set files `~/.aws/credentials` and `~/.aws/config`.

## How to run

Simply run:

```
$ playground run -f kinesis<tab>
```

## Details of what the script is doing

Create a Kinesis stream `kafka_docker_playground`:

```
$ aws kinesis create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1
```

Insert records in Kinesis stream:

```
$ aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1
```

The connector is created with:

```
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.stream": "'"$KINESIS_STREAM_NAME"'",
               "confluent.license": "",
               "name": "kinesis-source",
               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3"
          }' \
     http://localhost:8083/connectors/kinesis-source/config | jq .
```

Verify we have received the data in kinesis_topic topic:

```
playground topic consume --topic kinesis_topic --min-expected-messages 1
```

Delete your stream and clean up resources to avoid incurring any unintended charges:

```
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
