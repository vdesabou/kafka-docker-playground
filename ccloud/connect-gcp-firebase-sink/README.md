# GCP Firebase Sink connector (using Confluent Cloud)

## Objective

Quickly test [GCP Firebase Sink](https://docs.confluent.io/current/connect/kafka-connect-firebase/sink/index.html#quick-start) connector.

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

* Active Google Cloud Platform (GCP) account with authorization to create resources

## GCP Firebase Setup

### Service Account setup

Create `Service Account` from IAM & Admin console:

Set `Service account name`:

![Service Account setup](Screenshot1.png)

Choose permission `Firebase`->`Firebase Realtime Database Admin`

![Service Account setup](Screenshot2.png)

Create Key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json` and place it in `./keyfile.json`

### Realtime Database setup

Go to [Firebase console](https://console.firebase.google.com), click `Add Project` and choose your GCP project.

In your console, click `Database`on the left sidebar:

![Realtime Database setup](Screenshot5.png)

Click on `Realtime Database`:

![Realtime Database setup](Screenshot6.png)

Click on `Enable`:

![Realtime Database setup](Screenshot7.png)

## How to run



Simply run:

```bash
$ playground run -f gcp-firebase-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <GCP_PROJECT>
```

### Verify data has been pushed to Firebase

Note: this is automated

Go to [Firebase console](https://console.firebase.google.com) and choose your GCP project.

In your console, click `Database`on the left sidebar:

![Realtime Database setup](Screenshot5.png)

Click on `Realtime Database`:

![Realtime Database setup](Screenshot6.png)

You should see:

![Realtime Database setup](Screenshot8.png)
