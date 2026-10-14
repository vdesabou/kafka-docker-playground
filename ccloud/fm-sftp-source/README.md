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
