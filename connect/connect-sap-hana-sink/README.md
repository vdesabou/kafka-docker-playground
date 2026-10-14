# SAP HANA Sink connector

## Objective

Quickly test the [SAP HANA Sink](https://github.com/SAP/kafka-connect-sap) connector.

## Prerequisites

* CP 6.0.0 or later. Not supported with the `cfk` environment.
* The connector jar is built from source (tag `0.9.3`) with Maven in Docker on the first run, and the SAP HANA JDBC driver `ngdbc-2.12.9.jar` is downloaded from Maven Central.

## How to run

```bash
playground run -f sap-hana-sink.sh
```

## What the script does

1. Builds `kafka-connector-hana_2.13-0.9.3.jar` from [SAP/kafka-connect-sap](https://github.com/SAP/kafka-connect-sap) (if not already present) and downloads the JDBC driver.
2. Starts the environment with a SAP HANA express container (`sap`) and waits for `Startup finished!` (up to 10 minutes).
3. Creates the SAP HANA Sink connector reading topic `testtopic` (Avro key and value), with `auto.create=true` and target table `"LOCALDEV"."TEST"`.
4. Produces 2 Avro records to `testtopic`.
5. Queries `"LOCALDEV"."TEST"` with `hdbsql` in the `sap` container and checks the rows are present.

Expected result:

```
ID,product,quantity,price
111,"foo",100,50
222,"bar",100,50
```
