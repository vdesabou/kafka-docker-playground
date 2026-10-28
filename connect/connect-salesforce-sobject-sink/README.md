# Salesforce SObject Sink connector

## Objective

Quickly test the [Salesforce SObject Sink](https://docs.confluent.io/current/connect/kafka-connect-salesforce/sobjects_sink/index.html#salesforce-sobject-sink-connector-for-cp) connector.

A Salesforce PushTopics Source connector reads Leads from a first Salesforce account into Kafka, and the SObject Sink connector writes them to a second Salesforce account. Both connectors authenticate with the OAuth JWT Bearer flow (`salesforce.grant.type=JWT_BEARER`).

## Prerequisites

> [!TIP]
> `playground salesforce setup` (account #1) and `playground salesforce setup --account2` (account #2) configure the Salesforce orgs (External Client App with the JWT Bearer flow, Platform Event, Change Data Capture) and store `SALESFORCE_USERNAME`, `SALESFORCE_INSTANCE` and `SALESFORCE_CONSUMER_KEY_WITH_JWT` (`_ACCOUNT2` for account #2), see [Automated setup](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#automated-setup). `playground salesforce check` (`--account2`) verifies them.

* Two Salesforce accounts: go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register two accounts.
* On each account, an External Client App with the JWT Bearer flow: follow [these instructions](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#oauth-with-jwt-bearer-flow). The same certificate (`salesforce-confluent.keystore.jks`) is used for both apps.
* With CP 8.x, connector version 2.0.29 or later.
* `salesforce-confluent.keystore.jks` (password `confluent`) in this folder. The keystore of `playground salesforce setup` (`~/.config/kafka-docker-playground/salesforce-confluent.keystore.jks`) is copied here automatically; without it, the script tries to download the shared one from the playground S3 bucket (Confluent employees only, with AWS credentials set).

| Variable | Description |
| --- | --- |
| `SALESFORCE_USERNAME` | Username of account #1 (source) |
| `SALESFORCE_PASSWORD` | Password of account #1 |
| `SALESFORCE_SECURITY_TOKEN` | Security token of account #1 |
| `SALESFORCE_CONSUMER_KEY_WITH_JWT` | Consumer key of the External Client App (JWT) of account #1 |
| `SALESFORCE_INSTANCE` | Optional, defaults to `https://login.salesforce.com` |
| `SALESFORCE_USERNAME_ACCOUNT2` | Username of account #2 (sink) |
| `SALESFORCE_PASSWORD_ACCOUNT2` | Password of account #2 |
| `SALESFORCE_SECURITY_TOKEN_ACCOUNT2` | Security token of account #2 |
| `SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2` | Consumer key of the External Client App (JWT) of account #2 |
| `SALESFORCE_INSTANCE_ACCOUNT2` | Optional, defaults to `https://login.salesforce.com` |

`salesforce-sobject-sink.sh` also accepts test-specific overrides suffixed with `_KDP_SOBJECT` (e.g. `SALESFORCE_USERNAME_KDP_SOBJECT`, `SALESFORCE_USERNAME_KDP_SOBJECT_ACCOUNT2`), which take precedence over the shared variables when set.

## How to run

```bash
playground run -f salesforce-sobject-sink.sh
```

| Script | Description |
| --- | --- |
| `salesforce-sobject-sink.sh` | Basic example |
| `salesforce-sobject-sink-proxy.sh` | Same, through an nginx forward proxy (`http.proxy=nginx-proxy:8888`); direct traffic from `connect` to both Salesforce instances is blocked |

## What the script does

1. Logs in with the sfdx CLI on account #1, (re)creates a PushTopic on `Lead` (name unique to the script and environment, from `MyLeadPushTopics-template.apex`).
2. Creates a Salesforce PushTopics Source connector writing to topic `sfdc-pushtopic-leads`.
3. Creates a random Lead on account #1 and verifies it is received in `sfdc-pushtopic-leads`.
4. Creates the Salesforce SObject Sink connector (object `Lead`, `salesforce.sink.object.operation=insert`, `override.event.type=true`) writing to account #2.
5. Verifies a record in the `success-responses` reporter topic and that `error-responses` is empty.
6. Logs in with the sfdx CLI on account #2 and queries the Lead to check it was inserted.
7. Deletes the Leads created by the test on both accounts on exit.
