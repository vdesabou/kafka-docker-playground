# Fully Managed Salesforce Bulk API Source connector

## Objective

Quickly test the [Salesforce Bulk API Source](https://docs.confluent.io/cloud/current/connectors/cc-salesforce-bulk-api-source.html) fully managed connector.

The connector authenticates with username, password, security token and the consumer key/secret of a connected app. The sfdx CLI, used to create test data, logs in with the JWT Bearer flow.

## Prerequisites

> [!TIP]
> `playground salesforce setup` configures the Salesforce org (External Client App with the JWT Bearer flow, Platform Event, Change Data Capture) and stores `SALESFORCE_USERNAME`, `SALESFORCE_INSTANCE` and `SALESFORCE_CONSUMER_KEY_WITH_JWT`, see [Automated setup](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#automated-setup). `playground salesforce check` verifies them.

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* A Salesforce account with an External Client App using the JWT Bearer flow (see [Salesforce setup](#salesforce-setup))
* `salesforce-confluent.keystore.jks` (password `confluent`, it contains the private key matching the certificate of the External Client App) in this folder. If it is missing, the script tries to download it from the playground S3 bucket (Confluent employees only).

| Variable | Description |
| --- | --- |
| `SALESFORCE_USERNAME` | Salesforce username |
| `SALESFORCE_PASSWORD` | Salesforce password |
| `SALESFORCE_SECURITY_TOKEN` | Salesforce security token |
| `SALESFORCE_CONSUMER_KEY_WITH_JWT` | Consumer key of the External Client App with JWT Bearer flow enabled (used by the sfdx CLI) |
| `SALESFORCE_CONSUMER_KEY` | Optional, consumer key used by the connector, defaults to `SALESFORCE_CONSUMER_KEY_WITH_JWT` |
| `SALESFORCE_CONSUMER_PASSWORD` | Consumer secret of the app used by the connector |
| `SALESFORCE_INSTANCE` | Optional, defaults to `https://login.salesforce.com` |

## How to run

```bash
playground run -f fully-managed-salesforce-bulkapi-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-salesforce-bulkapi-source.sh` | `Lead` object, JSON output, password authentication |

## What the script does

1. Bootstraps the Confluent Cloud environment, recreates topic `sfdc-bulkapi-leads` and starts an `sfdx-cli` container.
2. Creates the fully managed `SalesforceBulkApiSource` connector on object `Lead` with `salesforce.since` set to today.
3. Logs in with the sfdx CLI (JWT) and creates a random Lead.
4. Verifies the record with `playground topic consume --topic sfdc-bulkapi-leads`.
5. Deletes the Lead created by the test on exit, and asks whether to delete the connector.

## Salesforce setup

1. Register a test account on the [Salesforce developer portal](https://developer.salesforce.com/signup/).
2. Create an External Client App with the OAuth JWT Bearer flow, following [OAuth with JWT Bearer Flow](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#oauth-with-jwt-bearer-flow). Its consumer key is `SALESFORCE_CONSUMER_KEY_WITH_JWT`.
3. Get your security token from *Settings* -> *My Personal Information* -> *Reset My Security Token*:

![security token](Screenshot1.png)

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-salesforce-bulkapi-source`](../../connect/connect-salesforce-bulkapi-source/README.md#benchmark): it loads Leads created with one Bulk API job for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to read a backlog of 100k records
playground connector benchmark --nb-records 100000
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
