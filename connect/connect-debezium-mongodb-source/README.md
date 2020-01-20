# Debezium MongoDB source connector

## Objective

Quickly test [Debezium MongoDB](https://docs.confluent.io/current/connect/debezium-connect-mongodb/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./mongo.sh
```

## Details of what the script is doing


Initialize MongoDB replica set

```bash
$ docker exec -it mongodb mongo --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'
```

Note: `mongodb:27017`is important here

Create a user profile

```bash
$ docker exec -i mongodb mongo << EOF
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
$ docker exec -i mongodb mongo << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF
```

View the record

```bash
$ docker exec -i mongodb mongo << EOF
use inventory
db.customers.find().pretty();
EOF
```

Create the connector:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
                    "tasks.max" : "1",
                    "mongodb.hosts" : "debezium/mongodb:27017",
                    "mongodb.name" : "dbserver1",
                    "mongodb.user" : "debezium",
                    "mongodb.password" : "dbz",
                    "database.history.kafka.bootstrap.servers" : "broker:9092"
          }' \
     http://localhost:8083/connectors/debezium-mongodb-source/config | jq_docker_cli .
```

Verifying topic dbserver1.inventory.customers

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1.inventory.customers --from-beginning --max-messages 1
```

Result is:

```json
{
    "after": {
        "string": "{\"_id\" : 1006.0,\"first_name\" : \"Bob\",\"last_name\" : \"Hopper\",\"email\" : \"thebob@example.com\"}"
    },
    "patch": null,
    "source": {
        "version": {
            "string": "0.9.5.Final"
        },
        "connector": {
            "string": "mongodb"
        },
        "name": "dbserver1",
        "rs": "debezium",
        "ns": "inventory.customers",
        "sec": 1570207101,
        "ord": 2,
        "h": {
            "long": 0
        },
        "initsync": {
            "boolean": true
        }
    },
    "op": {
        "string": "r"
    },
    "ts_ms": {
        "long": 1570207105641
    }
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
