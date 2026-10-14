# Fully Managed Oracle XStream CDC Source (Oracle 19c) Source connector

## Objective

Quickly test the [Fully Managed Oracle XStream CDC Source](https://docs.confluent.io/cloud/current/connectors/cc-oracle-xstream-cdc-source/cc-oracle-xstream-cdc-source-features.html) connector with Oracle 19c.

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose the Oracle port to the internet so that the fully managed connector can reach it ([sign up](https://dashboard.ngrok.com/signup), [get your token](https://dashboard.ngrok.com/get-started/your-authtoken)) |
| `SQL_DATAGEN` | Optional. If set, builds `oracle-datagen` and injects data for 10 minutes at the end of the run |

**🚨WARNING🚨** Exposing a TCP port over internet with ngrok is a security risk on a personal machine. Prefer an AWS EC2 instance with [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) allowed in its Security Group.

### Oracle image

Confluent employees get a prebuilt Oracle image from the playground S3 bucket automatically (requires AWS credentials).
Otherwise, download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in `./LINUX.X64_193000_db_home.zip`.
The first time you run the script, it builds the docker image `oracle/database:19.3.0-ee` using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md). It takes about 10 minutes.

**Please make sure to increase Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

For `fully-managed-cdc-xstream-oracle19-ssl-wallet.sh`, the Oracle Instant Client 19.25 zip (`instantclient_19_25_arm64.zip` or `instantclient_19_25_x86.zip`) is fetched automatically for Confluent employees; otherwise download it from [Oracle](https://www.oracle.com/in/database/technologies/instant-client/downloads.html) into this folder.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fully-managed-cdc-xstream-oracle19.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-cdc-xstream-oracle19.sh` | Basic example: snapshot, then inserts, updates, deletes and a schema change |
| `fully-managed-cdc-xstream-oracle19-blocking-snapshot.sh` | Triggers an ad-hoc blocking snapshot through the signal table `CFLT_SIGNALS` (`signal.data.collection`) |
| `fully-managed-cdc-xstream-oracle19-ssl-wallet.sh` | Oracle listener over TLS (one-way), the connector uses the server `cwallet.sso` (`database.tls.mode`, `database.wallet.file`) |

## What the script does

1. Gets or builds the Oracle 19c image, then starts Oracle and ngrok locally (the SSL variant first creates the Oracle wallets and TLS listener configuration from `ssl/`).
2. Enables XStream, ARCHIVELOG mode and supplemental logging, creates the XStream administrator and the `c##cfltuser` connect user, and creates the XStream outbound server `XOUT`.
3. Runs the [`orclcdc_readiness.sql`](https://docs.confluent.io/cloud/current/connectors/cc-oracle-xstream-cdc-source/prereqs-validation.html#validate-prerequisites-completion) check (basic and blocking-snapshot variants).
4. Creates table `CUSTOMERS` with initial rows.
5. Creates the fully managed `OracleXStreamSource` connector (Avro, `topic.prefix` `cflt`) pointing to the ngrok endpoint.
6. Runs DML (and a schema change) and verifies records in `cflt.C__CFLTUSER.CUSTOMERS` with `playground topic consume` (14 records; the blocking-snapshot variant checks 7, then 14 after the snapshot signal).
7. Deletes the connector at the end of the run.

## Troubleshooting

- `playground connector oracle-cdc-xstream generate-report` generates the Oracle XStream CDC connector diagnostics report.
- `playground connector oracle-cdc-xstream debug` runs various SQL commands to debug the XStream components.
- `playground debug oracle-xstream-analyze -c oracle` generates the report and analyzes it (findings with exact values, root-cause patterns); `-f orclcdc_diag_<date>.html` analyzes an existing report.
