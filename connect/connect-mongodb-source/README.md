# MongoDB source connector

## Objective

Quickly test [MongoDB](https://docs.mongodb.com/ecosystem/connectors/kafka/) connector.

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
$ docker exec -it mongodb mongo --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'
```

Note: `mongodb:27017`is important here

Create a user profile

```bash
$ docker exec -i mongodb mongo << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
```

Create the connector:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
                    "database":"inventory",
                    "collection":"customers",
                    "topic.prefix":"mongo"
          }' \
     http://localhost:8083/connectors/mongodb-source/config | jq .
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

Verifying topic `mongo.inventory.customers`:

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mongo.inventory.customers --from-beginning --max-messages 1
```

Result is:

```json
"{\"_id\": {\"_data\": \"825DEFAD7F000000022B022C0100296E5A100464FD9F727D5D40EC96C7C03D3B636406461E5F6964002B020004\", \"_typeBits\": {\"$binary\": \"QA==\", \"$type\": \"00\"}}, \"operationType\": \"insert\", \"clusterTime\": {\"$timestamp\": {\"t\": 1575988607, \"i\": 2}}, \"fullDocument\": {\"_id\": 1.0, \"first_name\": \"Bob\", \"last_name\": \"Hopper\", \"email\": \"thebob@example.com\"}, \"ns\": {\"db\": \"inventory\", \"coll\": \"customers\"}, \"documentKey\": {\"_id\": 1.0}}"
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
