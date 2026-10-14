# IBM MQ Source connector

## Objective

Quickly test the [IBM MQ Source](https://docs.confluent.io/kafka-connectors/ibmmq-source/current/overview.html) connector.

IBM MQ runs with the Docker [image](https://github.com/ibm-messaging/mq-container) `icr.io/ibm-messaging/mq`.

## Prerequisites

Download [IBM-MQ-Install-Java-All.jar](https://ibm.biz/mq92javaclient) (for example `9.3.4.0-IBM-MQ-Install-Java-All.jar`) and save it as `./IBM-MQ-Install-Java-All.jar` in this folder (it must be downloaded manually to accept the license agreement). The scripts extract `com.ibm.mq.allclient.jar` and `jms.jar` from it.

![IBM download page](Screenshot1.png)

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900).

With CP 8+, the minimum supported connector version is 12.2.0: older `--connector-tag` values are skipped (exit code 111). `ibm-mq-eos.sh` and `ibm-mq-bindings-mode.sh` are not supported with the `cfk` environment.

## How to run

```bash
playground run -f ibm-mq.sh
```

| Script | Description |
| --- | --- |
| `ibm-mq.sh` | Basic example, user/password authentication |
| `ibm-mq-ssl.sh` | TLS encryption on channel `DEV.APP.SVRCONN` (truststore only) |
| `ibm-mq-mtls.sh` | TLS encryption + mutual TLS authentication (`SSLCAUTH(REQUIRED)`, keystore + truststore, no user/password) |
| `ibm-mq-eos.sh` | Exactly-once source (`transaction.boundary=connector`, `state.topic.name`), consumed with `read_committed` |
| `ibm-mq-bytes-message.sh` | 100 JMS `BytesMessage` sent by `JmsProducer.java`, with `ByteArrayConverter` and an `ExtractField$Value` SMT on field `bytes` |
| `ibm-mq-bindings-mode.sh` | Bindings mode (`mq.transport.type=bindings`): the Connect worker runs inside a custom image based on the IBM MQ image (CP 8.1.0 and connector 13.0.5 are hardcoded in `bindings-mode/Dockerfile`) |

## What the script does

1. Extracts the IBM MQ client jars from `IBM-MQ-Install-Java-All.jar` (first run only).
2. For SSL/mTLS variants: generates certificates with `playground tools certs-create` and configures TLS on channel `DEV.APP.SVRCONN` (mTLS also sets `SSLCAUTH(REQUIRED)` and refreshes security).
3. For the EOS variant: defines the MQ topic `MY.MQ.STATE.TOPIC` and grants user `app` the required permissions.
4. Creates the IBM MQ source connector from queue `DEV.QUEUE.1` of queue manager `QM1` to topic `MyKafkaTopicName` (`ibm-topic` for EOS).
5. Puts messages in the queue with `amqsput` (or `runjms JmsProducer` for the BytesMessage variant).
6. Verifies the records with `playground topic consume`.

## Notes

* SSL/mTLS: `"mq.ssl.cipher.suite": "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"` is required (`TLS_RSA_*` suites are disabled by default in recent JDKs), and the Connect worker needs `KAFKA_OPTS: -Dcom.ibm.mq.cfg.useIBMCipherMappings=false` (set in the docker-compose override).
* mTLS: no username/password is needed to connect to the queue manager. `MQ_APP_PASSWORD` is commented out on the `ibmmq` container, so the connector uses `"mq.username": ""` and `"mq.password": ""`.
* Bindings mode: the worker is started manually inside the container, and the final `playground topic consume` is best effort (the Kafka CLI tools are not available in that image), so the script always exits 0 at the end.
