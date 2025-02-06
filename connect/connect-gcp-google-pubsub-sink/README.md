# Google Cloud Pub/Sub Group Kafka Connector sink connector



## Objective

Quickly test [Google Cloud Pub/Sub Group Kafka Connector](https://github.com/googleapis/java-pubsub-group-kafka-connector) connector.

* Active Google Cloud Platform (GCP) account with authorization to create resources

## GCP Pub/Sub Setup

* Create `Service Account` from IAM & Admin console:

Set `Service account name`:

![Service Account setup](Screenshot1.png)


Choose permission `Pub/Sub`->`Pub/Sub Admin`

![Service Account setup](Screenshot2.png)

Create Key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json`and place it in `./keyfile.json` or use environment variable `GCP_KEYFILE_CONTENT` with content generated with `GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')


## How to run

Simply run:

```bash
$ just use <playground run> command and search for gcp-google-pubsub-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> .sh in this folder
```

## Details of what the script is doing

Doing gsutil authentication

```bash
$ gcloud auth activate-service-account --key-file ${GCP_KEYFILE}
```

Create a Pub/Sub topic called $GCP_PUB_SUB_TOPIC

```bash
$ gcloud pubsub topics create $GCP_PUB_SUB_TOPIC
```

Create a Pub/Sub subscription called $GCP_PUB_SUB_SUBSCRIPTION

```bash
$ gcloud pubsub subscriptions create --topic $GCP_PUB_SUB_TOPIC $GCP_PUB_SUB_SUBSCRIPTION
```


Creating Google Cloud Pub/Sub Group Kafka Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.google.pubsub.kafka.sink.CloudPubSubSinkConnector",
               "tasks.max" : "1",
               "topics" : "pubsub-topic",
               "cps.project" : "$GCP_PROJECT",
               "cps.topic" : "$GCP_PUB_SUB_TOPIC",
               "gcp.credentials.file.path" : "/tmp/keyfile.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
               "metadata.publish": "true",
               "headers.publish": "true"
          }' \
     http://localhost:8083/connectors/pubsub-sink/config | jq .
```



N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
