# Fully Managed GCP BigTable Sink connector



## Objective

Quickly test [GCP BigTable Sink](https://docs.confluent.io/cloud/current/connectors/cc-gcp-bigtable-sink.html) connector.

* Active Google Cloud Platform (GCP) account with authorization to create resources

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2` for aws, `westeurope`for azure and `europe-west2` for gcp)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `txxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `txxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)


## GCP BigTable Setup

### Enabling Cloud BigTable Admin API

Go to this [link](https://console.developers.google.com/apis/library/bigtableadmin.googleapis.com) and click `Enable`:

![Enabling Cloud BigTable Admin API](Screenshot5.png)

### Setup Credentials

* Create `Service Account` from IAM & Admin console:

Set `Service account name`:

![Service Account setup](Screenshot1.png)

Choose permission `Cloud BigTable`->`BigTable Administrator`

![Service Account setup](Screenshot2.png)

Create Key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json`and place it in `./keyfile.json` or use environment variable `GCP_KEYFILE_CONTENT` with content generated with `GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`


## How to run

Simply run:

```bash
$ just use <playground run>
```
