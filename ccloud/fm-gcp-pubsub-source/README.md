# Fully Managed GCP Pub/Sub Source connector



## Objective

Quickly test [Fully Managed GCP Pub/Sub Source](https://docs.confluent.io/cloud/current/connectors/cc-google-pubsub-source.html) connector.

* Active Google Cloud Platform (GCP) account with authorization to create resources


## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)


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
$ just use <playground run> 
```