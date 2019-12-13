# MongoDB sink connector

## Objective

Quickly test [MongoDB](https://docs.mongodb.com/ecosystem/connectors/kafka/) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)


## How to run

Simply run:

```
$ ./mongo-sink.sh
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
               "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
                    "database":"inventory",
                    "collection":"customers",
                    "topics":"orders"
          }' \
     http://localhost:8083/connectors/mongodb-sink/config | jq .
```

Sending messages to topic `orders`

```bash
$ docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

View the record

```bash
$ docker exec -i mongodb mongo << EOF
use inventory
db.customers.find().pretty();
EOF
```

Result is:

```
MongoDB shell version v4.2.0
connecting to: mongodb://127.0.0.1:27017/?compressors=disabled&gssapiServiceName=mongodb
Implicit session: session { "id" : UUID("c82866ce-e000-43ea-82e2-5f0d7da22cb3") }
MongoDB server version: 4.2.0
switched to db inventory
{
        "_id" : ObjectId("5defb320169c4051ecbb50bf"),
        "id" : 999,
        "product" : "foo",
        "quantity" : 100,
        "price" : 50
}
bye
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
