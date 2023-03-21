# Spool Dir Source connector



## Objective

Quickly test [Spool Dir Source](https://docs.confluent.io/current/connect/kafka-connect-spooldir/index.html#kconnect-long-spool-dir-connectors) connector.


## How to run

Simply run:

```
$ ./csv.sh
```

## Details of what the script is doing

### CSV with Schema Example


Generating data

```bash
$ curl -k "https://api.mockaroo.com/api/58605010?count=1000&key=25fd9c80" > "${DIR}/data/input/csv-spooldir-source.csv"
```

Creating CSV Spool Dir Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": ".*\\.csv",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "spooldir-csv-topic",
                    "csv.first.row.as.header": "true",
                    "key.schema": "{\n  \"name\" : \"com.example.users.UserKey\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    }\n  }\n}",
                    "value.schema": "{\n  \"name\" : \"com.example.users.User\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    },\n    \"first_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"email\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"gender\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"ip_address\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_login\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"account_balance\" : {\n      \"name\" : \"org.apache.kafka.connect.data.Decimal\",\n      \"type\" : \"BYTES\",\n      \"version\" : 1,\n      \"parameters\" : {\n        \"scale\" : \"2\"\n      },\n      \"isOptional\" : true\n    },\n    \"country\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"favorite_color\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    }\n  }\n}"
          }}' \
     http://localhost:8083/connectors/spool-dir/config | jq .
```


Verify we have received the data in `spooldir-csv-topic` topic

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic spooldir-csv-topic --from-beginning --max-messages 10
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

### TSV with Schema Example


Generating data

```bash
$ curl -k "https://api.mockaroo.com/api/58605010?count=1000&key=25fd9c80" > "${DIR}/data/input/tsv-spooldir-source.csv"
```

Creating TSV Spool Dir Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": "tsv-spooldir-source.tsv",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "spooldir-tsv-topic",
                    "schema.generation.enabled": "true",
                    "csv.first.row.as.header": "true",
                    "csv.separator.char": "9"
          }' \
     http://localhost:8083/connectors/TsvSpoolDir/config | jq .
```


