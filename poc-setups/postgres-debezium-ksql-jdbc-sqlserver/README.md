# PoC Pipeline with Debezium from PSQL to MS-SQL-Server  

Creates an example pipeline based on the kafka connect demos for debezium and JDBC. 
Data flow is: **postgresql -> CDC with debezium -> flatten entries in ksqldb -> JDBC to sql server**.

## Setup
Have docker running and enter `./start.sh`
This will start up the docker images, set up the connectors pipeline and insert some example data into the source database.
After a few seconds, the CDC messages will be processed and corresponding lines will be inserted into the sink database. Have a look at the kafka connect log via `docker logs connect` and/or look at the intermediate topics and streams to see what is happening in the background.

## Checking the output / intermediate messages
* You can cross-check ksqldb and topics in C3 on `localhost:9021`
* alternatively use console-consumers to look into the topics:
```
# look at CDC messages
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --property print.key=true --property key.separator=" : " --timeout-ms 5000

# look at ksql-transformed messages
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic CUSTOMERS_FLAT --from-beginning --property print.key=true --property key.separator=" : " --timeout-ms 5000
```
* use `./query-psql.sh` to look at the source DB table
* use `./query-sqlserver.sh` to look at the target DB table

## ksqldb
* Connect to SQL Server: `docker exec -it ksqldb-cli ksql http://ksqldb-server:8088`
* (Re-)deploy the ksql-pipeline: `./setup_ksql-pipeline.sh`

## Other tests / examples
* example to illustrate tombstones in debezium: `./test-debezium-tombstone.sh`
* example script to insert same datasets into the source database: `./insert_datasets.sh`
* example JDBC config to set the correct PK and add whitelisting, i.e. only writing whitelisted fields to the sink:
    ```
    curl -X PUT \
         -H "Content-Type: application/json" \
         --data '{
                   "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                        "tasks.max": "1",
                        "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433",
                        "connection.user": "sa",
                        "connection.password": "Password!",
                        "topics": "CUSTOMERS_FLAT",
                        "auto.create": "true",
                        "pk.fields":"id",
                        "fields.whitelist": "id, LAST_NAME, FIRST_NAME"
              }' \
         http://localhost:8083/connectors/sqlserver-sink/config | jq .
    ```
