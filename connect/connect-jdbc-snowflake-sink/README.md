# JDBC Snowflake Sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with Snowflake, using the Snowflake JDBC driver 3.13.16 and key pair authentication.

## Prerequisites

### Register a trial account

Go to [Snowflake](https://www.snowflake.com) and register an account. You'll receive an email to set up your account and access a 30-day trial instance.

| Variable | Description |
| --- | --- |
| `SNOWFLAKE_ACCOUNT_NAME` | Account identifier, as in `https://<SNOWFLAKE_ACCOUNT_NAME>.snowflakecomputing.com` (may include the region, e.g. `xy12345.eu-west-1`) |
| `SNOWFLAKE_USERNAME` | Admin user, used to create the database, role, warehouse and user |
| `SNOWFLAKE_PASSWORD` | Password of `SNOWFLAKE_USERNAME` |

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
export SNOWFLAKE_ACCOUNT_NAME="<account name>"
export SNOWFLAKE_USERNAME="<username>"
export SNOWFLAKE_PASSWORD="<password>"
playground run -f jdbc-snowflake-sink.sh
```

| Script | Description |
| --- | --- |
| `jdbc-snowflake-sink.sh` | JDBC sink writing Avro records into an existing Snowflake table |

## What the script does

1. Downloads `snowflake-jdbc-3.13.16.jar` if needed and copies it into the JDBC connector `lib` folder.
2. Generates an encrypted RSA private key (`snowflake_key.p8`, PBE-SHA1-RC4-128) and its public key.
3. With `snowsql`, (re)creates a database, a role, an XSMALL warehouse and a user (with the RSA public key), all with names unique to your environment.
4. Starts the environment, creates table `FOO (f1 string, update_ts timestamp)` and produces 10 Avro records to topic `FOO`.
5. Creates the `jdbc-snowflake-sink` connector (`auto.create=false`, key pair authentication with `private_key_file=/tmp/snowflake_key.p8`).
6. Selects `FOO` as the connector user and checks that `value1` is present.

## Caveats

The JDBC connector has no specific Snowflake dialect, so the generic dialect is used, which comes with caveats:

* Recent Snowflake driver versions (for example `3.14.4`) cause issues with `TIMESTAMP` columns:

  ```log
  WARN [jdbc-snowflake|task-0] JDBC type 2014 (TIMESTAMPTZ) not currently supported (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:1204)
  ```

  Version `3.13.16` works fine (the column is probably reported as `TIMESTAMP` instead of `TIMESTAMPTZ`, which the generic dialect does not support).

* To make it work with timestamps, a view where each `DATE` and `TIMESTAMP` column is explicitly converted to UTC was needed, for example:

  ```sql
  create or replace view MYVIEWFORFOO as select id,f1,update_ts, convert_timezone('UTC', loaddate) as loaddate, convert_timezone('UTC', submitdate) as submitdate, convert_timezone('UTC', insuredbirthdate) as insuredbirthdate from FOO;
  ```

  `db.timezone` had no impact.
