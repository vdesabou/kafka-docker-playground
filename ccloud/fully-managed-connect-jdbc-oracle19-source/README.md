# Fully Managed Oracle Database Source (JDBC) (Oracle 19c) Source connector

## Objective

Quickly test [Fully Managed Oracle Database Source (JDBC) Connector](https://docs.confluent.io/cloud/current/connectors/cc-oracle-db-source.html) with Oracle 19c.

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

Download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip`from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in `./LINUX.X64_193000_db_home.zip`


Note: The first time you'll run the script, it will build (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the docker image `oracle/database:19.3.0-ee`. It takes about 10 minutes.

## Exposing docker container over internet

**🚨WARNING🚨** It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using [Ngrok](https://ngrok.com). It is strongly encouraged to run it on a AWS EC2 instance where you'll use [Confluent Static Egress IP Addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using EC2 Security Group.

Example in order to set EC2 Security Group with Confluent Static Egress IP Addresses and port 1521:

```bash
group=$(aws ec2 describe-instances --instance-id <$ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1521 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1521 --cidr 13.36.88.89/32
etc...
```

An [Ngrok](https://ngrok.com) auth token is necessary in order to expose the Docker Container port to internet, so that fully managed connector can reach it.

You can sign up at https://dashboard.ngrok.com/signup
If you have already signed up, make sure your auth token is setup by exporting environment variable `NGROK_AUTH_TOKEN`

Your auth token is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken

Ngrok web interface available at http://localhost:4551

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2` for aws, `westeurope`for azure and `europe-west2` for gcp)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `txxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `txxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)


## How to run

```
$ just use <playground run>
```