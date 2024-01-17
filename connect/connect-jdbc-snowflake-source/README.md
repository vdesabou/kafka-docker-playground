# JDBC Snowflake Source connector


## Objective

Quickly test [JDBC Snowflake Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.

## Caveats

JDBC connector does not have a specific *Snowflake* dialect therefore *Generic* dialect is used, it comes with caveats:
 
For example:
 
* It was identified that latest version of Snowflake driver `3.13.26`` is creating issue with *TIMESTAMP*:

```log
WARN [jdbc-snowflake|task-0] JDBC type 2014 (TIMESTAMPTZ) not currently supported (io.confluent.connect.jdbc.dialect.GenericDatabaseDialect:1204)
```

After testing lower versions, I’ve identified that `3.13.16`` is working fine (I assume it comes as *TIMESTAMP* instead as *TIMESTAMPTZ* which is not supported by GenericDialect)
  
* It was also identified that to make it work with timestamps, we had to create a view where each DATE and TIMESTAMP columns have to be explicitly converted to UTC, example:

```sql
create or replace view MYVIEWFORFOO as select id,f1,update_ts, convert_timezone('UTC', loaddate) as loaddate, convert_timezone('UTC', submitdate) as submitdate, convert_timezone('UTC', insuredbirthdate) as insuredbirthdate from FOO;
```

## Register a trial account

Go to [Snowflake](https://www.snowflake.com) and register an account. You'll receive an email to setup your account and access to a 30 day trial instance.

## How to run

Simply run:

```bash
$ playground run -f jdbc-snowflake-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <SNOWFLAKE_ACCOUNT_NAME> <SNOWFLAKE_USERNAME> <SNOWFLAKE_PASSWORD>
```

Note: you can also export these values as environment variable
