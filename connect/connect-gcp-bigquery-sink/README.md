# GCP BigQuery Sink connector



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

Rename it to `keyfile.json`and place it in `./keyfile.json` or use environment variable `GCP_KEYFILE_CONTENT` with content generated with `GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`


## How to run

Simply run:

```bash
$ playground run -f gcp-bigquery<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path> <GCP_PROJECT>
```

## Details of what the script is doing

Create dataset $GCP_PROJECT.$DATASET

```bash
$ docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" mk --dataset --description "used by playground" "$DATASET"
```

Messages are sent to `kcbq-quickstart1` topic using:

```bash
playground topic produce -t kcbq-quickstart1 --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF
```

The connector is created with:

```bash
playground connector create-or-update --connector gcp-bigquery-sink << EOF
{
     "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
     "tasks.max" : "1",
     "topics" : "kcbq-quickstart1",
     "sanitizeTopics" : "true",
     "autoCreateTables" : "true",
     "autoUpdateSchemas" : "true",
     "schemaRetriever" : "com.wepay.kafka.connect.bigquery.retrieve.IdentitySchemaRetriever",
     "defaultDataset" : "$DATASET",
     "mergeIntervalMs": "5000",
     "bufferSize": "100000",
     "maxWriteSize": "10000",
     "tableWriteWait": "1000",
     "project" : "$GCP_PROJECT",
     "keyfile" : "/tmp/keyfile.json",
}
EOF
```



After 120 seconds, data should be in GCP BigQuery:

```bash
$ bq --project_id "$GCP_PROJECT" query "SELECT * FROM $DATASET.kcbq_quickstart1;"
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
