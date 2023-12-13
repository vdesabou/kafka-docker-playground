# IBM MQ Source connector



## Objective

Quickly test [IBM MQ Source](https://docs.confluent.io/kafka-connect-ibmmq-source/current/overview.html) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900).

Download [IBM-MQ-Install-Java-All.jar](https://ibm.biz/mq92javaclient) (for example `9.3.4.0-IBM-MQ-Install-Java-All.jar`) and place it in `./IBM-MQ-Install-Java-All.jar`

![IBM download page](Screenshot1.png)

## How to run

Without SSL:

```
$ playground run -f ibm-mq<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

with SSL encryption:

```
$ playground run -f ibm-mq-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f ibm-mq-mtls<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
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
playground topic consume --topic MyKafkaTopicName --min-expected-messages 2 --timeout 60
```

Results:

```
{"messageID":"ID:414d5120514d3120202020202020202012e9b860012c0040","messageType":"text","timestamp":1622731076690,"deliveryMode":1,"correlationID":null,"replyTo":null,"destination":null,"redelivered":false,"type":null,"expiration":0,"priority":0,"properties":{"JMS_IBM_Format":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"MQSTR   "}},"JMS_IBM_PutDate":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"20210603"}},"JMS_IBM_Character_Set":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"ISO-8859-1"}},"JMSXDeliveryCount":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":1},"long":null,"float":null,"double":null,"string":null},"JMS_IBM_MsgType":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":8},"long":null,"float":null,"double":null,"string":null},"JMSXUserID":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"mqm         "}},"JMS_IBM_Encoding":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":546},"long":null,"float":null,"double":null,"string":null},"JMS_IBM_PutTime":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"14375669"}},"JMSXAppID":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"amqsput                     "}},"JMS_IBM_PutApplType":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":6},"long":null,"float":null,"double":null,"string":null}},"bytes":null,"map":null,"text":{"string":"Message 1"}}
{"messageID":"ID:414d5120514d3120202020202020202012e9b860022c0040","messageType":"text","timestamp":1622731076690,"deliveryMode":1,"correlationID":null,"replyTo":null,"destination":null,"redelivered":false,"type":null,"expiration":0,"priority":0,"properties":{"JMS_IBM_Format":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"MQSTR   "}},"JMS_IBM_PutDate":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"20210603"}},"JMS_IBM_Character_Set":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"ISO-8859-1"}},"JMSXDeliveryCount":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":1},"long":null,"float":null,"double":null,"string":null},"JMS_IBM_MsgType":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":8},"long":null,"float":null,"double":null,"string":null},"JMSXUserID":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"mqm         "}},"JMS_IBM_Encoding":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":546},"long":null,"float":null,"double":null,"string":null},"JMS_IBM_PutTime":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"14375669"}},"JMSXAppID":{"propertyType":"string","boolean":null,"byte":null,"short":null,"integer":null,"long":null,"float":null,"double":null,"string":{"string":"amqsput                     "}},"JMS_IBM_PutApplType":{"propertyType":"integer","boolean":null,"byte":null,"short":null,"integer":{"int":6},"long":null,"float":null,"double":null,"string":null}},"bytes":null,"map":null,"text":{"string":"Message 2"}}
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
               "mq.ssl.cipher.suite":"TLS_RSA_WITH_AES_128_CBC_SHA256",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source-ssl/config | jq .
```

Note:

* `"mq.ssl.cipher.suite":"TLS_RSA_WITH_AES_128_CBC_SHA256"` is required
* `KAFKA_OPTS: "-Dcom.ibm.mq.cfg.useIBMCipherMappings=false"` is also required

### With SSL encryption + Mutual TLS auth

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
