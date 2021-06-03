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

Generating the Client Key and Certificate

```bash
$ openssl req -new -nodes -out /tmp/client.csr -keyout /tmp/client.key -subj "/CN=connect"
$ openssl x509 -req -in /tmp/client.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/client.crt
```

Sign and import the CA cert into the keystore

$ keytool -noprompt -keystore /tmp/keystore.jks -alias CARoot -import -file /tmp/ca.crt -storepass confluent -keypass confluent
```

Sign and import the client certificate into the keystore

$ keytool -noprompt -keystore /tmp/keystore.jks -alias $i -import -file /tmp/client.crt -storepass confluent -keypass confluent

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
               "mq.ssl.cipher.suite":"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source-mtls/config | jq .
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
