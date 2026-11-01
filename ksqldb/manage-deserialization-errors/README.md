# How to find the records that ksqlDB could not deserialize

## Objective

A stream reads JSON records where one has the wrong type (`"enabled": "true"`, a string, instead of a boolean). ksqlDB skips that record and writes the deserialization error to the processing log. The example shows:

* the push query on the derived stream, which only returns the 2 valid records
* the `KSQL_PROCESSING_LOG` stream, with the error message, the cause and the original record (decoded from base64)
* `PRINT ksql_processing_log`, the raw processing log topic

The processing log is enabled with the `KSQL_KSQL_LOGGING_PROCESSING_*` and `KSQL_LOG4J_PROCESSING_LOG_*` environment variables of ksqldb-server, in `docker-compose.plaintext.yml`.

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

## Resources

https://docs.confluent.io/platform/current/ksqldb/reference/processing-log.html
