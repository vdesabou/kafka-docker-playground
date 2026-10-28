# HDFS 2 Sink connector

## Objective

Quickly test the [HDFS 2 Sink](https://docs.confluent.io/kafka-connectors/hdfs/current/overview.html) connector, including Hive integration.

## Prerequisites

* Not supported with the `cfk` environment (exits with code 111).
* With CP 8.3 and later, the connect container is switched to JDK 17 (see [#7862](https://github.com/vdesabou/kafka-docker-playground/issues/7862)).
* `hive-jdbc-3.1.2-standalone.jar` (basic example) and `hadoop-2.7.4.tar.gz` (Kerberos example) are downloaded automatically when missing.

## How to run

```bash
playground run -f hdfs2-sink.sh
```

| Script | Description |
| --- | --- |
| `hdfs2-sink.sh` | Single namenode HDFS with Hive integration (Hive metastore + HiveServer2) |
| `hdfs2-sink-ha-kerberos.sh` | HDFS in high availability (2 namenodes, `store.url=hdfs://sh`) secured with Kerberos, no Hive integration |

## What the script does

1. Starts the environment with the HDFS (and Hive) containers and opens permissions on `/` in HDFS.
2. Creates the HDFS sink connector on topic `hdfs-topic` with `flush.size=3`, Avro values and (basic example) `hive.integration=true` on database `testhive`.
3. Produces 10 Avro records (`{"f1":"value%g"}`) to `hdfs-topic`.
4. Lists `/topics/hdfs-topic/partition=0` in HDFS and displays one Avro file with `playground tools read-avro-file`.
5. Basic example: queries table `hdfs_topic` with `beeline` and checks `value1` is present.

The Kerberos variant first makes `namenode1` the active namenode (retried for up to 10 minutes, until both namenodes answer), creates a `connect` principal and keytab in the KDC and configures `hdfs.authentication.kerberos`, `connect.hdfs.principal`, `connect.hdfs.keytab` and `hdfs.namenode.principal`.

The namenodes are formatted (`namenode1`) and bootstrapped (`namenode2`) at container start, by two launcher plugins of the `flokkr/hadoop` image replaced with files of `ha-kerberos/`:

- `waitfor.sh` (`006_waitfor`): `namenode1` waits for the 3 journal nodes (port `8485`) and `namenode2` waits for `namenode1` (port `9820`) first (`WAITFOR`, `WAITFOR_TIMEOUT` in `docker-compose.plaintext.ha-kerberos.yml`).
- `hdfsinit.sh` (`012_hdfsinit`): an open port doesn't mean the service answers yet, so a failed `hdfs namenode -format` (for example `QuorumException: Unable to check if JNs are ready for formatting`) or `hdfs namenode -bootstrapStandby` is retried, 10 times 15 seconds apart (`HDFSINIT_RETRIES`, `HDFSINIT_RETRY_INTERVAL`). The image's plugin runs them once and starts the namenode even if they failed.
