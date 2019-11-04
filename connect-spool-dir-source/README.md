# Spool Dir Source connector

## Objective

Quickly test [Spool Dir Source](https://docs.confluent.io/current/connect/kafka-connect-spooldir/index.html#kconnect-long-spool-dir-connectors) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)

## How to run

Simply run:

```
$ ./csv.sh
```

## Details of what the script is doing

### CSV with Schema Example


Generating data

```bash
$ curl "https://api.mockaroo.com/api/58605010?count=1000&key=25fd9c80" > "${DIR}/data/input/csv-spooldir-source.csv"
```

Creating CSV Spool Dir Source connector

```bash
$ docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "CsvSchemaSpoolDir5",
               "config": {
                    "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": "csv-spooldir-source.csv",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "spooldir-testing-topic",
                    "csv.first.row.as.header": "true",
                    "key.schema": "{\n  \"name\" : \"com.example.users.UserKey\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    }\n  }\n}",
                    "value.schema": "{\n  \"name\" : \"com.example.users.User\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    },\n    \"first_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"email\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"gender\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"ip_address\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_login\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"account_balance\" : {\n      \"name\" : \"org.apache.kafka.connect.data.Decimal\",\n      \"type\" : \"BYTES\",\n      \"version\" : 1,\n      \"parameters\" : {\n        \"scale\" : \"2\"\n      },\n      \"isOptional\" : true\n    },\n    \"country\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"favorite_color\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    }\n  }\n}"
          }}' \
     http://localhost:8083/connectors | jq .
```


Verify we have received the data in `spooldir-testing-topic` topic

```bash
$ docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic spooldir-testing-topic --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 10
```

Results:

```json
{"id":1,"first_name":{"string":"Tommie"},"last_name":{"string":"Leicester"},"email":{"string":"tleicester0@xinhuanet.com"},"gender":{"string":"Female"},"ip_address":{"string":"25.110.5.90"},"last_login":{"string":"2017-04-24T17:32:35Z"},"account_balance":{"bytes":"\u0019\u001DG"},"country":{"string":"SE"},"favorite_color":{"string":"#7b1de9"}}
{"id":2,"first_name":{"string":"Gard"},"last_name":{"string":"Wilfing"},"email":{"string":"gwilfing1@blogtalkradio.com"},"gender":{"string":"Male"},"ip_address":{"string":"234.93.218.137"},"last_login":{"string":"2018-07-25T18:47:37Z"},"account_balance":{"bytes":"\u0011"},"country":{"string":"CN"},"favorite_color":{"string":"#727052"}}
{"id":4,"first_name":{"string":"Erhart"},"last_name":{"string":"Roseveare"},"email":{"string":"eroseveare3@slashdot.org"},"gender":{"string":"Male"},"ip_address":{"string":"206.110.62.252"},"last_login":{"string":"2016-01-13T11:36:54Z"},"account_balance":{"bytes":"$iï"},"country":{"string":"BR"},"favorite_color":{"string":"#900e29"}}
{"id":5,"first_name":{"string":"Farleigh"},"last_name":{"string":"Aluard"},"email":{"string":"faluard4@gov.uk"},"gender":{"string":"Male"},"ip_address":{"string":"142.209.12.43"},"last_login":{"string":"2017-11-28T10:36:59Z"},"account_balance":{"bytes":"%\u0014\u0016"},"country":{"string":"GA"},"favorite_color":{"string":"#a96a2e"}}
{"id":6,"first_name":{"string":"Alene"},"last_name":{"string":"Bootman"},"email":{"string":"abootman5@wp.com"},"gender":{"string":"Female"},"ip_address":{"string":"230.45.17.178"},"last_login":{"string":"2016-09-28T22:14:32Z"},"account_balance":{"bytes":"\u0002~M"},"country":{"string":"ES"},"favorite_color":{"string":"#c23257"}}
{"id":7,"first_name":{"string":"Lusa"},"last_name":{"string":"Plenderleith"},"email":{"string":"lplenderleith6@jimdo.com"},"gender":{"string":"Female"},"ip_address":{"string":"236.137.26.123"},"last_login":{"string":"2018-11-19T20:07:44Z"},"account_balance":{"bytes":"%ç"},"country":{"string":"IT"},"favorite_color":{"string":"#fe099f"}}
{"id":8,"first_name":{"string":"Guglielmo"},"last_name":{"string":"McKag"},"email":{"string":"gmckag7@berkeley.edu"},"gender":{"string":"Male"},"ip_address":{"string":"92.231.50.143"},"last_login":{"string":"2017-05-07T08:37:42Z"},"account_balance":{"bytes":"\u0006Ä¹"},"country":{"string":"CN"},"favorite_color":{"string":"#ffe2fc"}}
{"id":9,"first_name":{"string":"Israel"},"last_name":{"string":"Lenoir"},"email":{"string":"ilenoir8@weather.com"},"gender":{"string":"Male"},"ip_address":{"string":"189.220.152.49"},"last_login":{"string":"2016-05-16T16:50:29Z"},"account_balance":{"bytes":"\u0014Ô¬"},"country":{"string":"US"},"favorite_color":{"string":"#08858e"}}
{"id":10,"first_name":{"string":"Roby"},"last_name":{"string":"Meeland"},"email":{"string":"rmeeland9@sitemeter.com"},"gender":{"string":"Female"},"ip_address":{"string":"158.132.62.74"},"last_login":{"string":"2018-11-26T20:28:57Z"},"account_balance":{"bytes":"\u000B=ì"},"country":{"string":"DK"},"favorite_color":{"string":"#0cd765"}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
