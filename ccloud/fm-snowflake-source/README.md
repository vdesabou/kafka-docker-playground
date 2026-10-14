# Fully Managed Snowflake Source connector

## Objective

Quickly test the [Snowflake Source](https://docs.confluent.io/cloud/current/connectors/cc-snowflake-source/cc-snowflake-source.html) fully managed connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* A Snowflake account (see [Register a trial account](#register-a-trial-account))

| Variable | Description |
| --- | --- |
| `SNOWFLAKE_ACCOUNT_NAME` | `<account_locator>.<region_id>.<cloud_provider>`, see [Register a trial account](#register-a-trial-account) |
| `SNOWFLAKE_USERNAME` | Snowflake admin username, used to create the database, role, warehouse and user |
| `SNOWFLAKE_PASSWORD` | Password of `SNOWFLAKE_USERNAME` |

## How to run

```bash
playground run -f fully-managed-snowflake-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-snowflake-source.sh` | `timestamp+incrementing` mode, key pair authentication, Avro output |

## What the script does

1. Bootstraps the Confluent Cloud environment.
2. Generates an encrypted RSA key pair (`snowflake_key.p8` / `snowflake_key.pub`, passphrase `confluent`).
3. With `snowsql`, creates a database with schema `MYSCHEMA`, a role, a warehouse and a user (with the public key), unique to the script.
4. Creates table `TEST_TABLE` (`ID` autoincrement, `F1`, `UPDATE_TS`), inserts 3 rows and reads the account `TIMEZONE` parameter.
5. Creates the fully managed `SnowflakeSource` connector (`mode=timestamp+incrementing`, `topic.prefix=pg.`, `db.timezone` set to the account timezone).
6. Verifies the 3 records with `playground topic consume --topic pg.<database>.MYSCHEMA.TEST_TABLE`.
7. Asks whether to delete the connector.

## Register a trial account

Go to [Snowflake](https://www.snowflake.com) and register an account. You receive an email to set up your account and access a 30-day trial instance.

To get `SNOWFLAKE_ACCOUNT_NAME`, get the *Account Locator* from:

![ui](ui.png)

`SNOWFLAKE_ACCOUNT_NAME` must be set to `<account_locator>.<region_id>.<cloud_provider>` (for example `XXXXX.eu-west-3.aws`).
