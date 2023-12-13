# AWS Redshift Sink connector with Confluent Cloud.

## Objective

Quickly test [AWS Redshift](https://docs.confluent.io/current/connect/kafka-connect-aws-redshift/index.html#kconnect-long-aws-redshift-sink-connector) connector with Confluent Cloud.

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)


## How to run

Simply run:

```bash
$ playground run -f redshift<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

## Details of what the script is doing

Create AWS Redshift cluster

```bash
$ aws redshift create-cluster --cluster-identifier $CLUSTER_NAME --master-username masteruser --master-user-password myPassword1 --node-type dc2.large --cluster-type single-node --publicly-accessible
```

Create a security group

```bash
GROUP_ID=$(aws ec2 create-security-group --group-name sg$CLUSTER_NAME --description "playground aws redshift" | jq -r .GroupId)
```

Allow ingress traffic from 0.0.0.0/0 on port 5439

```bash
aws ec2 authorize-security-group-ingress --group-id $GROUP_ID --protocol tcp --port 5439 --cidr "0.0.0.0/0"
```

Modify AWS Redshift cluster to use the security group $GROUP_ID

```bash
aws redshift modify-cluster --cluster-identifier $CLUSTER_NAME --vpc-security-group-ids $GROUP_ID
```

Getting cluster URL

```bash
$ CLUSTER=$(aws redshift describe-clusters --cluster-identifier $CLUSTER_NAME | jq -r .Clusters[0].Endpoint.Address)
```

Sending messages to topic `orders`

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Creating AWS Redshift Sink connector with cluster url $CLUSTER

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.aws.redshift.RedshiftSinkConnector",
               "tasks.max": "1",
               "topics": "orders",
               "aws.redshift.domain": "$CLUSTER",
               "aws.redshift.port": "5439",
               "aws.redshift.database": "dev",
               "aws.redshift.user": "masteruser",
               "aws.redshift.password": "myPassword1",
               "auto.create": "true",
               "pk.mode": "kafka",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/redshift-sink/config | jq .
```

Verify data is in Redshift

```bash
$ docker run -i debezium/postgres:15-alpine psql -h $CLUSTER -U masteruser -d dev -p 5439 << EOF
myPassword1
SELECT * from orders;
EOF
```

Results:

```
 __connect_topic |             product             | quantity | __connect_partition | __connect_offset | price | id
-----------------+---------------------------------+----------+---------------------+------------------+-------+-----
 orders          | foo                             |      100 |                   0 |                0 |    50 | 999
(1 rows)
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
