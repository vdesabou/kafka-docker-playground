#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     aws s3 cp --only-show-errors s3://kafka-docker-playground/3rdparty/IBM-MQ-Install-Java-All.jar .
fi

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

cd ${DIR}/security
log "🔐 Generate keys and certificates used for SSL"
#./certs-create.sh
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    sudo chmod -R a+rw .
fi
cd ${DIR}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.mtls-repro-4102.yml"

# https://github.com/ibm-messaging/mq-container/blob/7f85fcf7db2749bfeb314e93cef83f0c506c4812/incubating/mqadvanced-server-dev/10-dev.mqsc.tpl

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.confluent.connect.jms \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "TRACE"
# }'

docker exec -i ibmmq runmqsc QM1 << EOF
DISPLAY QMGR ALL
DISPLAY QMGR CHLAUTH
DISPLAY CHANNEL(DEV.APP.SVRCONN)
DISPLAY CHLAUTH(DEV.APP.SVRCONN)
EOF

log "Set CHCKCLNT OPTIONAL"
docker exec -i ibmmq runmqsc QM1 << EOF
DEFINE AUTHINFO('DEV.AUTHINFO') AUTHTYPE(IDPWOS) CHCKCLNT(OPTIONAL) CHCKLOCL(OPTIONAL) ADOPTCTX(YES) REPLACE
ALTER QMGR CONNAUTH('DEV.AUTHINFO')
REFRESH SECURITY(*) TYPE(CONNAUTH)
EXIT
EOF

log "Disabling CHLAUTH"
docker exec -i ibmmq runmqsc QM1 << EOF
ALTER QMGR CHLAUTH(DISABLED)
EXIT
EOF

log "Set MCAUSER to empty"
docker exec -i ibmmq runmqsc QM1 << EOF
ALTER CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN)  MCAUSER('')
EXIT
EOF

log "Refresh security"
docker exec -i ibmmq runmqsc QM1 << EOF
REFRESH SECURITY
EXIT
EOF

log "Set the channel authentication to required so that both the server and client will need to provide a trusted certificate"
docker exec -i ibmmq runmqsc QM1 << EOF
ALTER CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) SSLCAUTH(REQUIRED)
EXIT
EOF

log "Force our queue manager to pick up these changes"
docker exec -i ibmmq runmqsc QM1 << EOF
REFRESH SECURITY(*) TYPE(SSL)
EXIT
EOF

log "Verify TLS is active on IBM MQ: it should display SSLCIPH(ANY_TLS12) and SSLCAUTH(REQUIRED)"
docker exec -i ibmmq runmqsc QM1 << EOF
DISPLAY QMGR ALL
DISPLAY QMGR CHLAUTH
DISPLAY CHANNEL(DEV.APP.SVRCONN)
DISPLAY CHLAUTH(DEV.APP.SVRCONN)
EOF

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
               "mq.username": "",
               "mq.password": "",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "mq.tls.truststore.location": "/tmp/truststore.jks",
               "mq.tls.truststore.password": "confluent",
               "mq.tls.keystore.location": "/tmp/keystore.jks",
               "mq.tls.keystore.password": "confluent",
               "mq.ssl.cipher.suite":"TLS_RSA_WITH_AES_128_CBC_SHA256",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source-mtls/config | jq .

sleep 5

docker container logs --tail=300 ibmmq

# Getting when ALTER CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN)  MCAUSER('')
# 2021-09-21T11:15:36.159Z AMQ8077W: Entity 'appuser' has insufficient authority to access object QM1 [qmgr]. [CommentInsert1(appuser), CommentInsert2(QM1 [qmgr]), CommentInsert3(connect)]
# 2021-09-21T11:15:36.159Z AMQ9557E: Queue Manager User ID initialization failed for 'appuser'. [ArithInsert1(2), ArithInsert2(2035), CommentInsert1(appuser)]


sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MyKafkaTopicName --from-beginning --max-messages 2
