# Debezium MongoDB source connector (using Confluent Cloud)

## Objective

Quickly test [Debezium MongoDB](https://docs.confluent.io/current/connect/debezium-connect-mongodb/index.html#quick-start) connector using Confluent Cloud.

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

```
$ playground run -f mongo<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Note: topic `dbserver1.inventory.customers`must be created manually as `auto.create.topics.enable` is set to `false`with Confluent Cloud.

Initialize MongoDB replica set

```bash
$ docker exec -i mongodb mongosh --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'
```

Note: `mongodb:27017`is important here

Create a user profile

```bash
$ docker exec -i mongodb mongosh << EOF
use admin
db.createUser(
{
user: "debezium",
pwd: "dbz",
roles: ["dbOwner"]
}
)
```

Insert a record

```bash
$ docker exec -i mongodb mongosh << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF
```

View the record

```bash
$ docker exec -i mongodb mongosh << EOF
use inventory
db.customers.find().pretty();
EOF
```

Create the connector:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
               "tasks.max" : "1",
               "mongodb.hosts" : "debezium/mongodb:27017",
               "mongodb.name" : "dbserver1",
               "mongodb.user" : "debezium",
               "mongodb.password" : "dbz"
          }' \
     http://localhost:8083/connectors/debezium-mongodb-source/config | jq .
```

Verifying topic dbserver1.inventory.customers

```bash
playground topic consume --topic dbserver1.inventory.customers --min-expected-messages 1 --timeout 60
```

Result is:

```json
{
    "after": {
        "string": "{\"_id\": 1006.0,\"first_name\": \"Bob\",\"last_name\": \"Hopper\",\"email\": \"thebob@example.com\"}"
    },
    "op": {
        "string": "r"
    },
    "patch": null,
    "source": {
        "collection": "customers",
        "connector": "mongodb",
        "db": "inventory",
        "h": {
            "long": 0
        },
        "name": "dbserver1",
        "ord": 2,
        "rs": "debezium",
        "snapshot": {
            "string": "last"
        },
        "tord": null,
        "ts_ms": 1582023670000,
        "version": "1.0.0.Final"
    },
    "ts_ms": {
        "long": 1582023675042
    }
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