Verify we have received the data in `spooldir-tsv-topic` topic

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic spooldir-tsv-topic --from-beginning --max-messages 10
```

Results:

```json
{"id":{"string":"1"},"first_name":{"string":"Cherin"},"last_name":{"string":"Gouldstone"},"email":{"string":"cgouldstone0@oaic.gov.au"},"gender":{"string":"Female"},"ip_address":{"string":"221.213.199.21"},"last_login":{"string":"2019-02-04T03:12:13Z"},"account_balance":{"string":"14498.95"},"country":{"string":"HN"},"favorite_color":{"string":"#df3147"}}
{"id":{"string":"2"},"first_name":{"string":"Dominick"},"last_name":{"string":"Shout"},"email":{"string":"dshout1@ted.com"},"gender":{"string":"Male"},"ip_address":{"string":"69.26.30.103"},"last_login":{"string":"2015-05-10T12:06:59Z"},"account_balance":{"string":"2182.89"},"country":{"string":"PH"},"favorite_color":{"string":"#715bf7"}}
{"id":{"string":"3"},"first_name":{"string":"Quinton"},"last_name":{"string":"Gear"},"email":{"string":"qgear2@reverbnation.com"},"gender":{"string":"Male"},"ip_address":{"string":"6.224.5.89"},"last_login":{"string":"2016-09-19T15:22:03Z"},"account_balance":{"string":"8229.0"},"country":{"string":"LB"},"favorite_color":{"string":"#6c5fb5"}}
{"id":{"string":"4"},"first_name":{"string":"Alexia"},"last_name":{"string":"Greated"},"email":{"string":"agreated3@bravesites.com"},"gender":{"string":"Female"},"ip_address":{"string":"114.202.205.39"},"last_login":{"string":"2018-01-28T23:50:13Z"},"account_balance":{"string":"14017.36"},"country":{"string":"FR"},"favorite_color":{"string":"#b86d2a"}}
{"id":{"string":"5"},"first_name":{"string":"Demetris"},"last_name":{"string":"Beddis"},"email":{"string":"dbeddis4@spotify.com"},"gender":{"string":"Male"},"ip_address":{"string":"160.147.197.220"},"last_login":{"string":"2017-09-18T18:30:50Z"},"account_balance":{"string":"11743.29"},"country":{"string":"CN"},"favorite_color":{"string":"#6aba0d"}}
{"id":{"string":"6"},"first_name":{"string":"Corey"},"last_name":{"string":"Berthod"},"email":{"string":"cberthod5@free.fr"},"gender":{"string":"Female"},"ip_address":{"string":"104.217.93.148"},"last_login":{"string":"2016-07-16T01:31:04Z"},"account_balance":{"string":"9903.04"},"country":{"string":"CN"},"favorite_color":{"string":"#7d2cce"}}
{"id":{"string":"7"},"first_name":{"string":"John"},"last_name":{"string":"Crown"},"email":{"string":"jcrown6@time.com"},"gender":{"string":"Male"},"ip_address":{"string":"68.35.236.93"},"last_login":{"string":"2015-09-04T13:46:45Z"},"account_balance":{"string":"10531.31"},"country":{"string":"HR"},"favorite_color":{"string":"#2261b0"}}
{"id":{"string":"8"},"first_name":{"string":"Cross"},"last_name":{"string":"Dicte"},"email":{"string":"cdicte7@cnn.com"},"gender":{"string":"Male"},"ip_address":{"string":"45.252.35.236"},"last_login":{"string":"2016-12-10T13:34:53Z"},"account_balance":{"string":"8571.82"},"country":{"string":"FR"},"favorite_color":{"string":"#05e703"}}
{"id":{"string":"9"},"first_name":{"string":"Bobbi"},"last_name":{"string":"Marple"},"email":{"string":"bmarple8@quantcast.com"},"gender":{"string":"Female"},"ip_address":{"string":"242.78.128.223"},"last_login":{"string":"2016-11-07T19:22:32Z"},"account_balance":{"string":"13619.37"},"country":{"string":"ET"},"favorite_color":{"string":"#dc11b0"}}
{"id":{"string":"10"},"first_name":{"string":"Derward"},"last_name":{"string":"Gibbins"},"email":{"string":"dgibbins9@samsung.com"},"gender":{"string":"Male"},"ip_address":{"string":"39.21.71.73"},"last_login":{"string":"2018-10-28T06:53:51Z"},"account_balance":{"string":"5770.48"},"country":{"string":"PH"},"favorite_color":{"string":"#5ea97b"}}
```

### JSON with Schema Example

Generate data

```bash
$ curl -k "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > "${DIR}/data/input/json-spooldir-source.json"
```

Creating JSON Spool Dir Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirJsonSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": ".*\\.json",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "spooldir-json-topic",
                    "schema.generation.enabled": "true",
                     "key.schema": "{\n  \"name\" : \"com.example.users.UserKey\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    }\n  }\n}",
                         "value.schema": "{\n  \"name\" : \"com.example.users.User\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    },\n    \"first_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"email\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"gender\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"ip_address\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_login\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"account_balance\" : {\n      \"name\" : \"org.apache.kafka.connect.data.Decimal\",\n      \"type\" : \"BYTES\",\n      \"version\" : 1,\n      \"parameters\" : {\n        \"scale\" : \"2\"\n      },\n      \"isOptional\" : true\n    },\n    \"country\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"favorite_color\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    }\n  }\n}"

          }' \
     http://localhost:8083/connectors/spool-dir/config | jq .
```

