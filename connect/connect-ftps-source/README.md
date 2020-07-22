# FTPS Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-ftps-source/asciinema.gif?raw=true)

## Objective

Quickly test [FTPS Source](https://docs.confluent.io/current/connect/kafka-connect-ftps/source/index.html#ftps-source-connector-for-cp) connector.



## How to run


Simply run:

```bash
$ ./ftps-source-json.sh
```


## Details of what the script is doing

Creating JSON file with schema FTPS Source connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.ftps.FtpsSourceConnector",
               "ftps.behavior.on.error":"LOG",
               "ftps.input.path": "/input",
               "ftps.error.path": "/error",
               "ftps.finished.path": "/finished",
               "ftps.input.file.pattern": "json-ftps-source.json",
               "ftps.username":"bob",
               "ftps.password":"test",
               "ftps.host":"ftps-server",
               "ftps.port":"220",
               "ftps.security.mode": "EXPLICIT",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "ftps.ssl.truststore.location": "/etc/kafka/secrets/kafka.ftps-server.truststore.jks",
               "ftps.ssl.truststore.password": "confluent",
               "ftps.ssl.keystore.location": "/etc/kafka/secrets/kafka.ftps-server.keystore.jks",
               "ftps.ssl.key.password": "confluent",
               "ftps.ssl.keystore.password": "confluent",
               "kafka.topic": "ftps-testing-topic",
               "schema.generation.enabled": "false",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "key.schema": "{\"name\" : \"com.example.users.UserKey\",\"type\" : \"STRUCT\",\"isOptional\" : false,\"fieldSchemas\" : {\"id\" : {\"type\" : \"INT64\",\"isOptional\" : false}}}",
               "value.schema": "{\"name\" : \"com.example.users.User\",\"type\" : \"STRUCT\",\"isOptional\" : false,\"fieldSchemas\" : {\"id\" : {\"type\" : \"INT64\",\"isOptional\" : false},\"first_name\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"last_name\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"email\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"gender\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"ip_address\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"last_login\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"account_balance\" : {\"name\" : \"org.apache.kafka.connect.data.Decimal\",\"type\" : \"BYTES\",\"version\" : 1,\"parameters\" : {\"scale\" : \"2\"},\"isOptional\" : true},\"country\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"favorite_color\" : {\"type\" : \"STRING\",\"isOptional\" : true}}}"
          }' \
     http://localhost:8083/connectors/ftps-source-json/config | jq .
```

Verifying topic `ftps-testing-topic`:

```bash
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ftps-testing-topic --from-beginning --max-messages 2
```

Results:

```json
{"id":1,"first_name":{"string":"Roscoe"},"last_name":{"string":"Brentnall"},"email":{"string":"rbrentnall0@mediafire.com"},"gender":{"string":"Male"},"ip_address":{"string":"202.84.142.254"},"last_login":{"string":"2018-02-12T06:26:23Z"},"account_balance":{"bytes":"\u00026¬"},"country":{"string":"CZ"},"favorite_color":{"string":"#4eaefa"}}
{"id":2,"first_name":{"string":"Gregoire"},"last_name":{"string":"Fentem"},"email":{"string":"gfentem1@nsw.gov.au"},"gender":{"string":"Male"},"ip_address":{"string":"221.159.106.63"},"last_login":{"string":"2015-03-27T00:29:56Z"},"account_balance":{"bytes":"\u0002\u001Få"},"country":{"string":"ID"},"favorite_color":{"string":"#e8f686"}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
