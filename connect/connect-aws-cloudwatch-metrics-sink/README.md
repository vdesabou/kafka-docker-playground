# AWS CloudWatch Metrics Sink connector



## Objective

Quickly test [AWS CloudWatch Metrics](https://docs.confluent.io/current/connect/kafka-connect-aws-cloudwatch-metrics/index.html#quick-start) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials)

You can either export environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or set files `~/.aws/credentials` and `~/.aws/config`.

## How to run

Simply run:

```bash
$ just use <playground run> command and search for cloudwatch-metrics-sink.sh in this folder
```


## Details of what the script is doing

Sending messages to topic cloudwatch-metrics-topic

```bash
$ docker exec -i connect kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic cloudwatch-metrics-topic --property parse.key=true --property key.separator=, --property key.schema='{"type":"string"}' --property value.schema='{"name": "myMetric","type": "record","fields": [{"name": "name","type": "string"},{"name": "type","type": "string"},{"name": "timestamp","type": "long"},{"name": "dimensions","type": {"name": "dimensions","type": "record","fields": [{"name": "dimensions1","type": "string"},{"name": "dimensions2","type": "string"}]}},{"name": "values","type": {"name": "values","type": "record","fields": [{"name":"count", "type": "double"},{"name":"oneMinuteRate", "type": "double"},{"name":"fiveMinuteRate", "type": "double"},{"name":"fifteenMinuteRate", "type": "double"},{"name":"meanRate", "type": "double"}]}}]}' << EOF
"key1", {"name" : "test_meter","type" : "meter", "timestamp" : $TIMESTAMP, "dimensions" : {"dimensions1" : "InstanceID","dimensions2" : "i-aaba32d4"},"values" : {"count" : 32423.0,"oneMinuteRate" : 342342.2,"fiveMinuteRate" : 34234.2,"fifteenMinuteRate" : 2123123.1,"meanRate" : 2312312.1}}
EOF
```

Creating AWS CloudWatch metrics Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "topics": "cloudwatch-metrics-topic",
               "connector.class": "io.confluent.connect.aws.cloudwatch.metrics.AwsCloudWatchMetricsSinkConnector",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "aws.cloudwatch.metrics.url": "$CLOUDWATCH_METRICS_URL",
               "aws.cloudwatch.metrics.namespace": "service-namespace",
               "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
               "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
               "behavior.on.malformed.metric": "FAIL",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-cloudwatch-metrics-sink/config | jq .
```

View the metrics being produced to Amazon CloudWatch

```bash
$ aws cloudwatch list-metrics --namespace service-namespace
```

Results:

```json
{
    "Metrics": [
        {
            "Namespace": "service-namespace",
            "MetricName": "test_meter_count",
            "Dimensions": [
                {
                    "Name": "dimensions2",
                    "Value": "i-aaba32d4"
                },
                {
                    "Name": "dimensions1",
                    "Value": "InstanceID"
                }
            ]
        },
        {
            "Namespace": "service-namespace",
            "MetricName": "test_meter_oneMinuteRate",
            "Dimensions": [
                {
                    "Name": "dimensions2",
                    "Value": "i-aaba32d4"
                },
                {
                    "Name": "dimensions1",
                    "Value": "InstanceID"
                }
            ]
        },
        {
            "Namespace": "service-namespace",
            "MetricName": "test_meter_fiveMinuteRate",
            "Dimensions": [
                {
                    "Name": "dimensions2",
                    "Value": "i-aaba32d4"
                },
                {
                    "Name": "dimensions1",
                    "Value": "InstanceID"
                }
            ]
        },
        {
            "Namespace": "service-namespace",
            "MetricName": "test_meter_fifteenMinuteRate",
            "Dimensions": [
                {
                    "Name": "dimensions2",
                    "Value": "i-aaba32d4"
                },
                {
                    "Name": "dimensions1",
                    "Value": "InstanceID"
                }
            ]
        },
        {
            "Namespace": "service-namespace",
            "MetricName": "test_meter_meanRate",
            "Dimensions": [
                {
                    "Name": "dimensions2",
                    "Value": "i-aaba32d4"
                },
                {
                    "Name": "dimensions1",
                    "Value": "InstanceID"
                }
            ]
        }
    ]
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
