# HDFS 2 Source connector

## Objective

Quickly test the [HDFS 2 Source](https://docs.confluent.io/kafka-connectors/hdfs2-source/current/overview.html) connector.

## Prerequisites

* Not supported with the `cfk` environment (exits with code 111).
* Connector versions 2.0.0 and later require CP 6.0.0 or later.
* With CP 8.3 and later, the connect container is switched to JDK 17 (see [#7862](https://github.com/vdesabou/kafka-docker-playground/issues/7862)).

## How to run

```bash
playground run -f hdfs2-source.sh
```

| Script | Description |
| --- | --- |
| `hdfs2-source.sh` | Writes data to HDFS with the HDFS 2 sink connector, then reads it back with the HDFS 2 source connector |

## What the script does

1. Starts the environment with HDFS and Hive containers and opens permissions on `/` in HDFS.
2. Creates an HDFS 2 **sink** connector on topic `hdfs-topic` (`FieldPartitioner` on `f1`, Hive integration) and produces 10 Avro records.
3. Lists `/topics/hdfs-topic` in HDFS, displays one Avro file and checks the Hive table `hdfs_topic` with `beeline`.
4. Creates the `hdfs2-source` connector (`AvroFormat`) with a `RegexRouter` transform that prefixes topic names with `copy-of-`.
5. Verifies that topic `copy-of-hdfs-topic` receives the records with `playground topic consume`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) writes Avro files of `{"f1":"benchmark message <i>"}` records (the schema of the example) to HDFS for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), in the layout of the HDFS sink: `/topics/<topic>/<partition>/<topic>+0+<start>+<end>.avro`, the topic being the one written by the sink of the example (`BENCHMARK_HDFS_TOPIC` to choose another one). The files are generated with `avro-tools` and copied with `hdfs dfs -put`, which writes `<file>._COPYING_` and renames it, so the connector never reads a file being written. The example has two connectors, so name the source:

```bash
# drain of 100000 records in files of 10000 records
playground connector benchmark --connector hdfs2-source --nb-records 100000

# throughput during 2 minutes while files of 20000 records are written
playground connector benchmark --connector hdfs2-source --mode steady --duration 2m --nb-records 20000
```

The connector reads the file listed after the last one it read: the files go to a partition folder that sorts after the ones of the sink (`f1=zz-benchmark` with the `FieldPartitioner` of the example), with offsets that grow from one run to the next. `--shape small-txn` writes one record per file (drain only). When the connector restarts its task during the drain, the benchmark counts the records in the topic, and says so.
