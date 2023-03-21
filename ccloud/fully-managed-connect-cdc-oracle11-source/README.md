# Fully Managed Oracle CDC Source (Oracle 11) Source connector

## Objective

Quickly test [Oracle CDC Source Connector](https://docs.confluent.io/kafka-connect-oracle-cdc/current/) with Oracle 11.

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


## Note on `redo.log.row.fetch.size`

The connector is configured with `"redo.log.row.fetch.size":1` for demo purpose only. If you're planning to inject more data, it is recommended to increase the value.

Example with included script [`07_generate_customers.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/sample-sql-scripts/07_generate_customers.sh.zip) (packaged as `.zip`in order to not be run automatically), which inserts around 7000 customer rows, in that case you would need to set `"redo.log.row.fetch.size":1000`:

```
cd sample-sql-scripts
unzip 07_generate_customers.sh.zip 
cd -
# insert new customer every 500ms
./sample-sql-scripts/07_generate_customers.sh 0.5
# insert new customer every second (default)
./sample-sql-scripts/07_generate_customers.sh 
```

See screencast below:


https://user-images.githubusercontent.com/4061923/139914676-e34fae34-0f5c-4240-9690-d1d486236457.mp4


## How to run

```
$ ./fully-managed-cdc-oracle11-source.sh <NGROK_AUTH_TOKEN>
```

Note:

Using ksqlDB using CLI:

```bash
$ docker exec -i ksqldb-cli ksql http://ksqldb-server:8088
```

## Details of what the script is doing

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "XE",
               "oracle.username": "MYUSER",
               "oracle.password": "password",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1
          }' \
     http://localhost:8083/connectors/cdc-oracle11-source/config | jq .
```

Verify the topic `XE.MYUSER.CUSTOMERS`:

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic XE.MYUSER.CUSTOMERS --from-beginning --max-messages 2
```

Results:

```json
{"ID":"\u0001","FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1604047105216},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
{"ID":"\u0002","FIRST_NAME":{"string":"Ruthie"},"LAST_NAME":{"string":"Brockherst"},"EMAIL":{"string":"rbrockherst1@ow.ly"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"platinum"},"COMMENTS":{"string":"Reverse-engineered tangible interface"},"CREATE_TS":{"long":1604047105230},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
