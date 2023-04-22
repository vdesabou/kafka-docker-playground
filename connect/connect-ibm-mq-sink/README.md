# IBM MQ Sink connector



## Objective

Quickly test [IBM MQ Sink](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/sink/index.html#quick-start) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900).

Download [IBM-MQ-Install-Java-All.jar](https://ibm.biz/mq92javaclient) (for example `9.2.0.3-IBM-MQ-Install-Java-All.jar`) and place it in `./IBM-MQ-Install-Java-All.jar`

![IBM download page](Screenshot1.png)

## How to run

Without SSL:

```
$ playground run -f ibm-mq-sink<tab>
```

with SSL encryption:

```
$ playground run -f ibm-mq-sink-ssl<tab>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f ibm-mq-sink-mtls<tab>
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

🔐 Generate keys and certificates used for SSL

```bash
./security/certs-create.sh
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
               "mq.tls.truststore.location": "/tmp/truststore.jks",
               "mq.tls.truststore.password": "confluent",
               "mq.ssl.cipher.suite":"TLS_RSA_WITH_AES_128_CBC_SHA256",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-sink-ssl/config | jq .
```

Note:

* `"mq.ssl.cipher.suite":"TLS_RSA_WITH_AES_128_CBC_SHA256"` is required
* `KAFKA_OPTS: "-Dcom.ibm.mq.cfg.useIBMCipherMappings=false"` is also required

### With SSL encryption + Mutual TLS auth

Creating IBM MQ sink connector

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
               "mq.username": "",
               "mq.password": "",
               "mq.tls.truststore.location": "/tmp/truststore.jks",
               "mq.tls.truststore.password": "confluent",
               "mq.tls.keystore.location": "/tmp/keystore.jks",
               "mq.tls.keystore.password": "confluent",
               "mq.ssl.cipher.suite":"TLS_RSA_WITH_AES_128_CBC_SHA256",
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

Note: with mTLS, we do not require a username/password to connect to the Queue, this is done by commenting `MQ_APP_PASSWORD` on `ibmmq` container:

```yml
# MQ_APP_PASSWORD: passw0rd
```

Therefore we can set:

```json
"mq.username": "",
"mq.password": "",
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
