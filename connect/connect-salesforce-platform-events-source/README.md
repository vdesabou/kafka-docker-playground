# Salesforce Platform Events Source connector

## Objective

Quickly test the [Salesforce Platform Events Source](https://docs.confluent.io/current/connect/kafka-connect-salesforce/platformevents/index.html#salesforce-platform-events-source-connector-for-cp) connector.

The connector authenticates with the OAuth JWT Bearer flow (`salesforce.grant.type=JWT_BEARER`).

## Prerequisites

> [!TIP]
> `playground salesforce setup` configures the Salesforce org (External Client App with the JWT Bearer flow, Platform Event, Change Data Capture) and stores `SALESFORCE_USERNAME`, `SALESFORCE_INSTANCE` and `SALESFORCE_CONSUMER_KEY_WITH_JWT`, see [Automated setup](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#automated-setup). `playground salesforce check` verifies them.

* A Salesforce account: go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.
* An External Client App with the JWT Bearer flow: follow [these instructions](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#oauth-with-jwt-bearer-flow).
* A Platform Event `MyPlatformEvent__e` with a text field `Message__c` (see [Create a Platform Event](#create-a-platform-event-in-salesforce)).
* With CP 8.x, connector version 2.0.29 or later.
* `salesforce-confluent.keystore.jks` (password `confluent`) in this folder. The keystore of `playground salesforce setup` (`~/.config/kafka-docker-playground/salesforce-confluent.keystore.jks`) is copied here automatically; without it, the script tries to download the shared one from the playground S3 bucket (Confluent employees only, with AWS credentials set).

| Variable | Description |
| --- | --- |
| `SALESFORCE_USERNAME` | Salesforce username |
| `SALESFORCE_PASSWORD` | Salesforce password |
| `SALESFORCE_SECURITY_TOKEN` | Salesforce security token (see [Find your security token](#find-your-security-token)) |
| `SALESFORCE_CONSUMER_KEY_WITH_JWT` | Consumer key of the External Client App with JWT Bearer flow enabled |
| `SALESFORCE_INSTANCE` | Optional, defaults to `https://login.salesforce.com` |

`salesforce-platform-events-source.sh` also accepts test-specific overrides suffixed with `_KDP_PE_SOURCE` (e.g. `SALESFORCE_USERNAME_KDP_PE_SOURCE`), which take precedence over the shared variables when set.

## How to run

```bash
playground run -f salesforce-platform-events-source.sh
```

| Script | Description |
| --- | --- |
| `salesforce-platform-events-source.sh` | Basic example |
| `salesforce-platform-events-source-proxy.sh` | Same, through an nginx forward proxy (`http.proxy=nginx-proxy:8888`); direct traffic from `connect` to Salesforce is blocked |

## What the script does

1. Creates the Salesforce Platform Events Source connector on `MyPlatformEvent__e`, writing to topic `sfdc-platform-events` (JSON converter), and waits for the subscription.
2. Logs in with the sfdx CLI (JWT) and publishes 2 platform events with `event.apex`.
3. Verifies the 2 events are received with `playground topic consume --topic sfdc-platform-events`.

## Find your security token

Find your security token (emailed to you from Salesforce.com). To reset it, select *Settings* -> *My Personal Information* -> *Reset My Security Token* and follow the instructions.

![security token](Screenshot1.png)

## Create a Platform Event in Salesforce

In Setup, search for *Platform Events*:

![Platform Event](Screenshot7.png)

Create a new Platform Event called *MyPlatformEvent*:

![Platform Event](Screenshot6.png)

Add a text field *Message*:

![Platform Event](Screenshot8.png)

## Send a Platform Event manually (optional)

The script publishes the events automatically. To do it by hand, select *Developer Console* in the upper right menu:

![Platform Event](Screenshot9.png)

Then choose *Debug* -> *Open Execute Anonymous Window*:

![Platform Event](Screenshot10.png)

and execute the content of [event.apex](event.apex).
