# Salesforce Bulk API Sink connector

## Objective

Quickly test the [Salesforce Bulk API Sink](https://docs.confluent.io/current/connect/kafka-connect-salesforce-bulk-api/sink/index.html) connector.

Leads are read from a first Salesforce account with a source connector (Bulk API or PushTopics), then written to a second Salesforce account with the Bulk API sink connector.

## Prerequisites

* Two Salesforce accounts (see [Register test accounts](#register-test-accounts)).
* On each account, an External Client App with the JWT Bearer flow enabled (see [OAuth with JWT Bearer Flow](#oauth-with-jwt-bearer-flow)), trusting the same certificate. It is always used by the sfdx CLI, and also by the Bulk API connectors for versions that support `JWT_BEARER` (3.0.15 to 3.0.x, and later than 3.1.8). Older versions authenticate with username, password and security token. The PushTopic source connector always uses `JWT_BEARER`.
* `salesforce-confluent.keystore.jks` (password `confluent`) in this folder. If it is missing, the script tries to download it from the playground S3 bucket (Confluent employees only, with AWS credentials set).
* With CP 8.x, connector version 2.0.29 or later (the script exits with code 111 otherwise).

| Variable | Description |
| --- | --- |
| `SALESFORCE_USERNAME` | Username of account #1 (source) |
| `SALESFORCE_PASSWORD` | Password of account #1 |
| `SALESFORCE_SECURITY_TOKEN` | Security token of account #1 |
| `SALESFORCE_CONSUMER_KEY_WITH_JWT` | Consumer key of the External Client App of account #1 |
| `SALESFORCE_INSTANCE` | Optional, defaults to `https://login.salesforce.com` |
| `SALESFORCE_USERNAME_ACCOUNT2` | Username of account #2 (sink) |
| `SALESFORCE_PASSWORD_ACCOUNT2` | Password of account #2 |
| `SALESFORCE_SECURITY_TOKEN_ACCOUNT2` | Security token of account #2 |
| `SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2` | Consumer key of the External Client App of account #2 |
| `SALESFORCE_INSTANCE_ACCOUNT2` | Optional, defaults to `https://login.salesforce.com` |

`salesforce-bulkapi-sink-with-bulkapi-source.sh` also accepts test-specific overrides suffixed with `_KDP_BULKAPI_SINK` (e.g. `SALESFORCE_USERNAME_KDP_BULKAPI_SINK`, `SALESFORCE_USERNAME_KDP_BULKAPI_SINK_ACCOUNT2`), which take precedence over the shared variables when set.

## How to run

```bash
playground run -f salesforce-bulkapi-sink-with-bulkapi-source.sh
```

| Script | Description |
| --- | --- |
| `salesforce-bulkapi-sink-with-bulkapi-source.sh` | Bulk API source connector on account #1, Bulk API sink connector on account #2 |
| `salesforce-bulkapi-sink-with-bulkapi-source-proxy.sh` | Same, through an nginx forward proxy (`http.proxy=nginx-proxy:8888`); direct traffic from `connect` to Salesforce is blocked to make sure the proxy is used |
| `salesforce-bulkapi-sink-with-pushtopics-source.sh` | PushTopic source connector on account #1 (PushTopic created from `MyLeadPushTopics-template.apex`), Bulk API sink connector on account #2 |
| `salesforce-bulkapi-sink-with-pushtopics-source-proxy.sh` | Same, through an nginx forward proxy |

## What the script does

1. Picks the authentication grant (`JWT_BEARER` or `PASSWORD`) from the connector version, and starts the environment with an `sfdx-cli` container.
2. Logs in with the sfdx CLI (JWT) on account #1 (PushTopic variants: also re-creates the Lead PushTopic and creates the PushTopic source connector `salesforce-pushtopic-source`, topic `sfdc-pushtopic-leads`).
3. Creates a random Lead in account #1.
4. Bulk API variants: creates the Bulk API source connector `salesforce-bulkapi-source` (object `Lead`, topic `sfdc-bulkapi-leads`).
5. Verifies that the Lead is received in the source topic with `playground topic consume`.
6. Creates the Bulk API sink connector `salesforce-bulkapi-sink` on account #2 (object `Lead`, `salesforce.ignore.fields=CleanStatus`, `salesforce.ignore.reference.fields=true`, results reported to topics `success-responses` and `error-responses`).
7. Verifies that topic `success-responses` receives a record and that `error-responses` is empty (PushTopic variants: that it has no error for the Lead of the run, since the PushTopic also sends the Leads created by other jobs in the same org), then queries account #2 with the sfdx CLI to check that the Lead was created.
8. Deletes the test Leads (and the PushTopic) on exit.

## Register test accounts

Go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register two accounts.

## OAuth with JWT Bearer Flow

Follow the instructions from [here](../connect-salesforce-cdc-source/README.md#oauth-with-jwt-bearer-flow) to create the External Client App with the JWT Bearer flow, on both accounts.
