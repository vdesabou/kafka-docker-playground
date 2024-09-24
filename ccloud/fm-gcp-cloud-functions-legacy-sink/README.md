# Fully Managed Google Cloud Functions (Legacy) Sink connector



## Objective

Quickly test [Fully Managed Google Cloud Functions (Legacy) Sink](https://docs.confluent.io/cloud/current/connectors/cc-google-functions-sink.html) connector.


* Active Google Cloud Platform (GCP) account with authorization to create resources

## Google Cloud Functions Setup

* Navigate to the [Google Cloud Console](https://console.cloud.google.com/)

* Go to the [Cloud Functions](https://console.cloud.google.com/functions) tab.

![Cloud functions setup](Screenshot1.png)

* Create a new function. Use the default code that is provided.

![Cloud functions setup](Screenshot2.png)

Note down the project id, the region (example `us-central1`), and the function name (example `function-1`) as they will be used later.

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)


## How to run

Simply run:

```bash
$ just use <playground run> command and search for fully-managed-google-cloud-functions<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <GCP_FUNCTION_REGION> <GCP_FUNCTION_FUNCTION> .sh in this folder
```
