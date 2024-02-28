# JDBC Snowflake Sink connector


## Objective

Quickly test [JDBC Snowflake Sink](https://docs.confluent.io/kafka-connect-jdbc/current/sink-connector/index.html#jdbc-sink-connector-for-cp) connector.

## Caveats

JDBC connector does not have a specific *Snowflake* dialect therefore *Generic* dialect is used, it comes with caveats:
 
For example:
 
* It was identified that latest version of Snowflake driver `3.14.4`` is creating issue with *TIMESTAMP*:

```log
WARN [jdbc-snowflake|task-0] JDBC type 2014 (TIMESTAMPTZ) not currently supported (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:1204)
```

After testing lower versions, I’ve identified that `3.13.16` is working fine (I assume it comes as *TIMESTAMP* instead as *TIMESTAMPTZ* which is not supported by GenericDialect)
  
* It was also identified that to make it work with timestamps, we had to create a view where each DATE and TIMESTAMP columns have to be explicitly converted to UTC, example:

```sql
create or replace view MYVIEWFORFOO as select id,f1,update_ts, convert_timezone('UTC', loaddate) as loaddate, convert_timezone('UTC', submitdate) as submitdate, convert_timezone('UTC', insuredbirthdate) as insuredbirthdate from FOO;
```

PS: `db.timezone` had no impact

## Register a trial account

Go to [Snowflake](https://www.snowflake.com) and register an account. You'll receive an email to setup your account and access to a 30 day trial instance.

## How to run

Simply run:

```bash
$ just use <playground run> command and search for jdbc-snowflake-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <SNOWFLAKE_ACCOUNT_NAME> <SNOWFLAKE_USERNAME> .sh in this folder
```

Note: you can also export these values as environment variable

