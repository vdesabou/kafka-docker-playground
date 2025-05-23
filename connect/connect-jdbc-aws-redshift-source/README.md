# JDBC AWS Redshift source connector

## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html) connector with AWS Redshift.

## How to run

Simply run:

```bash
$ just use <playground run> command and search for redshift-jdbc-source.sh in this folder
```
## Details of what the script is doing

Create AWS Redshift cluster

```bash
$ aws redshift create-cluster --cluster-identifier $CLUSTER_NAME --master-username masteruser --master-user-password myPassword1 --node-type dc2.large --cluster-type single-node --publicly-accessible --tags "Key=cflt_managed_by,Value=user Key=cflt_managed_id,Value="$USER""
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
$ CLUSTER=$(aws redshift describe-clusters --cluster-identifier $CLUSTER_NAME | jq -r '.Clusters[0].Endpoint.Address')
```

Create database in Redshift:

```bash
docker run -i -e CLUSTER="$CLUSTER" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:15-alpine psql -h "$CLUSTER" -U "masteruser" -d "dev" -p "5439" -f "/tmp/customers.sql" << EOF
myPassword1
EOF
```

Verify data is in Redshift:

```bash
docker run -i -e CLUSTER="$CLUSTER" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:15-alpine psql -h "$CLUSTER" -U "masteruser" -d "dev" -p "5439" << EOF
myPassword1
SELECT * from CUSTOMERS;
EOF
```

Creating JDBC AWS Redshift source connector:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                "tasks.max": "1",
                "connection.url": "jdbc:redshift://$CLUSTER:$PORT/dev?user=masteruser&password=myPassword1&ssl=false",
                "table.whitelist": "customers",
                "mode": "timestamp+incrementing",
                "timestamp.column.name": "update_ts",
                "incrementing.column.name": "id",
                "topic.prefix": "redshift-",
                "validate.non.null":"false",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/redshift-jdbc-source/config | jq .
```

Verifying topic `redshift-customers`

```bash
playground topic consume --topic redshift-customers --min-expected-messages 5 --timeout 60
```

Result is:

```json
{
    "club_status": {
        "string": "bronze"
    },
    "comments": {
        "string": "Universal optimal hierarchy"
    },
    "create_ts": {
        "long": 1580230824909
    },
    "email": {
        "string": "rblaisdell0@rambler.ru"
    },
    "first_name": {
        "string": "Rica"
    },
    "gender": {
        "string": "Female"
    },
    "id": 1,
    "last_name": {
        "string": "Blaisdell"
    },
    "update_ts": {
        "long": 1580230824909
    }
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
