# GCS Source connector



## Objective

Quickly test [GCS Source](https://docs.confluent.io/current/connect/kafka-connect-gcs/source/index.html#quick-start) connector.

* Active Google Cloud Platform (GCP) account with authorization to create resources

## Prepare a Bucket

[Instructions](https://docs.confluent.io/current/connect/kafka-connect-gcs/index.html#prepare-a-bucket)

* Create `Service Account` from IAM & Admin console:

Set `Service account name`:

![Service Account setup](Screenshot1.png)

Choose permission `Storage Admin` (probably not required to have all of them):

![Service Account setup](Screenshot2.png)

Create Key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json`and place it in `./keyfile.json` or use environment variable `GCP_KEYFILE_CONTENT` with content generated with `GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`


## How to run

For [Backup and Restore GCS Source](https://docs.confluent.io/kafka-connect-gcs-source/current/backup-and-restore/overview.html):

```bash
$ playground run -f gcs-source-backup-and-restore<tab> <GCP_PROJECT>
```

For [Generalized GCS Source](https://docs.confluent.io/kafka-connect-gcs-source/current/generalized/overview.html) (it requires version 2.1.0 at minimum):

```bash
$ playground run -f gcs-source-generalized<tab> <GCP_PROJECT>
```

Note: you can also export these values as environment variable

## Details of what the script is doing

### Backup and Restore GCS Source

Steps from [connect-gcp-gcs-sink](../connect/connect-gcp-gcs-sink/README.md)

Creating GCS Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSourceConnector",
                    "gcs.bucket.name" : "$GCS_BUCKET_NAME",
                    "gcs.credentials.path" : "/tmp/keyfile.json",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "tasks.max" : "1",
                    "confluent.topic.bootstrap.servers" : "broker:9092",
                    "confluent.topic.replication.factor" : "1",
                    "transforms" : "AddPrefix",
                    "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.AddPrefix.regex" : ".*",
                    "transforms.AddPrefix.replacement" : "copy_of_$0"
          }' \
     http://localhost:8083/connectors/GCSSourceConnector/config | jq .
```

Verify messages are in topic `copy_of_gcs_topic`

```bash
playground topic consume --topic copy_of_gcs_topic --min-expected-messages 9 --timeout 60
```

Results:

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
{"f1":"value4"}
{"f1":"value5"}
{"f1":"value6"}
{"f1":"value7"}
{"f1":"value8"}
{"f1":"value9"}
```

### Generalized GCS S3 Source

Copy generalized.quickstart.json to bucket $GCS_BUCKET_NAME/quickstart:

```bash
$ docker run -i -v ${PWD}:/tmp/ --volumes-from gcloud-config google/cloud-sdk:latest gsutil cp /tmp/generalized.quickstart.json gs://$GCS_BUCKET_NAME/quickstart/generalized.quickstart.json
```

Creating Generalized GCS Source connector:

```bash
playground connector create-or-update --connector gcs-source << EOF
{
               "connector.class": "io.confluent.connect.gcs.GcsSourceConnector",
               "gcs.bucket.name" : "$GCS_BUCKET_NAME",
               "gcs.credentials.path" : "/tmp/keyfile.json",
               "format.class": "io.confluent.connect.gcs.format.json.JsonFormat",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "mode": "GENERIC",
               "topic.regex.list": "quick-start-topic:.*",
               "tasks.max" : "1",
               "confluent.topic.bootstrap.servers" : "broker:9092",
               "confluent.topic.replication.factor" : "1"
          }
EOF
```

Verifying topic `quick-start-topic`:

```bash
playground topic consume --topic quick-start-topic --min-expected-messages 9 --timeout 60
```

Results:

```json
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
{"f1":"value4"}
{"f1":"value5"}
{"f1":"value6"}
{"f1":"value7"}
{"f1":"value8"}
{"f1":"value9"}
Processed a total of 9 messages
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])

