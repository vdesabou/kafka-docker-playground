# Fully Managed Oracle CDC Source (Oracle 19c) Source connector

## Objective

Quickly test the [Fully Managed Oracle CDC Source](https://docs.confluent.io/cloud/current/connectors/cc-oracle-cdc-source/index.html) connector with Oracle 19c (CDB, table in `CDB$ROOT`).

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose the Oracle port to the internet (see below) |
| `SQL_DATAGEN` | Optional. If set, builds `oracle-datagen` and injects data for 10 minutes at the end of the run |

### Oracle image

Confluent employees get a prebuilt Oracle image from the playground S3 bucket automatically (requires AWS credentials).
Otherwise, download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in `./LINUX.X64_193000_db_home.zip`.
The first time you run the script, it builds the docker image `oracle/database:19.3.0-ee` using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md). It takes about 10 minutes.

### Exposing docker container over internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

Example to set an EC2 Security Group with Confluent Static Egress IP Addresses and port 1521:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1521 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1521 --cidr 13.36.88.89/32
# etc...
```

Sign up at https://dashboard.ngrok.com/signup. Your auth token is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken

The Ngrok web interface is available at http://localhost:4040.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fully-managed-cdc-oracle19-cdb-table.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-cdc-oracle19-cdb-table.sh` | Oracle 19c, common user `C##MYUSER`, table `CUSTOMERS` in the CDB |

## What the script does

1. Gets or builds the Oracle 19c image, then starts Oracle and ngrok locally (`docker-compose.yml`).
2. Creates the `C##CDC_PRIVS` role and the `C##MYUSER` user, enables supplemental logging, and runs the [`oracle-readiness.sql`](https://docs.confluent.io/cloud/current/connectors/cc-oracle-cdc-source/oracle-cdc-setup-includes/prereqs-validation.html#automated-readiness-check) check.
3. Creates table `CUSTOMERS` with 5 rows.
4. Creates the fully managed `OracleCdcSource` connector (`start.from` `snapshot`, Avro key and value) pointing to the ngrok endpoint.
5. Inserts, updates and deletes rows, then alters the table (adds column `country`) and updates rows again.
6. Verifies 13 records in `ORCLCDB.C__MYUSER.CUSTOMERS` and 14 in `redo-log-topic` with `playground topic consume`.
7. Deletes the connector at the end of the run.
