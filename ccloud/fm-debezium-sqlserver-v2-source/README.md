# Fully Managed Microsoft SQL Server CDC Source (Debezium) [v2] source connector

## Objective

Quickly test the [Fully Managed Microsoft SQL Server CDC Source (Debezium) V2](https://docs.confluent.io/cloud/current/connectors/cc-microsoft-sql-server-source-cdc-v2-debezium/cc-microsoft-sql-server-source-cdc-v2-debezium.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose the SQL Server port to the internet so that the fully managed connector can reach it ([sign up](https://dashboard.ngrok.com/signup), [get your token](https://dashboard.ngrok.com/get-started/your-authtoken)) |

### Exposing docker container over internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

Example to set an EC2 Security Group with Confluent Static Egress IP Addresses and port 1433:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1433 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1433 --cidr 13.36.88.89/32
# etc...
```

The Ngrok web interface is available at http://localhost:4040.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fully-managed-debezium-v2-sqlserver-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-debezium-v2-sqlserver-source.sh` | CDC of table `testDB.dbo.customers` from a local SQL Server 2019, Avro output |
| `fully-managed-debezium-v2-sqlserver-source-ssl.sh` | Same with encryption: SQL Server uses a self-signed certificate, the connector gets the truststore inline (`database.encrypt`, `database.truststore`) |

With `--enable-sql-datagen` (`playground run -f fully-managed-debezium-v2-sqlserver-source.sh --enable-sql-datagen`), once the example succeeded, `playground run` injects rows in the `dbo.customers` table with [`benchmark-load.bash`](benchmark-load.bash) (the same load as `playground connector benchmark`) for 10 minutes: one row per transaction, from 5 parallel sessions, logging the rows inserted every 30 seconds. `SQL_DATAGEN_DURATION` (minutes, default `10`) and `SQL_DATAGEN_SESSIONS` (default `5`) change the duration and the number of sessions.

## What the script does

1. The SSL variant first generates a self-signed certificate and a JKS truststore in `ssl/`.
2. Starts SQL Server and ngrok locally (`docker-compose.yml` or `docker-compose-ssl.yml`) and waits for SQL Server to be ready.
3. Creates database `testDB`, enables CDC on it, creates table `customers` with 4 rows and enables CDC on the table.
4. Creates the fully managed `SqlServerCdcSourceV2` connector (`topic.prefix` `server1`, `table.include.list` `dbo.customers`, Avro output) pointing to the ngrok endpoint.
5. Verifies records in topic `server1.testDB.dbo.customers` with `playground topic consume`.
6. Deletes the connector at the end of the run.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the same load as the self-managed example [`connect-debezium-sqlserver-source`](../../connect/connect-debezium-sqlserver-source/README.md#benchmark): it loads rows in the `customers` table for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to capture 100k rows inserted in one transaction
playground connector benchmark --nb-records 100000 --shape bulk

# 10k transactions of one row
playground connector benchmark --nb-records 10000 --shape small-txn
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
