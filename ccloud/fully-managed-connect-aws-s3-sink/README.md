# Fully Managed S3 Sink connector

## Objective

Quickly test [Fully Managed S3 Sink](https://docs.confluent.io/cloud/current/connectors/cc-s3-sink.html) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/current/connect/kafka-connect-kinesis/quickstart.html#aws-credentials)

This project assumes `~/.aws/credentials` and `~/.aws/config` are set.

## Prerequisites

* Properly initialized Confluent Cloud CLI

You must be already logged in with confluent CLI which needs to be setup with correct environment, cluster and api key to use:

Typical commands to run:

```bash
$ confluent login --save

Use environment $ENVIRONMENT_ID:
$ confluent environment use $ENVIRONMENT_ID

Use cluster $CLUSTER_ID:
$ confluent kafka cluster use $CLUSTER_ID

Store api key $API_KEY:
$ confluent api-key store $API_KEY $API_SECRET --resource $CLUSTER_ID --force

Use api key $API_KEY:
$ confluent api-key use $API_KEY --resource $CLUSTER_ID
```

* Create a file `$HOME/.confluent/config`

You should have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";

// Schema Registry specific settings
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR_API_KEY>:<SR_API_SECRET>
schema.registry.url=<SR ENDPOINT>

// license
confluent.license=<YOUR LICENSE>

// ccloud login password
ccloud.user=<ccloud login>
ccloud.password=<ccloud password>
```

## How to run

Simply run:

```
$ ./fully-managed-s3-sink.sh
```

## Details of what the script is doing

Creating bucket name <$AWS_BUCKET_NAME>, if required

```bash
$ aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
```


Creating S3 Sink connector

```bash
cat << EOF > connector.json
{
     "connector.class": "S3_SINK",
     "name": "S3_SINK",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "topics": "s3_topic",
     "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
     "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
     "input.data.format": "AVRO",
     "output.data.format": "AVRO",
     "s3.bucket.name": "$AWS_BUCKET_NAME",
     "time.interval" : "HOURLY",
     "flush.size": "1000",
     "schema.compatibility": "NONE",
     "tasks.max" : "1"
}
EOF

create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300
```

Messages are sent to `s3_topic` topic using:

```
$ seq -f "{\"f1\": \"value%g\"}" 1500 | docker run -i --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}  kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

After a few seconds, S3 should contain files in bucket:

```
$ aws s3api list-objects --bucket "$AWS_BUCKET_NAME"
```

Results:

```json
{
    "Contents": [
        {
            "Key": "topics/s3_topic/year=2022/month=03/day=04/hour=15/s3_topic+0+0000000000.avro",
            "LastModified": "2022-03-04T15:46:12+00:00",
            "ETag": "\"abd39afbf2c331fa741843cf0116831a-1\"",
            "Size": 9042,
            "StorageClass": "STANDARD",
            "Owner": {
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        },
        {
            "Key": "topics/s3_topic/year=2022/month=03/day=04/hour=15/s3_topic+0+0000001000.avro",
            "LastModified": "2022-03-04T15:46:12+00:00",
            "ETag": "\"4a39ebeaad481e5270e9e655802df86f-1\"",
            "Size": 9541,
            "StorageClass": "STANDARD",
            "Owner": {
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        },
        {
            "Key": "topics/s3_topic/year=2022/month=03/day=04/hour=15/s3_topic+0+0000002000.avro",
            "LastModified": "2022-03-04T15:46:13+00:00",
            "ETag": "\"9d935f212c2bf53b76b35daf642a830a-1\"",
            "Size": 9650,
            "StorageClass": "STANDARD",
            "Owner": {
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        },
        {
            "Key": "topics/s3_topic/year=2022/month=03/day=04/hour=15/s3_topic+0+0000003000.avro",
            "LastModified": "2022-03-04T15:46:13+00:00",
            "ETag": "\"f0dc3fd7cf1594820e29e9e800e77433-1\"",
            "Size": 9042,
            "StorageClass": "STANDARD",
            "Owner": {
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        },
        {
            "Key": "topics/s3_topic/year=2022/month=03/day=04/hour=15/s3_topic+0+0000004000.avro",
            "LastModified": "2022-03-04T15:46:13+00:00",
            "ETag": "\"000d3806b7a7be359d69561d35ecfab1-1\"",
            "Size": 9541,
            "StorageClass": "STANDARD",
            "Owner": {
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        },
        {
            "Key": "topics/s3_topic/year=2022/month=03/day=04/hour=15/s3_topic+0+0000005000.avro",
            "LastModified": "2022-03-04T15:46:13+00:00",
            "ETag": "\"23529ce886f016be0814777c33cf3015-1\"",
            "Size": 9650,
            "StorageClass": "STANDARD",
            "Owner": {
                "ID": "9185230836bd0b811896b3dc97974c8cb986dbcbf58ed554d6e9e6412a237e60"
            }
        }
    ]
}
```