# Datagen Source connector


## Objective

Quickly test [Datagen Source](https://docs.confluent.io/kafka-connect-datagen/current/index.html) connector.


## How to run

Simply run:

```
$ playground run -f datagen-source<tab>
```

## Details of what the script is doing


Create topic orders:

```bash
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "orders",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "10000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/orders.avro",
                "schema.keyfield" : "orderid"
            }' \
      http://localhost:8083/connectors/datagen-orders/config | jq
```

Create topic shipments:

```bash
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "shipments",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "10000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/shipments.avro"
            }' \
      http://localhost:8083/connectors/datagen-shipments/config | jq
```

Create topic products:

```bash
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "products",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "100",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/products.avro",
                "schema.keyfield" : "productid"
            }' \
      http://localhost:8083/connectors/datagen-products/config | jq
```

Create topic customers:

```bash
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "customers",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "1000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/customers.avro",
                "schema.keyfield" : "customerid"
            }' \
      http://localhost:8083/connectors/datagen-customers/config | jq
```

Verify we have received the data in orders topic:

```bash
playground topic consume --topic orders --min-expected-messages 1
```

Verify we have received the data in shipments topic:

```bash
playground topic consume --topic shipments --min-expected-messages 1
```

Verify we have received the data in customers topic:

```bash
playground topic consume --topic customers --min-expected-messages 1
```

Verify we have received the data in products topic:

```bash
playground topic consume --topic products --min-expected-messages 1
```

Results:

```
Verify we have received the data in orders topic:
{"ordertime":1643187141000,"orderid":0,"productid":"Product_8","orderunits":0,"order_category":"train","customerid":"Customer_1797"}
Processed a total of 1 messages
Verify we have received the data in shipments topic:
{"shipment_time":1643187141000,"shipmentid":0,"orderid":0,"productid":"Product_164","customerid":"Customer_8"}
Processed a total of 1 messages
Verify we have received the data in customers topic:
{"customerid":"Customer_3","firstname":"AndySims_345324","lastname":"Nathan_126","gender":"OTHER","random_data":"jBlDSWgjgUhEWXRNWjfMWRBdXENrtGQCcEkLiujnUYAVDvoQYkPhGPjAjGdtmtzHiYnAGmxVWovVRdHsnuFOUZVFxMeQKuyqyBKuhEsKlbKFxeEivNVBIodcBxwomswFcNunSSDnhfrJVoPhJOXETF","address":{"city":"City_55","state":"State_48","zipcode":40175}}
Processed a total of 1 messages
Verify we have received the data in products topic:
{"productid":"Product_305","name":"Product_8","category":"orange","description":"pvbzvXlFljkbMObhmbXlAqnfywfzMIIpmHQOPvFmohffXJUcjJEhtmBxpyPmzLxtybeUxDRjsOuEQhkGBFZfcatBjawBycKPsAShZIJbYbRtawrlNZSvzNTdBoHzreFzOPtEnilHFSDGRrPCwHdjuF"}
Processed a total of 1 messages
````

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
