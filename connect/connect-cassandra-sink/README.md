# Cassandra Sink connector



## Objective

Quickly test [Cassandra Sink](https://docs.confluent.io/current/connect/kafka-connect-cassandra/index.html#kconnect-long-cassandra-sink-connector) connector.

Cassandra `3.0` is used.




## How to run

Simply run:

```
$ playground run -f cassandra<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

## Details of what the script is doing

Getting value for cassandra.local.datacenter (2.0.x only), see https://docs.confluent.io/kafka-connect-cassandra/current/index.html#upgrading-to-version-2-0-x

```bash
DATACENTER=$(docker exec cassandra cqlsh -e 'SELECT data_center FROM system.local;' | head -4 | tail -1 | tr -d ' ')
```

Sending messages to topic topic1

```bash
$ playground topic produce -t topic1 --nb-messages 10 --forced-value '{"f1": "value1"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF
```

Creating Cassandra Sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.cassandra.CassandraSinkConnector",
                    "tasks.max": "1",
                    "topics" : "topic1",
                    "cassandra.contact.points" : "cassandra",
                    "cassandra.keyspace" : "test",
                    "cassandra.consistency.level": "ONE",
                    "cassandra.local.datacenter":"$DATACENTER",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "transforms": "createKey",
                    "transforms.createKey.fields": "f1",
                    "transforms.createKey.type": "org.apache.kafka.connect.transforms.ValueToKey"
          }' \
     http://localhost:8083/connectors/cassandra-sink/config | jq .
```

Verify messages are in cassandra table test.topic1

```bash
$ docker exec cassandra cqlsh -e 'select * from test.topic1;'
```

Results:

```bash
 f1
---------
  value7
  value9
  value6
  value1
  value8
  value3
  value5
  value4
  value2
 value10

(10 rows)
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
