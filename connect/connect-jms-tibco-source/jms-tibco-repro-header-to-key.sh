#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco

if [ ! -f ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     logerror "ERROR: ${DIR}/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
     exit 1
fi

if [ ! -f ${DIR}/tibjms.jar ]
then
     log "${DIR}/tibjms.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/tibjms.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

if [ ! -f ${DIR}/jms-2.0.jar ]
then
     log "${DIR}/jms-2.0.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/jms-2.0.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/jms-2.0.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

if test -z "$(docker images -q tibems:latest)"
then
     log "Building TIBCO EMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:latest . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending EMS JSON message in queue connector-quickstart"
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgProducer -user admin -queue connector-quickstart m1 m2 m3 m4 m5'

# Struct
# {
#     messageID=ID:E4EMS-SERVER.15E286CCE3:5,
#     messageType=text,
#     timestamp=1579707637122,
#     deliveryMode=2,
#     destination=
#           Struct
#           {
#                destinationType=queue,
#                name=connector-quickstart
#           },
#     redelivered=false,
#     expiration=0,
#     priority=4,
#     properties=
#     {
#         JMSXDeliveryCount=
#           Struct
#           {
#                propertyType=integer,
#                integer=1
#           },
#         titi=
#           Struct
#           {
#                propertyType=string,
#                string=toto
#           }
#     },
#     text=m5
# }

log "Creating JMS TIBCO source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "from-tibco-messages",
                    "java.naming.factory.initial": "com.tibco.tibjms.naming.TibjmsInitialContextFactory",
                    "java.naming.provider.url": "tibjmsnaming://tibco-ems:7222",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "errors.tolerance": "all",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true",
                    "errors.retry.timeout": "600000",
                    "errors.retry.delay.max.ms": "30000",
                    "transforms": "FlattenJson",
                    "transforms.FlattenJson.type":"org.apache.kafka.connect.transforms.Flatten$Value",
                    "transforms.flatten.delimiter": ".",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-tibco-source/config | jq_docker_cli .

sleep 5

# [2020-01-22 16:05:37,670] ERROR Error encountered in task jms-tibco-source-0. Executing stage 'TRANSFORMATION' with class 'org.apache.kafka.connect.transforms.Flatten$Value', where source record is = SourceRecord{sourcePartition={}, sourceOffset={}} ConnectRecord{topic='from-tibco-messages', kafkaPartition=null, key=Struct{messageID=ID:E4EMS-SERVER.15E2872A63:5}, keySchema=Schema{io.confluent.connect.jms.Key:STRUCT}, value=Struct{messageID=ID:E4EMS-SERVER.15E2872A63:5,messageType=text,timestamp=1579709133001,deliveryMode=2,destination=Struct{destinationType=queue,name=connector-quickstart},redelivered=false,expiration=0,priority=4,properties={JMSXDeliveryCount=Struct{propertyType=integer,integer=1}, titi=Struct{propertyType=string,string=toto}},text=m5}, valueSchema=Schema{io.confluent.connect.jms.Value:STRUCT}, timestamp=1579709133001, headers=ConnectHeaders(headers=)}. (org.apache.kafka.connect.runtime.errors.LogReporter)
# org.apache.kafka.connect.errors.DataException: Flatten transformation does not support MAP for record without schemas (for field properties).
#         at org.apache.kafka.connect.transforms.Flatten.buildUpdatedSchema(Flatten.java:196)
#         at org.apache.kafka.connect.transforms.Flatten.applyWithSchema(Flatten.java:146)
#         at org.apache.kafka.connect.transforms.Flatten.apply(Flatten.java:75)
#         at org.apache.kafka.connect.runtime.TransformationChain.lambda$apply$0(TransformationChain.java:50)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:128)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:162)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:104)
#         at org.apache.kafka.connect.runtime.TransformationChain.apply(TransformationChain.java:50)

log "Verify we have received the data in from-tibco-messages topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic from-tibco-messages --from-beginning --max-messages 1
