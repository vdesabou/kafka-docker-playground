#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     aws s3 cp --only-show-errors s3://kafka-docker-playground/3rdparty/9.0.0.8-IBM-MQ-Install-Java-All.jar .
fi

if [ ! -f ${DIR}/9.0.0.8-IBM-MQ-Install-Java-All.jar ]
then
     # not running with github actions
     logerror "ERROR: ${DIR}/9.0.0.8-IBM-MQ-Install-Java-All.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi
if [ ! -f ${DIR}/com.ibm.mq.allclient.jar ]
then
     # install deps
     log "Getting com.ibm.mq.allclient.jar and jms.jar from 9.0.0.8-IBM-MQ-Install-Java-All.jar"
     docker run --rm -v ${DIR}/9.0.0.8-IBM-MQ-Install-Java-All.jar:/tmp/9.0.0.8-IBM-MQ-Install-Java-All.jar -v ${DIR}/install:/tmp/install openjdk:8 java -jar /tmp/9.0.0.8-IBM-MQ-Install-Java-All.jar --acceptLicense /tmp/install
     cp ${DIR}/install/wmq/JavaSE/jms.jar ${DIR}/
     cp ${DIR}/install/wmq/JavaSE/com.ibm.mq.allclient.jar ${DIR}/
fi

# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.mtls.yml" down -v

log "Starting up ibmmq container to get generated cert from server"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.mtls.yml" up -d ibmmq

# Verify IBM MQ has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for IBM MQ to start"
docker container logs ibmmq > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Started web server" ]]; do
sleep 10
docker container logs ibmmq > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in ibmmq container do not show 'Started web server' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "IBM MQ has started!"

# https://developer.ibm.com/components/ibm-mq/tutorials/configuring-mutual-tls-authentication-java-messaging-app/
rm -rf ${DIR}/mtls
mkdir -p ${DIR}/mtls
cd ${DIR}/mtls

log "Create a keystore (a .kdb file) using the MQ security tool command runmqakm"
docker exec -i ibmmq bash << EOF
cd /var/mqm/qmgrs/QM1/ssl
rm -f key.*
rm -f QM.*
# Create a keystore (a .kdb file) using the MQ security tool command runmqakm
runmqakm -keydb -create -db key.kdb -pw confluent -stash
chmod 640 *
# create a self-signed certificate and private key and put them in the keystore
runmqakm -cert -create -db key.kdb -stashed -dn "cn=qm,o=ibm,c=uk" -label ibmwebspheremqqm1
# let’s extract the queue manager certificate, which we’ll then give to the client application.
runmqakm -cert -extract -label ibmwebspheremqqm1 -db key.kdb -stashed -file QM.cert
EOF

log "Copy IBM MQ certificate"
docker cp ibmmq:/var/mqm/qmgrs/QM1/ssl/QM.cert .

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

log "Create client truststore.jks with server certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -importcert -alias server-certificate -noprompt -file /tmp/QM.cert -keystore /tmp/truststore.jks -storepass confluent

log "Setting up mutual authentication"

log "Set the channel authentication to required so that both the server and client will need to provide a trusted certificate"
docker exec -i ibmmq runmqsc QM1 << EOF
ALTER CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) SSLCAUTH(REQUIRED)
EXIT
EOF

log "Create client keystore.jks"
rm -f keystore.jks
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -genkeypair -noprompt -keyalg RSA -alias client-key -keystore /tmp/keystore.jks -storepass confluent -keypass confluent -storetype pkcs12 -dname "CN=connect,OU=TEST,O=CONFLUENT,L=PaloAlto,S=Ca,C=US"

log "Extract the client certificate to the file client.crt"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -noprompt -export -alias client-key -file /tmp/client.crt -keystore /tmp/keystore.jks -storepass confluent -keypass confluent

log "Copy client.crt to ibmmq container"
docker cp client.crt ibmmq:/tmp/client.crt

log "Add client certificate to the queue manager’s key repository, so the server knows that it can trust the client"
docker exec -i ibmmq bash -c "cd /var/mqm/qmgrs/QM1/ssl && runmqakm -cert -add -db key.kdb -stashed -label ibmwebspheremqapp -file /tmp/client.crt"

log "Force our queue manager to pick up these changes"
docker exec -i ibmmq runmqsc QM1 << EOF
REFRESH SECURITY(*) TYPE(SSL)
EXIT
EOF

log "List the certificates in the key repository"
docker exec -i ibmmq bash -c "cd /var/mqm/qmgrs/QM1/ssl && runmqakm -cert -list -db key.kdb -stashed"

cd ${DIR}

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.mtls.yml" up -d

../../scripts/wait-for-connect-and-controlcenter.sh

log "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF

log "Creating IBM MQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.IbmMqSinkConnector",
               "topics": "sink-messages",
               "mq.hostname": "ibmmq",
               "mq.port": "1414",
               "mq.transport.type": "client",
               "mq.queue.manager": "QM1",
               "mq.channel": "DEV.APP.SVRCONN",
               "mq.username": "",
               "mq.password": "",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-sink-mtls/config | jq .

sleep 10

log "Verify message received in DEV.QUEUE.1 queue"
docker exec ibmmq bash -c "/opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "my message" /tmp/result.log

