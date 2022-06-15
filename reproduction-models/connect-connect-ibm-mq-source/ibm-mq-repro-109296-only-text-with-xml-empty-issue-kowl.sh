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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-109296-only-text-with-xml-empty-issue-kowl.yml"


log "Creating IBM MQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.ibm.mq.IbmMQSourceConnector",
               "kafka.topic": "jms-topic",
               "mq.hostname": "ibmmq",
               "mq.port": "1414",
               "mq.transport.type": "client",
               "mq.queue.manager": "QM1",
               "mq.channel": "DEV.APP.SVRCONN",
               "mq.username": "app",
               "mq.password": "passw0rd",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "transforms": "extractPayload",
               "transforms.extractPayload.type": "org.apache.kafka.connect.transforms.ExtractField$Value",
               "transforms.extractPayload.field": "text",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter", 
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source-xml/config | jq .

sleep 5

# to compile I did on my laptop:
# CLASSPATH=.:$PWD/jms.jar:$PWD/com.ibm.mq.allclient.jar:${CLASSPATH}
# export CLASSPATH
# javac JMSProducer.java
log "Sending multiline message to DEV.QUEUE.1 JMS queue:"
docker cp repro-109296-JmsProducer.class.txt ibmmq:/opt/mqm/samp/jms/samples/JmsProducer.class
docker exec -i ibmmq /opt/mqm/java/bin/runjms JmsProducer -m QM1 -d DEV.QUEUE.1 -h localhost -p 1414 -l DEV.APP.SVRCONN -u app -w passw0rd

sleep 5

log "Verify we have received the data in jms-topic topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic jms-topic --from-beginning 


# <?xml version = "1.0" encoding = "UTF-8"?>
# <MYServices>
#  <header>
#   <Version>1.0</Version>
#   <SrvType>OML</SrvType>
#   <SrvName>REQ_BALANCE_ENQUIRY</SrvName>
#   <SrcApp>BNK</SrcApp>
#   <OrgId>BLA</OrgId>
#  </header>
#  <body>
#   <srv_req>
#    <req_credit_card_balance_enquiry>
#     <card_no>12345678</card_no>
#    </req_credit_card_balance_enquiry>
#   </srv_req>
#  </body>
# </MYServices>

# Struct{messageID=ID:414d5120514d31202020202020202020a89ca962014c0040,messageType=text,timestamp=1655289887326,deliveryMode=2,destination=Struct{destinationType=queue,name=queue:///DEV.QUEUE.1},redelivered=false,expiration=0,priority=4,properties={JMS_IBM_Format=Struct{propertyType=string,string=MQSTR   }, JMS_IBM_PutDate=Struct{propertyType=string,string=20220615}, JMS_IBM_Character_Set=Struct{propertyType=string,string=UTF-8}, JMSXDeliveryCount=Struct{propertyType=integer,integer=1}, JMS_IBM_MsgType=Struct{propertyType=integer,integer=8}, JMSXUserID=Struct{propertyType=string,string=app         }, JMS_IBM_Encoding=Struct{propertyType=integer,integer=273}, JMS_IBM_PutTime=Struct{propertyType=string,string=10444733}, JMSXAppID=Struct{propertyType=string,string=JmsProducer                 }, JMS_IBM_PutApplType=Struct{propertyType=integer,integer=28}},text=<?xml version = "1.0" encoding = "UTF-8"?>
# <MYServices>
#  <header>
#   <Version>1.0</Version>
#   <SrvType>OML</SrvType>
#   <SrvName>REQ_BALANCE_ENQUIRY</SrvName>
#   <SrcApp>BNK</SrcApp>
#   <OrgId>BLA</OrgId>
#  </header>
#  <body>
#   <srv_req>
#    <req_credit_card_balance_enquiry>
#     <card_no>12345678</card_no>
#    </req_credit_card_balance_enquiry>
#   </srv_req>
#  </body>
# </MYServices>
# }

# <?xml version="1.0"?><note><to>Tove</to><from>Jani</from><heading>Reminder</heading><body>Don't forget me this weekend!</body></note>

# in kowl:

# [
#     {
#         "partitionID": 0,
#         "offset": 0,
#         "timestamp": 1655289993060,
#         "compression": "uncompressed",
#         "isTransactional": false,
#         "headers": [],
#         "key": {
#             "payload": "Struct{messageID=ID:414d5120514d31202020202020202020a89ca96201500040}",
#             "encoding": "text",
#             "schemaId": 0
#         },
#         "value": {
#             "payload": {
#                 "MYServices": {
#                     "header": {
#                         "OrgId": "BLA",
#                         "Version": "1.0",
#                         "SrvType": "OML",
#                         "SrvName": "REQ_BALANCE_ENQUIRY",
#                         "SrcApp": "BNK"
#                     },
#                     "body": {
#                         "srv_req": {
#                             "req_credit_card_balance_enquiry": {
#                                 "card_no": "12345678"
#                             }
#                         }
#                     }
#                 }
#             },
#             "encoding": "xml",
#             "schemaId": 0
#         }
#     }
# ]