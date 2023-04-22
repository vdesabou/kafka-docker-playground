# Fully Managed S3 Sink connector

## Objective

Quickly test [Fully Managed S3 Sink](https://docs.confluent.io/cloud/current/connectors/cc-s3-sink.html) connector.



## AWS Setup

* Make sure you have an [AWS account](https://docs.aws.amazon.com/streams/latest/dev/before-you-begin.html#setting-up-sign-up-for-aws).
* Set up [AWS Credentials](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html#aws-credentials)

This project assumes `~/.aws/credentials` and `~/.aws/config` are set.

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

## How to run

Simply run:

```
$ playground run -f fully-managed-s3-sink<tab>
```

## Details of what the script is doing

Creating bucket name <$AWS_BUCKET_NAME>, if required

```bash
$ if [ "$AWS_REGION" == "us-east-1" ]
then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
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
$ seq -f "{\"f1\": \"value%g\"}" 1500 | docker run -i --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG}  kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
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