# IBM MQ Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-ibm-mq-source/asciinema.gif?raw=true)

## Objective

Quickly test [IBM MQ Source](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/index.html) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

* Download [9.0.0.8-IBM-MQ-Install-Java-All.jar](https://www-945.ibm.com/support/fixcentral/swg/selectFixes?product=ibm%2FWebSphere%2FWebSphere+MQ&fixids=9.0.0.4-IBM-MQ-Install-Java-All&source=dbluesearch&function=fixId&parent=ibm/WebSphere) and place it in `./9.0.0.8-IBM-MQ-Install-Java-All.jar`

![IBM download page](Screenshot1.png)

## How to run

Without SSL:

```
$ ./ibm-mq.sh
```

with SSL encryption:

```
$ ./ibm-mq-ssl.sh
```

with SSL encryption + Mutual TLS authentication:

```
$ ./ibm-mq-mtls.sh
```

## Details of what the script is doing

### Without SSL

The connector is created with:

```bash
$ curl -X PUT \
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
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source/config | jq .
```

Messages are sent to IBM MQ using:

```bash
$ docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF
```

Verify we have received the data in MyKafkaTopicName topic:

```bash
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MyKafkaTopicName --from-beginning --max-messages 2
```

Results:

```
{"messageID":"ID:414d5120514d3120202020202020202012e9b860012c0040","messageType":"text","timestamp":1622731076690,"deliveryMode":1,"correlationID":null,"replyTo":null,"destination":null,"redelivered":false,"type":null,"expiration":0,"priority":0,"properties":{"JMS_IBM_Format":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"MQSTR   "}},"JMS_IBM_PutDate":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"20210603"}},"JMS_IBM_Character_Set":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"ISO-8859-1"}},"JMSXDeliveryCount":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":1},"long":null,"float":null,"double":null,"string":null},"JMS_IBM_MsgType":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":8},"long":null,"float":null,"double":null,"string":null},"JMSXUserID":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"mqm         "}},"JMS_IBM_Encoding":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":546},"long":null,"float":null,"double":null,"string":null},"JMS_IBM_PutTime":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"14375669"}},"JMSXAppID":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"amqsput                     "}},"JMS_IBM_PutApplType":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":6},"long":null,"float":null,"double":null,"string":null}},"bytes":null,"map":null,"text":{"string":"Message 1"}}
{"messageID":"ID:414d5120514d3120202020202020202012e9b860022c0040","messageType":"text","timestamp":1622731076690,"deliveryMode":1,"correlationID":null,"replyTo":null,"destination":null,"redelivered":false,"type":null,"expiration":0,"priority":0,"properties":{"JMS_IBM_Format":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"MQSTR   "}},"JMS_IBM_PutDate":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"20210603"}},"JMS_IBM_Character_Set":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"ISO-8859-1"}},"JMSXDeliveryCount":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":1},"long":null,"float":null,"double":null,"string":null},"JMS_IBM_MsgType":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":8},"long":null,"float":null,"double":null,"string":null},"JMSXUserID":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"mqm         "}},"JMS_IBM_Encoding":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":546},"long":null,"float":null,"double":null,"string":null},"JMS_IBM_PutTime":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"14375669"}},"JMSXAppID":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"amqsput                     "}},"JMS_IBM_PutApplType":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":6},"long":null,"float":null,"double":null,"string":null}},"bytes":null,"map":null,"text":{"string":"Message 2"}}
```

### With SSL

Creating a Root Certificate Authority (CA)

```bash
$ openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"
Generate the IBM MQ server key and certificate
```

```bash
$ openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=ibmmq"
$ openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt
```

Generate truststore.jks

```bash
$ keytool -noprompt -keystore /tmp/truststore.jks -alias CARoot -import -file /tmp/ca.crt -storepass confluent -keypass confluent
```

Creating IBM MQ source connector

```bash
$ curl -X PUT \
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
               "mq.ssl.cipher.suite":"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source-ssl/config | jq .
```

Note:

* `"mq.ssl.cipher.suite":"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384"` is required
* `KAFKA_OPTS: "-Dcom.ibm.mq.cfg.useIBMCipherMappings=false"` is also required

### With SSL encryption + Mutual TLS auth

Starting up ibmmq container to get generated cert from server

```bash
$ docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.mtls.yml" up -d ibmmq
```

Create a keystore (a .kdb file) using the MQ security tool command runmqakm

```
$ docker exec -i ibmmq bash << EOF
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
```

Copy IBM MQ certificate

```
docker cp ibmmq:/var/mqm/qmgrs/QM1/ssl/QM.cert .
```

Create client truststore.jks with server certificate

```
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -importcert -alias server-certificate -noprompt -file /tmp/QM.cert -keystore /tmp/truststore.jks -storepass confluent
```

Setting up mutual authentication
Set the channel authentication to required so that both the server and client will need to provide a trusted

```certificate
docker exec -i ibmmq runmqsc QM1 << EOF
ALTER CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) SSLCAUTH(REQUIRED)
EXIT
EOF
```

Create client keystore.jks

```
rm -f keystore.jks
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -genkeypair -noprompt -keyalg RSA -alias client-key -keystore /tmp/keystore.jks -storepass confluent -keypass confluent -storetype pkcs12 -dname "CN=connect,OU=TEST,O=CONFLUENT,L=PaloAlto,S=Ca,C=US"
```

Extract the client certificate to the file client.crt

```
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -noprompt -export -alias client-key -file /tmp/client.crt -keystore /tmp/keystore.jks -storepass confluent -keypass confluent
```

Copy client.crt to ibmmq container

```
docker cp client.crt ibmmq:/tmp/client.crt
```

Add client certificate to the queue manager’s key repository, so the server knows that it can trust the client

```
docker exec -i ibmmq bash -c "cd /var/mqm/qmgrs/QM1/ssl && runmqakm -cert -add -db key.kdb -stashed -label ibmwebspheremqapp -file /tmp/client.crt"
```

Force our queue manager to pick up these changes

```
docker exec -i ibmmq runmqsc QM1 << EOF
REFRESH SECURITY(*) TYPE(SSL)
EXIT
EOF
```

List the certificates in the key repository

```
docker exec -i ibmmq bash -c "cd /var/mqm/qmgrs/QM1/ssl && runmqakm -cert -list -db key.kdb -stashed"
```

Creating IBM MQ source connector

```bash
$ curl -X PUT \
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
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source-mtls/config | jq .
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
