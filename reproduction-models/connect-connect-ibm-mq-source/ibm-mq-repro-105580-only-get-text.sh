#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

get_3rdparty_file "IBM-MQ-Install-Java-All.jar"

if [ ! -f ${DIR}/IBM-MQ-Install-Java-All.jar ]
then
     # not running with github actions
     logerror "ERROR: ${DIR}/IBM-MQ-Install-Java-All.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

if [ ! -f ${DIR}/com.ibm.mq.allclient.jar ]
then
     # install deps
     log "Getting com.ibm.mq.allclient.jar and jms.jar from IBM-MQ-Install-Java-All.jar"
     if [[ "$OSTYPE" == "darwin"* ]]
     then
          # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
          rm -rf ${DIR}/install/
     else
          sudo rm -rf ${DIR}/install/
     fi
     docker run --rm -v ${DIR}/IBM-MQ-Install-Java-All.jar:/tmp/IBM-MQ-Install-Java-All.jar -v ${DIR}/install:/tmp/install openjdk:8 java -jar /tmp/IBM-MQ-Install-Java-All.jar --acceptLicense /tmp/install
     cp ${DIR}/install/wmq/JavaSE/lib/jms.jar ${DIR}/
     cp ${DIR}/install/wmq/JavaSE/lib/com.ibm.mq.allclient.jar ${DIR}/
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-105580-only-get-text.yml"


log "Creating IBM MQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.ibm.mq.IbmMQSourceConnector",
                    "kafka.topic": "MyKafkaTopicName",
                    "mq.hostname": "ibmmq",
                    "mq.port": "1414",
                    "mq.transport.type": "client",
                    "mq.queue.manager": "QM1",
                    "mq.channel": "DEV.APP.SVRCONN",
                    "mq.username": "app",
                    "mq.password": "passw0rd",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter", 
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "transforms": "ExtractField",
                    "transforms.ExtractField.type": "org.apache.kafka.connect.transforms.ExtractField$Value",
                    "transforms.ExtractField.field": "text"
          }' \
     http://localhost:8083/connectors/ibm-mq-source/config | jq .

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
10,"XXX","2022138","145749765085","XXXXXX","XXXXXX","XXXX","0000:0001:3b96:3e7a:bf4a:0002","00db:85e1:e250:e6d9:7c00:0000:0000:0001","2022-05-18-18.57.49.420141","XXXXXXX ",0000,1,560,"A","2010-06-20","9999-12-31","2010-06-18","0100966009          ","MI",1,"   ","A","2010-06-20-04.09.19.006919","2010-06-20-04.09.19.006919",23,"N","2",1,560,"A","2010-06-18","9999-12-31","2010-06-18","0100966009          ","MI",1,"   ","A","2010-06-20-04.09.19.006919","2010-06-20-04.09.19.006919",23,"N","2"

EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic MyKafkaTopicName --from-beginning --max-messages 2


# Message 1
# 10,"XXX","2022138","145749765085","XXXXXX","XXXXXX","XXXX","0000:0001:3b96:3e7a:bf4a:0002","00db:85e1:e250:e6d9:7c00:0000:0000:0001","2022-05-18-18.57.49.420141","XXXXXXX ",0000,1,560,"A","2010-06-20","9999-12-31","2010-06-18","0100966009          ","MI",1,"   ","A","2010-06-20-04.09.19.006919","2010-06-20-04.09.19.006919",23,"N","2",1,560,"A","2010-06-18","9999-12-31","2010-06-18","0100966009          ","MI",1,"   ","A","2010-06-20-04.09.19.006919","2010-06-20-04.09.19.006919",23,"N","2"
# Processed a total of 2 messages


# Struct{messageID=ID:414d5120514d3120202020202020202090788662022d0040,messageType=text,timestamp=1653032584520,deliveryMode=1,redelivered=false,expiration=0,priority=0,properties={JMS_IBM_Format=Struct{propertyType=string,string=MQSTR   }, JMS_IBM_PutDate=Struct{propertyType=string,string=20220520}, JMS_IBM_Character_Set=Struct{propertyType=string,string=ISO-8859-1}, JMSXDeliveryCount=Struct{propertyType=integer,integer=1}, JMS_IBM_MsgType=Struct{propertyType=integer,integer=8}, JMSXUserID=Struct{propertyType=string,string=mqm         }, JMS_IBM_Encoding=Struct{propertyType=integer,integer=546}, JMS_IBM_PutTime=Struct{propertyType=string,string=07430452}, JMSXAppID=Struct{propertyType=string,string=amqsput                     }, JMS_IBM_PutApplType=Struct{propertyType=integer,integer=6}},text=10,"XXX","2022138","145749765085","XXXXXX","XXXXXX","XXXX","0000:0001:3b96:3e7a:bf4a:0002","00db:85e1:e250:e6d9:7c00:0000:0000:0001","2022-05-18-18.57.49.420141","XXXXXXX ",0000,1,560,"A","2010-06-20","9999-12-31","2010-06-18","0100966009          ","MI",1,"   ","A","2010-06-20-04.09.19.006919","2010-06-20-04.09.19.006919",23,"N","2",1,560,"A","2010-06-18","9999-12-31","2010-06-18","0100966009          ","MI",1,"   ","A","2010-06-20-04.09.19.006919","2010-06-20-04.09.19.006919",23,"N","2"}
