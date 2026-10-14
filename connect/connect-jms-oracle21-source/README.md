# JMS Oracle AQ (Oracle 21c) Source connector

## Objective

Quickly test the [JMS Source](https://docs.confluent.io/kafka-connectors/jms-source/current/overview.html) connector with Oracle Advanced Queuing (AQ) on Oracle Database 21c.

## Prerequisites

If you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900): a prebuilt Oracle image is downloaded from the playground S3 bucket when AWS credentials are available.

Otherwise, download Oracle Database 21c (21.3) for Linux x86-64 `LINUX.X64_213000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle21c-linux-downloads.html) and place it in this folder.

The first time you run the script, it builds the docker image `oracle/database:21.3.0-ee` (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)). It takes about 10 minutes.

**Make sure to increase the Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

With CP 8.x, the minimum supported connector version is 12.2.0 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-oracle21-source.sh
```

## What the script does

1. Gets or builds the Oracle 21c image, starts Oracle and creates user `C##MYUSER`.
2. Copies `aqapi.jar` and `ojdbc8.jar` from the Oracle container (and downloads `jta-1.1.jar`) into the `confluentinc-kafka-connect-jms` plugin `lib` folder, then starts the rest of the environment.
3. Grants the AQ privileges to `C##MYUSER` and creates the AQ queue table `PLAYGROUNDTABLE` and the queue `PLAYGROUND` (`SYS.AQ$_JMS_TEXT_MESSAGE`).
4. Enqueues a JMS text message `HELLO PLSQL WORLD !` in queue `PLAYGROUND` with a PL/SQL block (`DBMS_AQ.ENQUEUE`).
5. Creates the JMS source connector `jms-oracle-source` (`oracle.jms.AQjmsInitialContextFactory`, `javax.jms.XAQueueConnectionFactory`, Avro value converter).
6. Verifies that topic `jms-oracle-topic` receives the message with `playground topic consume`.

Example of record (truncated, the `properties` field contains all `JMSX*` and `JMS_Oracle*` properties):

```json
{
    "bytes": null,
    "correlationID": null,
    "deliveryMode": 2,
    "destination": {
        "io.confluent.connect.jms.Destination": {
            "destinationType": "queue",
            "name": "PLAYGROUND"
        }
    },
    "expiration": 0,
    "map": null,
    "messageID": "ID:E088787E36F30226E053020018AC3EF1",
    "messageType": "text",
    "priority": 1,
    "properties": {
        "JMSXDeliveryCount": {
            "boolean": null,
            "byte": null,
            "bytes": null,
            "double": null,
            "float": null,
            "integer": {
                "int": 1
            },
            "long": null,
            "propertyType": "integer",
            "short": null,
            "string": null
        }
    },
    "redelivered": false,
    "replyTo": null,
    "text": {
        "string": "HELLO PLSQL WORLD !"
    },
    "timestamp": 1654247330000,
    "type": null
}
```
