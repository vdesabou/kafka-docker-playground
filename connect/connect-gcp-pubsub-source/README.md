# GCP Pub/Sub Source connector



## Objective

Quickly test [GCP Pub/Sub Source](https://docs.confluent.io/current/connect/kafka-connect-gcp-pubsub/index.html#quick-start) connector.

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
$ just use <playground run> command and search for gcp-pubsub<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> .sh in this folder
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

Publish three messages to $GCP_PUB_SUB_TOPIC

```bash
$ gcloud pubsub topics publish $GCP_PUB_SUB_TOPIC --message "Peter"
gcloud pubsub topics publish $GCP_PUB_SUB_TOPIC --message "Megan"
gcloud pubsub topics publish $GCP_PUB_SUB_TOPIC --message "Erin"
```

Creating GCP PubSub Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.gcp.pubsub.PubSubSourceConnector",
                    "tasks.max" : "1",
                    "kafka.topic" : "pubsub-topic",
                    "gcp.pubsub.project.id" : "$GCP_PROJECT",
                    "gcp.pubsub.topic.id" : "$GCP_PUB_SUB_TOPIC",
                    "gcp.pubsub.subscription.id" : "$GCP_PUB_SUB_SUBSCRIPTION",
                    "gcp.pubsub.credentials.path" : "/tmp/keyfile.json",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/pubsub-source/config | jq .
```

Verify messages are in topic `pubsub-topic`

```bash
playground topic consume --topic pubsub-topic --min-expected-messages 3 --timeout 60
```

Results:

```json
{"MessageData":{"string":"Megan"},"AttributesMap":{}}
{"MessageData":{"string":"Peter"},"AttributesMap":{}}
{"MessageData":{"string":"Erin"},"AttributesMap":{}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
