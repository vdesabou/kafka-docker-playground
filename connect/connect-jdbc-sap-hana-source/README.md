# JDBC SAP HANA Source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with SAP HANA Express (`saplabs/hanaexpress`), using the SAP HANA JDBC driver (`ngdbc` 2.12.9).

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f sap-hana-source.sh
```

| Script | Description |
| --- | --- |
| `sap-hana-source.sh` | JDBC source in `incrementing` mode on a SAP HANA table |

## What the script does

1. Downloads `ngdbc-2.12.9.jar` if needed and copies it into the JDBC connector `lib` folder.
2. Starts SAP HANA Express alongside the plaintext environment and waits for `Startup finished!`.
3. Creates the `LOCALDEV` user (idempotent: in the CFK environment the `post_start` hooks are not mounted).
4. Creates the `CUSTOMERS` column table (identity `ID`) and inserts one row with `hdbsql`.
5. Creates the `jdbc-sap-hana-source` connector (`mode=incrementing` on `ID`, `topic.prefix=sap-hana-`).
6. Verifies that the record lands in topic `sap-hana-CUSTOMERS` with `playground topic consume`.