Verify we have received the data in spooldir-json-topic topic

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic spooldir-json-topic --from-beginning --max-messages 10
```

Results:

```json
{"id":1,"first_name":{"string":"Benedick"},"last_name":{"string":"Crockford"},"email":{"string":"bcrockford0@smh.com.au"},"gender":{"string":"Male"},"ip_address":{"string":"102.230.9.216"},"last_login":{"string":"2014-09-13T20:56:29Z"},"account_balance":{"bytes":"!0"},"country":{"string":"ML"},"favorite_color":{"string":"#2a6a42"}}
{"id":2,"first_name":{"string":"Merill"},"last_name":{"string":"Reddyhoff"},"email":{"string":"mreddyhoff1@mysql.com"},"gender":{"string":"Male"},"ip_address":{"string":"91.124.205.107"},"last_login":{"string":"2017-08-12T14:03:21Z"},"account_balance":{"bytes":"!\u001D"},"country":{"string":"CN"},"favorite_color":{"string":"#86b64c"}}
{"id":3,"first_name":{"string":"Jarad"},"last_name":{"string":"Klaesson"},"email":{"string":"jklaesson2@sina.com.cn"},"gender":{"string":"Female"},"ip_address":{"string":"97.20.41.13"},"last_login":{"string":"2016-02-19T16:27:22Z"},"account_balance":{"bytes":" ÝÃ"},"country":{"string":"FI"},"favorite_color":{"string":"#70db70"}}
{"id":4,"first_name":{"string":"Amandy"},"last_name":{"string":"Duddy"},"email":{"string":"aduddy3@blogger.com"},"gender":{"string":"Male"},"ip_address":{"string":"34.69.165.52"},"last_login":{"string":"2016-10-02T12:17:04Z"},"account_balance":{"bytes":"\u0003,"},"country":{"string":"RU"},"favorite_color":{"string":"#485373"}}
{"id":5,"first_name":{"string":"Isabeau"},"last_name":{"string":"Bellenie"},"email":{"string":"ibellenie4@tiny.cc"},"gender":{"string":"Female"},"ip_address":{"string":"216.22.180.32"},"last_login":{"string":"2016-05-01T15:25:11Z"},"account_balance":{"bytes":"\r`F"},"country":{"string":"CN"},"favorite_color":{"string":"#c79e9c"}}
{"id":6,"first_name":{"string":"Dorelia"},"last_name":{"string":"Simion"},"email":{"string":"dsimion5@gravatar.com"},"gender":{"string":"Male"},"ip_address":{"string":"194.108.184.2"},"last_login":{"string":"2017-10-24T18:42:52Z"},"account_balance":{"bytes":"\u0002xä"},"country":{"string":"FR"},"favorite_color":{"string":"#9da2eb"}}
{"id":7,"first_name":{"string":"Trey"},"last_name":{"string":"Tanser"},"email":{"string":"ttanser6@ed.gov"},"gender":{"string":"Male"},"ip_address":{"string":"109.45.152.104"},"last_login":{"string":"2015-07-21T22:56:50Z"},"account_balance":{"bytes":"\u001AÔ\u001B"},"country":{"string":"CN"},"favorite_color":{"string":"#4b0618"}}
{"id":8,"first_name":{"string":"Addie"},"last_name":{"string":"Robbel"},"email":{"string":"arobbel7@eepurl.com"},"gender":{"string":"Male"},"ip_address":{"string":"189.28.111.232"},"last_login":{"string":"2016-04-05T05:34:43Z"},"account_balance":{"bytes":"\u000BáL"},"country":{"string":"CN"},"favorite_color":{"string":"#92aef9"}}
{"id":9,"first_name":{"string":"Lindy"},"last_name":{"string":"Grayshon"},"email":{"string":"lgrayshon8@umn.edu"},"gender":{"string":"Male"},"ip_address":{"string":"159.192.159.43"},"last_login":{"string":"2017-12-29T16:20:29Z"},"account_balance":{"bytes":"\u0004H-"},"country":{"string":"CN"},"favorite_color":{"string":"#166a5d"}}
{"id":10,"first_name":{"string":"Rockwell"},"last_name":{"string":"Middlemist"},"email":{"string":"rmiddlemist9@artisteer.com"},"gender":{"string":"Female"},"ip_address":{"string":"171.185.136.75"},"last_login":{"string":"2017-10-02T09:46:55Z"},"account_balance":{"bytes":"\u001F¬t"},"country":{"string":"FR"},"favorite_color":{"string":"#3040cf"}}
```

### JSON Schemaless Source Connector Example

Generating data

```bash
$ curl -k "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > "${DIR}/data/input/json-spooldir-source.json"
```

Creating JSON Spool Dir Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirSchemaLessJsonSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": ".*\\.json",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "spooldir-schemaless-json-topic",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter"
          }' \
     http://localhost:8083/connectors/spool-dir/config | jq .
```

Verify we have received the data in spooldir-schemaless-json-topic topic

```bash
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic spooldir-schemaless-json-topic --from-beginning --max-messages 10 --topic spooldir-schemaless-json-topic --from-beginning --max-messages 10
```

Results:

