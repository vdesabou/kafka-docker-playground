# JDBC MySQL Sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with MySQL, using MySQL Connector/J 8.4.0.

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the scripts exit with code 111 otherwise).

## How to run

```bash
playground run -f mysql-sink.sh
```

| Script | Description |
| --- | --- |
| `mysql-sink.sh` | No SSL (`useSSL=false`) |
| `mysql-sink-ssl.sh` | SSL encryption: user `userssl` requires SSL, server certificate verified with a truststore |
| `mysql-sink-mtls.sh` | SSL encryption + mutual TLS: user `usermtls`, client certificate provided with a keystore |

## What the script does

1. Downloads `mysql-connector-j-8.4.0.jar` if needed and copies it into the JDBC connector `lib` folder.
2. SSL / mTLS variants only: starts the `mysql` container first, copies its generated `ca.pem`, `client-cert.pem` and `client-key.pem`, and converts them into `security/truststore.jks` and `security/keystore.jks`.
3. Starts the environment and creates the sink connector (`mysql-sink`, `mysql-ssl-sink` or `mysql-mtls-sink`) on topic `orders` with `auto.create=true`.
4. Produces 2 Avro records to topic `orders` with `playground topic produce`.
5. Describes and selects the `orders` table with the `mysql` client and checks that the `foo` row is present.
