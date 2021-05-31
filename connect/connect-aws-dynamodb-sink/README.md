# AWS DynamoDB Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-aws-dynamodb-sink/asciinema.gif?raw=true)

## Objective

Quickly test [AWS DynamoDB](https://docs.confluent.io/current/connect/kafka-connect-aws-dynamodb/index.html#kconnect-long-aws-dynamodb-sink-connector) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html#aws-credentials)

This project assumes `~/.aws/credentials` and `~/.aws/config` are set, see `docker-compose.yml`file for connect:

```yaml
    connect:
    <snip>
    volumes:
        - $HOME/.aws/credentials:$CONNECT_CONTAINER_HOME_DIR/.aws/credentials:ro
        - $HOME/.aws/config:$CONNECT_CONTAINER_HOME_DIR/.aws/config:ro
```

## How to run

Simply run:

```bash
$ ./dynamodb.sh
```


## Details of what the script is doing

Sending messages to topic topic1

```bash
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic topic1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Creating AWS DynamoDB Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.aws.dynamodb.DynamoDbSinkConnector",
                    "tasks.max": "1",
                    "topics": "topic1",
                    "aws.dynamodb.region": "'"$AWS_REGION"'",
                    "aws.dynamodb.endpoint": "'"$DYNAMODB_ENDPOINT"'",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/dynamodb-sink/config | jq .
```

Verify data is in DynamoDB

```bash
$ aws dynamodb scan --table-name topic1 --region $AWS_REGION
```

Results:

```json
{
    "Items": [
        {
            "f1": {
                "S": "value1"
            },
            "offset": {
                "N": "0"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value2"
            },
            "offset": {
                "N": "1"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value3"
            },
            "offset": {
                "N": "2"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value4"
            },
            "offset": {
                "N": "3"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value5"
            },
            "offset": {
                "N": "4"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value6"
            },
            "offset": {
                "N": "5"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value7"
            },
            "offset": {
                "N": "6"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value8"
            },
            "offset": {
                "N": "7"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value9"
            },
            "offset": {
                "N": "8"
            },
            "partition": {
                "N": "0"
            }
        },
        {
            "f1": {
                "S": "value10"
            },
            "offset": {
                "N": "9"
            },
            "partition": {
                "N": "0"
            }
        }
    ],
    "Count": 10,
    "ScannedCount": 10,
    "ConsumedCapacity": null
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
