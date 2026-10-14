# Fully-Managed Debezium MariaDB source connector

## Objective

Quickly test the [Fully Managed Debezium MariaDB CDC Source](https://docs.confluent.io/cloud/current/connectors/cc-mariadb-cdc-source-debezium.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose the MariaDB port to the internet so that the fully managed connector can reach it ([sign up](https://dashboard.ngrok.com/signup), [get your token](https://dashboard.ngrok.com/get-started/your-authtoken)) |
| `SQL_DATAGEN` | Optional. If set, builds `mysql-datagen` (from `ccloud/fm-debezium-mysql-v2-source`) and injects data for 10 minutes at the end of the run |

### Exposing docker container over internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on an AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using an EC2 Security Group.

Example to set an EC2 Security Group with Confluent Static Egress IP Addresses and port 3306:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 3306 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 3306 --cidr 13.36.88.89/32
# etc...
```

The Ngrok web interface is available at http://localhost:4040.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fully-managed-debezium-mariadb.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-debezium-mariadb.sh` | CDC of table `mydb.team` from a local MariaDB, Avro output |

## What the script does

1. Starts MariaDB and ngrok locally (`docker-compose.yml`).
2. Creates table `mydb.team` and inserts 2 rows.
3. Creates the fully managed `MariaDbCdcSource` connector (`topic.prefix` `mariadb`, `table.include.list` `mydb.team`, Avro output) pointing to the ngrok endpoint.
4. Verifies at least 2 records in topic `mariadb.mydb.team` with `playground topic consume`.
5. Deletes the connector at the end of the run.
