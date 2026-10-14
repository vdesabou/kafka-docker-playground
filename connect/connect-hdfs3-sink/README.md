# HDFS 3 Sink connector

## Objective

Quickly test the [HDFS 3 Sink](https://docs.confluent.io/kafka-connectors/hdfs3-sink/current/overview.html) connector.

## Prerequisites

* Not supported with the `cfk` environment (exits with code 111).
* `hdfs3-sink-hive4.sh` builds a local `kdp/hadoop:3.3.6` image from the `Dockerfile` in this folder.

## How to run

```bash
playground run -f hdfs3-sink.sh
```

| Script | Description |
| --- | --- |
| `hdfs3-sink.sh` | Single namenode HDFS (Hadoop 3.1.3) with Hive integration. For connector versions 2.0.0 and later, Hive integration is disabled (see below) |
| `hdfs3-sink-hive4.sh` | Hadoop 3.3.6 with Hive 4 metastore and HiveServer2, for Hive integration with connector versions 2.0.0 and later |
| `hdfs3-sink-ha-kerberos.sh` | HDFS in high availability (2 namenodes, `store.url=hdfs://sh`) secured with Kerberos, no Hive integration |

## What the script does

1. Starts the environment with the HDFS (and Hive) containers and opens permissions on `/` in HDFS.
2. Creates the HDFS 3 sink connector on topic `hdfs-topic` with `flush.size=3`, Avro values and Hive integration on database `testhive` (when enabled).
3. Produces 10 Avro records (`{"f1":"value%g"}`) to `hdfs-topic`.
4. Lists `/topics/hdfs-topic/partition=0` in HDFS and displays one Avro file with `playground tools read-avro-file`.
5. When Hive integration is enabled, queries the Hive table with `beeline` and looks for `value1`.

The Kerberos variant first makes `namenode1` the active namenode, creates a `connect` principal and keytab in the KDC and configures `hdfs.authentication.kerberos`, `connect.hdfs.principal`, `connect.hdfs.keytab` and `hdfs.namenode.principal`.

## Hive compatibility

HDFS 3 Sink connector versions 2.0.0 and later are only compatible with Hive Metastore 4.0.1 and later. `hdfs3-sink.sh` therefore sets `hive.integration=false` for these versions; use `hdfs3-sink-hive4.sh` if you need Hive integration.
