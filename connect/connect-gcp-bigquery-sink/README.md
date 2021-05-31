# GCP BigQuery Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-gcp-bigquery-sink/asciinema.gif?raw=true)

## Objective

Quickly test [GCP BigQuery Sink](https://docs.confluent.io/current/connect/kafka-connect-bigquery/index.html#kconnect-long-gcp-bigquery-sink-connector) connector.

* Active Google Cloud Platform (GCP) account with authorization to create resources

## GCP BigQuery Setup

* Follow [Quickstart using the web UI in the GCP Console](https://cloud.google.com/bigquery/docs/quickstarts/quickstart-web-ui) to get familiar with GCP BigQuery
* Create `Service Account` from IAM & Admin console:

Set `Service account name`:

![Service Account setup](Screenshot1.png)


Choose permission `BigQuery`->`BigQuery Admin`:

![Service Account setup](Screenshot2.png)

Create Key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json`and place it in `./keyfile.json`


## How to run

Simply run:

```bash
$ ./gcp-bigquery.sh <PROJECT>
```

## Details of what the script is doing

Create dataset $PROJECT.$DATASET

```bash
$ docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"
```

Messages are sent to `kcbq-quickstart1` topic using:

```bash
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic kcbq-quickstart1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

The connector is created with:

```bash
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "kcbq-quickstart1",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "autoUpdateSchemas" : "true",
               "schemaRetriever" : "com.wepay.kafka.connect.bigquery.retrieve.IdentitySchemaRetriever",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .
```



After 120 seconds, data should be in GCP BigQuery:

```bash
$ bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.kcbq_quickstart1;"
Waiting on bqjob_r1bbecb24663a3f7c_0000016d825065f1_1 ... (0s) Current status: DONE
+---------+
|   f1    |
+---------+
| value1  |
| value8  |
| value5  |
| value2  |
| value7  |
| value3  |
| value10 |
| value6  |
| value9  |
| value4  |
+---------+
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
