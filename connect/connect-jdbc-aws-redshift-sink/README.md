# JDBC AWS Redshift sink connector

## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html) connector with AWS Redshift.

## How to run

Simply run:

```bash
$ playground run -f redshift-jdbc-sink<tab>
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

Creating JDBC AWS Redshift source connector:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://'"$CLUSTER"':'"$PORT"'/dev?user=masteruser&password=myPassword1&ssl=false",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "orders",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/redshift-jdbc-sink/config | jq .
```

Verifying topic `redshift-customers`

```bash
playground topic consume --topic redshift-customers --min-expected-messages 5
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
