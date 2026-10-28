# Salesforce PushTopics Source connector

## Objective

Quickly test the [Salesforce PushTopics Source](https://docs.confluent.io/current/connect/kafka-connect-salesforce/pushtopics/salesforce_pushtopic_source_connector_quickstart.html#example-configure-salesforce-pushtopic-source-connector) connector.

The connector authenticates with the OAuth JWT Bearer flow (`salesforce.grant.type=JWT_BEARER`).

## Prerequisites

> [!TIP]
> `playground salesforce setup` configures the Salesforce org (External Client App with the JWT Bearer flow, Platform Event, Change Data Capture) and stores `SALESFORCE_USERNAME`, `SALESFORCE_INSTANCE` and `SALESFORCE_CONSUMER_KEY_WITH_JWT`, see [Automated setup](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#automated-setup). `playground salesforce check` verifies them.

* A Salesforce account: go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.
* An External Client App with the JWT Bearer flow: follow [these instructions](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#oauth-with-jwt-bearer-flow).
* With CP 8.x, connector version 2.0.29 or later.
* `salesforce-confluent.keystore.jks` (password `confluent`) in this folder. If it is missing, the script tries to download it from the playground S3 bucket (Confluent employees only, with AWS credentials set).

| Variable | Description |
| --- | --- |
| `SALESFORCE_USERNAME` | Salesforce username |
| `SALESFORCE_PASSWORD` | Salesforce password |
| `SALESFORCE_SECURITY_TOKEN` | Salesforce security token (see [Find your security token](#find-your-security-token)) |
| `SALESFORCE_CONSUMER_KEY_WITH_JWT` | Consumer key of the External Client App with JWT Bearer flow enabled |
| `SALESFORCE_INSTANCE` | Optional, defaults to `https://login.salesforce.com` |

`salesforce-pushtopic-source.sh` also accepts test-specific overrides suffixed with `_KDP_PUSHTOPIC` (e.g. `SALESFORCE_USERNAME_KDP_PUSHTOPIC`), which take precedence over the shared variables when set.

## How to run

```bash
playground run -f salesforce-pushtopic-source.sh
```

| Script | Description |
| --- | --- |
| `salesforce-pushtopic-source.sh` | Basic example |
| `salesforce-pushtopic-source-proxy.sh` | Same, through an nginx forward proxy (`http.proxy=nginx-proxy:8888`); direct traffic from `connect` to Salesforce is blocked |
| `salesforce-pushtopic-source-proxy-basic-auth.sh` | Same, through a squid proxy with basic authentication. Not expected to work: the PushTopic connector does not support `http.proxy.user` (the script exits immediately) |

## What the script does

1. Generates `MyLeadPushTopics.apex` from `MyLeadPushTopics-template.apex` with a PushTopic name unique to the script and environment.
2. Logs in with the sfdx CLI (JWT), deletes the PushTopic if it already exists, and creates it on `Lead`.
3. Creates the Salesforce PushTopics Source connector (object `Lead`), writing to topic `sfdc-pushtopic-leads` (JSON converter), and waits for the subscription.
4. Creates a random Lead in Salesforce.
5. Verifies the record is received with `playground topic consume --topic sfdc-pushtopic-leads`.
6. Deletes the Lead created by the test on exit.

## Find your security token

Find your security token (emailed to you from Salesforce.com). To reset it, select *Settings* -> *My Personal Information* -> *Reset My Security Token* and follow the instructions.

![security token](Screenshot1.png)