```json
{"id":1,"first_name":"Richy","last_name":"Slavin","email":"rslavin0@nyu.edu","gender":"Male","ip_address":"111.76.127.178","last_login":"2014-11-16T07:05:01Z","account_balance":291.19,"country":"ID","favorite_color":"#ffe1cb"}
{"id":2,"first_name":"Sisely","last_name":"Zecchini","email":"szecchini1@w3.org","gender":"Female","ip_address":"144.47.147.144","last_login":"2014-08-25T20:38:35Z","account_balance":4530.98,"country":"ID","favorite_color":"#f1d0bb"}
{"id":3,"first_name":"Innis","last_name":"Saynor","email":"isaynor2@army.mil","gender":"Male","ip_address":"140.108.208.221","last_login":"2018-09-07T23:24:02Z","account_balance":15682.39,"country":"MX","favorite_color":"#1b1168"}
{"id":4,"first_name":"Haleigh","last_name":"Blei","email":"hblei3@salon.com","gender":"Female","ip_address":"204.203.123.208","last_login":"2014-12-25T19:40:42Z","account_balance":23466.06,"country":"DO","favorite_color":"#1bdd1a"}
{"id":5,"first_name":"Teressa","last_name":"Winny","email":"twinny4@addthis.com","gender":"Female","ip_address":"111.125.49.88","last_login":"2017-10-29T00:07:43Z","account_balance":4453.82,"country":"ZW","favorite_color":"#6a7cbd"}
{"id":6,"first_name":"Michelina","last_name":"Ipsly","email":"mipsly5@hc360.com","gender":"Female","ip_address":"148.34.135.55","last_login":"2019-03-12T02:28:14Z","account_balance":6995.06,"country":"CN","favorite_color":"#bec264"}
{"id":7,"first_name":"Candida","last_name":"Saddleton","email":"csaddleton6@chronoengine.com","gender":"Female","ip_address":"135.66.188.103","last_login":"2019-03-03T19:28:50Z","account_balance":1024.69,"country":"NG","favorite_color":"#dd93f7"}
{"id":8,"first_name":"Suzette","last_name":"Pigne","email":"spigne7@reuters.com","gender":"Female","ip_address":"141.44.225.93","last_login":"2016-09-04T18:24:18Z","account_balance":13501.22,"country":"CN","favorite_color":"#b412d1"}
{"id":9,"first_name":"Imelda","last_name":"Moncarr","email":"imoncarr8@yolasite.com","gender":"Female","ip_address":"128.79.219.67","last_login":"2018-05-01T07:52:45Z","account_balance":2138.31,"country":"TN","favorite_color":"#47cc85"}
{"id":10,"first_name":"Elisha","last_name":"Stollsteimer","email":"estollsteimer9@odnoklassniki.ru","gender":"Male","ip_address":"132.220.225.250","last_login":"2018-05-12T07:44:07Z","account_balance":17464.43,"country":"MT","favorite_color":"#836ad7"}
```

### FIX Encoded Lines Example

Generating data

```bash
$ curl "https://raw.githubusercontent.com/jcustenborder/kafka-connect-spooldir/master/src/test/resources/com/github/jcustenborder/kafka/connect/spooldir/SpoolDirLineDelimitedSourceConnector/fix.json" > "${DIR}/data/input/fix.json"
```

Creating Line Delimited Spool Dir Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirLineDelimitedSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": ".*\\.json",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "fix-topic",
                    "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/spool-dir/config | jq .
```bash


Verify we have received the data in fix-topic topic

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic fix-topic --from-beginning --max-messages 100
```

Results:

```
"{"
"  \"description\" : \"This example will read files in a directory line by line and parse them using kafka-connect-transform-fix to a FIX representation of the data.\","
"  \"name\" : \"FIX encoded lines\","
"  \"config\" : {"
"    \"topic\" : \"fix\","
"    \"input.path\" : \"/tmp\","
"    \"input.file.pattern\" : \"^.+\\\\.fix$\","
"    \"error.path\" : \"/tmp\","
"    \"finished.path\" : \"/tmp\""
"  },"
"  \"transformations\" : {"
"    \"fromFix\" : {"
"      \"type\" : \"com.github.jcustenborder.kafka.connect.transform.fix.FromFIX$Value\""
"    }"
"  },"
"  \"output\" : {"
"    \"sourcePartition\" : { },"
"    \"sourceOffset\" : { },"
"    \"topic\" : \"fix\","
"    \"kafkaPartition\" : 0,"
"    \"valueSchema\" : {"
"      \"name\" : \"fix42.NewOrderSingle\","
"      \"type\" : \"STRUCT\","
"      \"isOptional\" : false,"
"      \"fieldSchemas\" : {"
"        \"Account\" : {"
"          \"type\" : \"STRING\","
"          \"parameters\" : {"
"            \"fix.field\" : \"1\""
"          },"
"          \"isOptional\" : true"
"        },"
"        \"CashOrderQty\" : {"
"          \"type\" : \"FLOAT64\","
"          \"parameters\" : {"
"            \"fix.field\" : \"152\""
"          },"
"          \"isOptional\" : true"
"        },"
"        \"CheckSum\" : {"
"          \"type\" : \"STRING\","
"          \"parameters\" : {"
"            \"fix.field\" : \"10\""
"          },"
"          \"isOptional\" : true"
"        },"
"        \"ClOrdID\" : {"
"          \"type\" : \"STRING\","
"          \"parameters\" : {"
"            \"fix.field\" : \"11\""
"          },"
"          \"isOptional\" : true"
"        },"
"        \"ClearingAccount\" : {"
"          \"type\" : \"STRING\","
"          \"parameters\" : {"
"            \"fix.field\" : \"440\""
"          },"
"          \"isOptional\" : true"
"        },"
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
