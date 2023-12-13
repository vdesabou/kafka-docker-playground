# Google Cloud Pub/Sub Group Kafka Connector Source connector



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

Rename it to `keyfile.json`and place it in `./keyfile.json` or use environment variable `GCP_KEYFILE_CONTENT` with content generated with `GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`


## How to run

Simply run:

```bash
$ playground run -f gcp-google-pubsub-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path> <GCP_PROJECT>
```

## Details of what the script is doing

Doing gsutil authentication

```bash
$ gcloud auth activate-service-account --key-file ${GCP_KEYFILE}
```

Create a Pub/Sub topic called topic-1

```bash
$ gcloud pubsub topics create topic-1
```

Create a Pub/Sub subscription called subscription-1

```bash
$ gcloud pubsub subscriptions create --topic topic-1 subscription-1
```

Publish three messages to topic-1

```bash
$ gcloud pubsub topics publish topic-1 --message "Peter"
gcloud pubsub topics publish topic-1 --message "Megan"
gcloud pubsub topics publish topic-1 --message "Erin"
```

Creating reating Google Cloud Pub/Sub Group Kafka Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.google.pubsub.kafka.source.CloudPubSubSourceConnector",
               "tasks.max" : "1",
               "kafka.topic" : "pubsub-topic",
               "cps.project" : "$GCP_PROJECT",
               "cps.topic" : "topic-1",
               "cps.subscription" : "subscription-1",
               "gcp.credentials.file.path" : "/tmp/keyfile.json",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/pubsub-source/config | jq .
```

Verify messages are in topic `pubsub-topic`

```bash
playground topic consume --topic pubsub-topic --min-expected-messages 3 --timeout 60
```

Results:

```
"Peter"
"Erin"
"Megan"
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
