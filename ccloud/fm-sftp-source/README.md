# Fully Managed SFTP Source connector

## Objective

Quickly test the [SFTP Source](https://docs.confluent.io/cloud/current/connectors/cc-sftp-source.html) fully managed connector, against a local SFTP server exposed through ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | [ngrok](https://ngrok.com) auth token, used to expose the local container to the fully managed connector. Sign up at https://dashboard.ngrok.com/signup, the token is on https://dashboard.ngrok.com/get-started/your-authtoken |

## Exposing Docker containers over the internet

> [!WARNING]
> Running this example on your personal machine exposes a TCP port to the internet through [ngrok](https://ngrok.com), which is a security risk. Prefer an AWS EC2 instance, and allow only the [Confluent Cloud static egress IP addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (public endpoints on AWS only) in the EC2 security group.

Example to open port 22 to the Confluent static egress IP addresses:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq -r '.Reservations[] | .Instances[] | .SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 22 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 22 --cidr 13.36.88.89/32
# etc. for every static egress IP address of your region
```

The ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-sftp-source-csv.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-sftp-source-csv.sh` | CSV file with header row (`input.file.parser.format=CSV`), JSON output |
| `fully-managed-sftp-source-json.sh` | JSON file (`input.file.parser.format=JSON`), JSON output |

## What the script does

1. Bootstraps the Confluent Cloud environment and deletes topic `sftp-testing-topic`.
2. Starts the SFTP server and ngrok locally, creates the `input`, `error` and `finished` folders under `/home/foo/upload` and copies a 2-record CSV or JSON file into `input`.
3. Creates the fully managed `SftpSource` connector with schema generation enabled.
4. Verifies the 2 records with `playground topic consume --topic sftp-testing-topic`.
5. Asks whether to delete the connector.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-sftp-source`](../../connect/connect-sftp-source/README.md#benchmark): it loads CSV or JSON files in the input directory of the SFTP server for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to read a backlog of 100k records
playground connector benchmark --nb-records 100000
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
