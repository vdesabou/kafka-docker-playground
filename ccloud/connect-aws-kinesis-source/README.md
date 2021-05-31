# AWS Kinesis Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-aws-kinesis-source/asciinema.gif?raw=true)

## Objective

Quickly test [Kinesis Connector](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#quick-start) connector with Confluent Cloud.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/index.html#aws-credentials)

This project assumes `~/.aws/credentials` is set, see `docker-compose.yml`file for connect:

```
    connect:
    <snip>
    volumes:
        - $HOME/.aws/credentials:$CONNECT_CONTAINER_HOME_DIR/.aws/credentials:ro
```

## How to run

Simply run:

```
$ ./kinesis.sh
```

## Details of what the script is doing

Create a Kinesis stream `my_kinesis_stream` in `us-east-1` region as it is default:

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
               "kinesis.region": "EU_WEST_3",
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
$ docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic kinesis_topic --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 1'
```

Delete your stream and clean up resources to avoid incurring any unintended charges:

```
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
