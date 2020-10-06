# AWS Redshift Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-aws-redshift-sink/asciinema.gif?raw=true)

## Objective

Quickly test [AWS Redshift](https://docs.confluent.io/current/connect/kafka-connect-aws-redshift/index.html#kconnect-long-aws-redshift-sink-connector) connector.


## How to run

Simply run:

```bash
$ ./redshift.sh
```

## Details of what the script is doing

Create AWS Redshift cluster

```bash
$ aws redshift create-cluster --cluster-identifier playgroundcluster --master-username masteruser --master-user-password myPassword1 --node-type dc2.large --cluster-type single-node --publicly-accessible
```

Create a security group

```bash
$ GROUP_ID=$(aws ec2 create-security-group --group-name redshiftplaygroundcluster --description "playground aws redshift" | jq -r .GroupId)
```

Allow ingress traffic from public ip on port 5439

```bash
$ aws ec2 authorize-security-group-ingress --group-id $GROUP_ID --protocol tcp --port 5439 --cidr $PUBLIC_IP/24
```

Modify AWS Redshift cluster to use the security group

```bash
$ aws redshift modify-cluster --cluster-identifier playgroundcluster --vpc-security-group-ids $GROUP_ID
```

Getting cluster URL

```bash
$ CLUSTER=$(aws redshift describe-clusters --cluster-identifier playgroundcluster | jq -r .Clusters[0].Endpoint.Address)
```

Sending messages to topic `orders`

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```


Creating AWS Redshift Logs Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.aws.redshift.RedshiftSinkConnector",
                    "tasks.max": "1",
                    "topics": "orders",
                    "aws.redshift.domain": "'"$CLUSTER"'",
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
$ docker run -i debezium/postgres:10 psql -h $CLUSTER -U masteruser -d dev -p 5439 << EOF
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


Delete AWS Redshift cluster

```bash
$ aws redshift delete-cluster --cluster-identifier playgroundcluster --skip-final-cluster-snapshot
```

Delete security group

```bash
$ aws ec2 delete-security-group --group-name redshiftplaygroundcluster
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
