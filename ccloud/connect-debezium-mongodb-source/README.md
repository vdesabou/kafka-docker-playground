# Debezium MongoDB source connector (using Confluent Cloud)

## Objective

Quickly test [Debezium MongoDB](https://docs.confluent.io/current/connect/debezium-connect-mongodb/index.html#quick-start) connector using Confluent Cloud.


## How to run

Create `$HOME/.ccloud/config`

On the host from which you are running Docker, ensure that you have properly initialized Confluent Cloud CLI and have a valid configuration file at `$HOME/.ccloud/config`.

Example:

```bash
$ cat $HOME/.ccloud/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username\="<API KEY>" password\="<API SECRET>";

// Schema Registry specific settings
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR_API_KEY>:<SR_API_SECRET>
schema.registry.url=<SR ENDPOINT>

// license
confluent.license=<YOUR LICENSE>

// ccloud login password
ccloud.user=<ccloud login>
ccloud.password=<ccloud password>
```

Simply run:

```
$ ./mongo.sh
```

## Details of what the script is doing

Note: topic `dbserver1.inventory.customers`must be created manually as `auto.create.topics.enable` is set to `false`with Confluent Cloud.

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
$ docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic dbserver1.inventory.customers --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 1'
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
