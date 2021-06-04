# IBM MQ Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-ibm-mq-sink/asciinema.gif?raw=true)

## Objective

Quickly test [IBM MQ Sink](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/sink/index.html#quick-start) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

* Download [9.0.0.8-IBM-MQ-Install-Java-All.jar](https://www-945.ibm.com/support/fixcentral/swg/selectFixes?product=ibm%2FWebSphere%2FWebSphere+MQ&fixids=9.0.0.4-IBM-MQ-Install-Java-All&source=dbluesearch&function=fixId&parent=ibm/WebSphere) and place it in `./9.0.0.8-IBM-MQ-Install-Java-All.jar`

![IBM download page](Screenshot1.png)

## How to run

Without SSL:

```
$ ./ibm-mq-sink.sh
```

with SSL encryption:

```
$ ./ibm-mq-sink-ssl.sh
```

with SSL encryption + Mutual TLS authentication:

```
$ ./ibm-mq-sink-mtls.sh
```

## Details of what the script is doing

### Without SSL

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.IbmMqSinkConnector",
                    "topics": "sink-messages",
                    "mq.hostname": "ibmmq",
                    "mq.port": "1414",
                    "mq.transport.type": "client",
                    "mq.queue.manager": "QM1",
                    "mq.channel": "DEV.APP.SVRCONN",
                    "mq.username": "app",
                    "mq.password": "passw0rd",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-sink/config | jq .
```

Sending messages to topic `sink-messages`:

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF
```

Verify message received in `DEV.QUEUE.1` queue:

```bash
$ docker exec ibmmq bash -c "/opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1"
```

Results:

```
AMQSBCG0 - starts here
**********************

 MQOPEN - 'DEV.QUEUE.1'


 MQGET of message number 1, CompCode:0 Reason:0
****Message descriptor****

  StrucId  : 'MD  '  Version : 2
  Report   : 0  MsgType : 8
  Expiry   : -1  Feedback : 0
  Encoding : 273  CodedCharSetId : 1208
  Format : 'MQHRF2  '
  Priority : 4  Persistence : 1
  MsgId : X'414D5120514D312020202020202020203F8EA85D1EA66A20'
  CorrelId : X'000000000000000000000000000000000000000000000000'
  BackoutCount : 0
  ReplyToQ       : '                                                '
  ReplyToQMgr    : 'QM1                                             '
  ** Identity Context
  UserIdentifier : 'app         '
  AccountingToken :
   X'0000000000000000000000000000000000000000000000000000000000000000'
  ApplIdentityData : '                                '
  ** Origin Context
  PutApplType    : '28'
  PutApplName    : 'cli.ConnectDistributed      '
  PutDate  : '20191017'    PutTime  : '16024736'
  ApplOriginData : '    '

  GroupId : X'000000000000000000000000000000000000000000000000'
  MsgSeqNumber   : '1'
  Offset         : '0'
  MsgFlags       : '0'
  OriginalLength : '-1'

****   Message      ****

 length - 174 of 174 bytes

00000000:  5246 4820 0000 0002 0000 009C 0000 0111           'RFH ............'
00000010:  0000 04B8 4D51 5354 5220 2020 0000 0000           '....MQSTR   ....'
00000020:  0000 04B8 0000 0020 3C6D 6364 3E3C 4D73           '....... <mcd><Ms'
00000030:  643E 6A6D 735F 7465 7874 3C2F 4D73 643E           'd>jms_text</Msd>'
00000040:  3C2F 6D63 643E 2020 0000 0050 3C6A 6D73           '</mcd>  ...P<jms'
00000050:  3E3C 4473 743E 7175 6575 653A 2F2F 2F44           '><Dst>queue:///D'
00000060:  4556 2E51 5545 5545 2E31 3C2F 4473 743E           'EV.QUEUE.1</Dst>'
00000070:  3C54 6D73 3E31 3537 3133 3238 3136 3733           '<Tms>15713281673'
00000080:  3632 3C2F 546D 733E 3C44 6C76 3E32 3C2F           '62</Tms><Dlv>2</'
00000090:  446C 763E 3C2F 6A6D 733E 2020 5468 6973           'Dlv></jms>  This'
000000A0:  2069 7320 6D79 206D 6573 7361 6765                ' is my message  '



 No more messages
 MQCLOSE
 MQDISC
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
               "connector.class": "io.confluent.connect.jms.IbmMqSinkConnector",
                    "topics": "sink-messages",
                    "mq.hostname": "ibmmq",
                    "mq.port": "1414",
                    "mq.transport.type": "client",
                    "mq.queue.manager": "QM1",
                    "mq.channel": "DEV.APP.SVRCONN",
                    "mq.username": "app",
                    "mq.password": "passw0rd",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "mq.ssl.cipher.suite":"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-sink-ssl/config | jq .
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
               "connector.class": "io.confluent.connect.jms.IbmMqSinkConnector",
               "topics": "sink-messages",
               "mq.hostname": "ibmmq",
               "mq.port": "1414",
               "mq.transport.type": "client",
               "mq.queue.manager": "QM1",
               "mq.channel": "DEV.APP.SVRCONN",
               "mq.username": "app",
               "mq.password": "passw0rd",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-sink-mtls/config | jq .
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
