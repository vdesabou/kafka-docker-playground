#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/9.0.0.8-IBM-MQ-Install-Java-All.jar ]
then
     if [ -z "$CI" ]
     then
          # not running with github actions
          logerror "ERROR: ${DIR}/9.0.0.8-IBM-MQ-Install-Java-All.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
     fi
fi

if [ ! -f ${DIR}/com.ibm.mq.allclient.jar ]
then
     # install deps
     log "Getting com.ibm.mq.allclient.jar and jms.jar from 9.0.0.8-IBM-MQ-Install-Java-All.jar"
     docker run --rm -v ${DIR}/9.0.0.8-IBM-MQ-Install-Java-All.jar:/tmp/9.0.0.8-IBM-MQ-Install-Java-All.jar -v ${DIR}/install:/tmp/install openjdk:8 java -jar /tmp/9.0.0.8-IBM-MQ-Install-Java-All.jar --acceptLicense /tmp/install
     cp ${DIR}/install/wmq/JavaSE/jms.jar ${DIR}/
     cp ${DIR}/install/wmq/JavaSE/com.ibm.mq.allclient.jar ${DIR}/
     rm -rf ${DIR}/install
fi

mkdir -p ${DIR}/mtls
cd ${DIR}/mtls
if [ -z "$CI" ]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

rm -f server.crt
rm -f server.csr
rm -f server.key
rm -f ca.crt
rm -f ca.key
rm -f truststore.jks

log "Creating a Root Certificate Authority (CA)"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"
log "Generate the IBM MQ server key and certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=ibmmq"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt

log "Generate truststore.jks"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -noprompt -keystore /tmp/truststore.jks -alias CARoot -import -file /tmp/ca.crt -storepass confluent -keypass confluent

if [ -z "$CI" ]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
rm server.csr

log "Generating the Client Key and Certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -nodes -out /tmp/client.csr -keyout /tmp/client.key -subj "/CN=connect"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl x509 -req -in /tmp/client.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/client.crt

# Sign and import the CA cert into the keystore
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -noprompt -keystore /tmp/keystore.jks -alias CARoot -import -file /tmp/ca.crt -storepass confluent -keypass confluent

# Sign and import the host certificate into the keystore
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -noprompt -keystore /tmp/keystore.jks -alias $i -import -file /tmp/client.crt -storepass confluent -keypass confluent

if [ -z "$CI" ]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
rm client.csr

cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.mtls.yml"

log "Verify TLS is active on IBM MQ: it should display SSLCIPH(ANY_TLS12)"
docker exec -i ibmmq runmqsc QM1 << EOF
DISPLAY CHANNEL(DEV.APP.SVRCONN)
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
               "mq.username": "app",
               "mq.password": "passw0rd",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "mq.tls.truststore.location": "/tmp/truststore.jks",
               "mq.tls.truststore.password": "confluent",
               "mq.tls.keystore.location": "/tmp/keystore.jks",
               "mq.tls.keystore.password": "confluent",
               "mq.ssl.cipher.suite":"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source-mtls/config | jq .

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MyKafkaTopicName --from-beginning --max-messages 2
