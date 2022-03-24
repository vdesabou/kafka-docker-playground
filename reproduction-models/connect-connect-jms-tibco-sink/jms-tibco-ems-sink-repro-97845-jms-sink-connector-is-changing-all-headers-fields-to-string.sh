#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco
cd ../../connect/connect-jms-tibco-sink/docker-tibco/
get_3rdparty_file "TIB_ems-ce_8.5.1_linux_x86_64.zip"
cd -
if [ ! -f ../../connect/connect-jms-tibco-sink/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     logerror "ERROR: ../../connect/connect-jms-tibco-sink/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
     exit 1
fi

if [ ! -f ../../connect/connect-jms-tibco-sink/tibjms.jar ]
then
     log "../../connect/connect-jms-tibco-sink/tibjms.jar missing, will get it from ../../connect/connect-jms-tibco-sink/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ../../connect/connect-jms-tibco-sink/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
     cp ../../connect/connect-jms-tibco-sink/opt/tibco/ems/8.5/lib/tibjms.jar ../../connect/connect-jms-tibco-sink/
     rm -rf ../../connect/connect-jms-tibco-sink/opt
fi

if test -z "$(docker images -q tibems:latest)"
then
     log "Building TIBCO EMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ../../connect/connect-jms-tibco-sink/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:latest . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi

# for component in producer-repro-97845
# do
#     set +e
#     log "🏗 Building jar for ${component}"
#     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
#     if [ $? != 0 ]
#     then
#         logerror "ERROR: failed to build java component "
#         tail -500 /tmp/result.log
#         exit 1
#     fi
#     set -e
# done
# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/com.github.jcustenborder \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "TRACE"
# }'


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-97845-jms-sink-connector-is-changing-all-headers-fields-to-string.yml"

log "Generate data"
docker exec -i connect bash -c 'mkdir -p /tmp/data/input/ && mkdir -p /tmp/data/error/ && mkdir -p /tmp/data/finished/ && curl -k "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > /tmp/data/input/json-spooldir-source.json'

log "Creating JSON Spool Dir Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirJsonSourceConnector",
               "input.file.pattern": "json-spooldir-source.json",
               "input.path": "/tmp/data/input",
               "error.path": "/tmp/data/error",
               "finished.path": "/tmp/data/finished",
               "halt.on.error": "false",
               "topic": "customer_avro",
               "key.schema": "{\n  \"name\" : \"com.example.users.UserKey\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    }\n  }\n}",
               "value.schema": "{\n  \"name\" : \"com.example.users.User\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    },\n    \"first_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"email\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"gender\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"ip_address\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_login\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"account_balance\" : {\n      \"name\" : \"org.apache.kafka.connect.data.Decimal\",\n      \"type\" : \"BYTES\",\n      \"version\" : 1,\n      \"parameters\" : {\n        \"scale\" : \"2\"\n      },\n      \"isOptional\" : true\n    },\n    \"country\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"favorite_color\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    }\n  }\n}"
         }' \
     http://localhost:8083/connectors/spool-dir/config | jq .


sleep 5

log "Verify we have received the data in customer_avro topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customer_avro --from-beginning --max-messages 10

# [{"topic":"customer_avro","partition":0,"offset":0,"timestamp":1648136882480,"timestampType":"CREATE_TIME","headers":[{"key":"file.name","stringValue":"json-spooldir-source.json"},{"key":"file.name.without.extension","stringValue":"json-spooldir-source"},{"key":"file.path","stringValue":"/tmp/data/input/json-spooldir-source.json"},{"key":"file.parent.dir.name","stringValue":"input"},{"key":"file.length","stringValue":"119602"},{"key":"file.offset","stringValue":"0"},{"key":"file.last.modified","stringValue":"2022-03-24T15:47:36.086Z"}],"key":"Struct{id=1}","value":{"id":1,"first_name":{"string":"Brana"},"last_name":{"string":"BoHlingolsen"},"email":{"string":"bbohlingolsen0@freewebs.com"},"gender":{"string":"Female"},"ip_address":{"string":"17.52.49.139"},"last_login":{"string":"2014-06-30T04:35:39Z"},"account_balance":{"bytes":"\fG"},"country":{"string":"CZ"},"favorite_color":{"string":"#156282"}},"__confluent_index":0}]

log "Creating JMS TIBCO EMS sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
                    "tasks.max": "1",
                    "topics": "customer_avro",
                    "java.naming.provider.url": "tibjmsnaming://tibco-ems:7222",
                    "java.naming.factory.initial": "com.tibco.tibjms.naming.TibjmsInitialContextFactory",
                    "jndi.connection.factory": "QueueConnectionFactory",
                    "java.naming.security.principal": "admin",
                    "java.naming.security.credentials": "",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "jms.forward.kafka.headers": true,
                    "jms.forward.kafka.metadata": true,
                    "transforms" : "headerToField",
                    "transforms.headerToField.type" : "com.github.jcustenborder.kafka.connect.transform.common.HeaderToField$Value",
                    "transforms.headerToField.header.mappings" : "file.path:STRING:file_path,file.name:STRING:file_name,file.last.modified:INT64(Timestamp):file_last_modified,file.length:INT32:file_length"
          }' \
     http://localhost:8083/connectors/jms-tibco-ems-sink/config | jq .

