# JMS Oracle AQ (Oracle 21c) Sink connector

## Objective

Quickly test the [JMS Sink](https://docs.confluent.io/kafka-connectors/jms-sink/current/overview.html) connector with Oracle Advanced Queuing (AQ) on Oracle Database 21c.

## Prerequisites

If you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900): a prebuilt Oracle image is downloaded from the playground S3 bucket when AWS credentials are available.

Otherwise, download Oracle Database 21c (21.3) for Linux x86-64 `LINUX.X64_213000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle21c-linux-downloads.html) and place it in this folder.

The first time you run the script, it builds the docker image `oracle/database:21.3.0-ee` (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)). It takes about 10 minutes.

**Make sure to increase the Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

With CP 8.x, the minimum supported connector version is 2.1.16 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-oracle21-sink.sh
```

## What the script does

1. Gets or builds the Oracle 21c image, starts Oracle and creates user `C##MYUSER`.
2. Copies `aqapi.jar` and `ojdbc8.jar` from the Oracle container (and downloads `jta-1.1.jar`) into the `confluentinc-kafka-connect-jms-sink` plugin `lib` folder, then starts the rest of the environment.
3. Grants the AQ privileges to `C##MYUSER` and creates the AQ queue table `PLAYGROUNDTABLE` and the queue `PLAYGROUND` (`SYS.AQ$_JMS_TEXT_MESSAGE`).
4. Produces 2 messages to topic `sink-messages` with `playground topic produce`.
5. Creates the JMS sink connector `jms-oracle-sink` (`oracle.jms.AQjmsInitialContextFactory`, `javax.jms.XAQueueConnectionFactory`, string message format).
6. Verifies that `This is my message 1` is present in queue table `PLAYGROUNDTABLE` with `sqlplus`.
