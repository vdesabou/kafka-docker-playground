# Fully Managed Salesforce PushTopics Source connector

## Objective

Quickly test the [Salesforce PushTopic Source](https://docs.confluent.io/cloud/current/connectors/cc-salesforce-pushtopic-source.html) fully managed connector.

The connector authenticates with the OAuth JWT Bearer flow (`salesforce.grant.type=JWT_BEARER`).

## Prerequisites

> [!TIP]
> `playground salesforce setup` configures the Salesforce org (External Client App with the JWT Bearer flow, Platform Event, Change Data Capture) and stores `SALESFORCE_USERNAME`, `SALESFORCE_INSTANCE` and `SALESFORCE_CONSUMER_KEY_WITH_JWT`, see [Salesforce examples: set up an org](https://kafka-docker-playground.io/#/salesforce) (Salesforce CLI install, second org, troubleshooting). `playground salesforce check` verifies them.

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* A Salesforce account with an External Client App using the JWT Bearer flow (see [Salesforce setup](#salesforce-setup))
* `salesforce-confluent.keystore.jks` (password `confluent`, it contains the private key matching the certificate of the External Client App) in this folder. The keystore of `playground salesforce setup` (`~/.config/kafka-docker-playground/salesforce-confluent.keystore.jks`) is copied here automatically; without it, the script tries to download the shared one from the playground S3 bucket (Confluent employees only).

| Variable | Description |
| --- | --- |
| `SALESFORCE_USERNAME` | Salesforce username |
| `SALESFORCE_PASSWORD` | Salesforce password |
| `SALESFORCE_SECURITY_TOKEN` | Salesforce security token |
| `SALESFORCE_CONSUMER_KEY_WITH_JWT` | Consumer key of the External Client App with JWT Bearer flow enabled |
| `SALESFORCE_INSTANCE` | Optional, defaults to `https://login.salesforce.com` |

## How to run

```bash
playground run -f fully-managed-salesforce-pushtopic-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-salesforce-pushtopic-source.sh` | PushTopic on `Lead`, JSON output, JWT Bearer authentication |

## What the script does

1. Generates `MyLeadPushTopics.apex` from `MyLeadPushTopics-template.apex` with a PushTopic name unique to the run.
2. Bootstraps the Confluent Cloud environment, recreates topic `sfdc-pushtopic-leads-pushtopic-source` and starts an `sfdx-cli` container.
3. Logs in with the sfdx CLI (JWT) and (re)creates the Lead PushTopic.
4. Creates the fully managed `SalesforcePushTopicSource` connector on object `Lead`.
5. Creates a random Lead and verifies it with `playground topic consume --topic sfdc-pushtopic-leads-pushtopic-source`.
6. Deletes the Lead and the PushTopic created by the test on exit, and asks whether to delete the connector.

## Salesforce setup

1. Register a test account on the [Salesforce developer portal](https://developer.salesforce.com/signup/).
2. Create an External Client App with the OAuth JWT Bearer flow, following [OAuth with JWT Bearer Flow](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#oauth-with-jwt-bearer-flow). Its consumer key is `SALESFORCE_CONSUMER_KEY_WITH_JWT`.
3. Get your security token from *Settings* -> *My Personal Information* -> *Reset My Security Token*:

![security token](Screenshot1.png)