sleep 5


log "Verify we have received the data in connector-quickstart EMS queue"
docker exec -i tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgConsumer -user admin -queue connector-quickstart -nbmessages 20' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Text=" /tmp/result.log

# with "jms.forward.kafka.headers": false
# Received message: TextMessage={ Header={ JMSMessageID={ID:E4EMS-SERVER.1623C94324:21} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Mar 24 15:55:24 UTC 2022} JMSDeliveryTime={Thu Mar 24 15:55:24 UTC 2022} JMSExpiration={0} JMSPriority={4} } Properties={ JMSXDeliveryCount={Integer:1} } Text={{"id":20,"first_name":"Lorne","last_name":"Dysart","email":"ldysartj@topsy.com","gender":"Female","ip_address":"33.96.59.174","last_login":"2017-07-10T09:10:31Z","account_balance":14920.56,"country":"PH","favorite_color":"#ee9bb2","file_path":"/tmp/data/input/json-spooldir-source.json","file_name":"json-spooldir-source.json","file_last_modified":2022-03-24T15:55:08.365Z,"file_length":119554}} }

# with "jms.forward.kafka.headers": true
# Received message: TextMessage={ Header={ JMSMessageID={ID:E4EMS-SERVER.1623C95CC4:21} JMSDestination={Queue[connector-quickstart]} JMSReplyTo={null} JMSDeliveryMode={PERSISTENT} JMSRedelivered={false} JMSCorrelationID={null} JMSType={null} JMSTimestamp={Thu Mar 24 16:02:12 UTC 2022} JMSDeliveryTime={Thu Mar 24 16:02:12 UTC 2022} JMSExpiration={0} JMSPriority={4} } Properties={ file.path={String:/tmp/data/input/json-spooldir-source.json} file.name.without.extension={String:json-spooldir-source} JMSXDeliveryCount={Integer:1} file.parent.dir.name={String:input} file.name={String:json-spooldir-source.json} file.length={String:119269} file.last.modified={String:2022-03-24T16:01:56.636Z} file.offset={String:19} } Text={{"id":20,"first_name":"Mack","last_name":"Bellwood","email":"mbellwoodj@pcworld.com","gender":"Male","ip_address":"13.203.162.73","last_login":"2015-10-07T01:10:40Z","account_balance":10102.87,"country":"PT","favorite_color":"#90a5da","file_path":"/tmp/data/input/json-spooldir-source.json","file_name":"json-spooldir-source.json","file_last_modified":2022-03-24T16:01:56.636Z,"file_length":119269}} }


# Received message: TextMessage={
#      Header=
#         { 
#             JMSMessageID={ID:E4EMS-SERVER.1623C98004:21} 
#             JMSDestination={Queue[connector-quickstart]} 
#             JMSReplyTo={null} 
#             JMSDeliveryMode={PERSISTENT} 
#             JMSRedelivered={false} 
#             JMSCorrelationID={null} 
#             JMSType={null} 
#             JMSTimestamp={Thu Mar 24 16:11:36 UTC 2022} 
#             JMSDeliveryTime={Thu Mar 24 16:11:36 UTC 2022} 
#             JMSExpiration={0} 
#             JMSPriority={4} } 
            
#             Properties=
#                 { 
#                     file.path={String:/tmp/data/input/json-spooldir-source.json} 
#                     file.name.without.extension={String:json-spooldir-source} 
#                     JMSXDeliveryCount={Integer:1} 
#                     file.parent.dir.name={String:input} 
#                     file.name={String:json-spooldir-source.json} 
#                     KAFKA_OFFSET={Long:19} 
#                     file.length={String:119501} 
#                     file.last.modified={String:2022-03-24T16:11:21.647Z} 
#                     KAFKA_PARTITION={Integer:0} 
#                     KAFKA_TOPIC={String:customer_avro} 
#                     file.offset={String:19} 
#                 } 
                
#             Text=
#                 {
#                     {
#                         "id": 20,
#                         "first_name": "Hamel",
#                         "last_name": "Dimitresco",
#                         "email": "hdimitrescoj@hp.com",
#                         "gender": "Male",
#                         "ip_address": "104.51.108.144",
#                         "last_login": "2017-02-10T22:55:17Z",
#                         "account_balance": 16510.27,
#                         "country": "CA",
#                         "favorite_color": "#a36d2d",
#                         "file_path": "/tmp/data/input/json-spooldir-source.json",
#                         "file_name": "json-spooldir-source.json",
#                         "file_last_modified": 2022 - 03 - 24 T16: 11: 21.647 Z,
#                         "file_length": 119501
#                     }
#                 }
#             }