# JDBC Snowflake Source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with Snowflake, using the Snowflake JDBC driver and key pair authentication.

**Not working with CP 8.0+**: with driver `3.13.16`, the task fails with `JDBC driver internal error: Fail to retrieve row count for first arrow chunk: sun.misc.Unsafe or java.nio.DirectByteBuffer.<init>(long, int) not available.` Upgrading the driver fixes this, but then hits the `TIMESTAMPTZ` issue described in [Caveats](#caveats).

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
playground run -f jdbc-snowflake-source.sh
```

| Script | Description |
| --- | --- |
| `jdbc-snowflake-source.sh` | JDBC source in `timestamp+incrementing` mode on a Snowflake view |

## What the script does

1. Copies `snowflake-jdbc-3.13.16.jar` into the JDBC connector `lib` folder.
2. Generates an encrypted RSA private key (`snowflake_key.p8`, PBE-SHA1-RC4-128) and its public key.
3. With `snowsql`, (re)creates a database with schema `MYSCHEMA`, a role, an XSMALL warehouse and a user (with the RSA public key), all with names unique to your environment.
4. Starts the environment, creates table `FOO (id, f1, update_ts)` with 3 rows, and a view `MYVIEWFORFOO` that converts `update_ts` to UTC.
5. Creates the `jdbc-snowflake-source` connector on the view (`table.types=VIEW`, `mode=timestamp+incrementing` on `UPDATE_TS` / `ID`, `topic.prefix=snowflake-`).
6. Verifies that 3 records land in topic `snowflake-MYVIEWFORFOO` with `playground topic consume`.

## Caveats

The JDBC connector has no specific Snowflake dialect, so the generic dialect is used, which comes with caveats:

* Recent Snowflake driver versions (for example `3.14.4`) cause issues with `TIMESTAMP` columns:

  ```log
  WARN [jdbc-snowflake|task-0] JDBC type 2014 (TIMESTAMPTZ) not currently supported (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:1204)
  ```

  Version `3.13.16` works fine with CP 7.x (the column is probably reported as `TIMESTAMP` instead of `TIMESTAMPTZ`, which the generic dialect does not support).

* To make it work with timestamps, a view where each `DATE` and `TIMESTAMP` column is explicitly converted to UTC is needed, for example:

  ```sql
  create or replace view MYVIEWFORFOO as select id,f1,update_ts, convert_timezone('UTC', loaddate) as loaddate, convert_timezone('UTC', submitdate) as submitdate, convert_timezone('UTC', insuredbirthdate) as insuredbirthdate from FOO;
  ```
