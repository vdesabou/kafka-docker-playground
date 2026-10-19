# HDFS 3 Source connector

## Objective

Quickly test the [HDFS 3 Source](https://docs.confluent.io/kafka-connectors/hdfs3-source/current/overview.html) connector.

## Prerequisites

* Not supported with the `cfk` environment (exits with code 111).
* Connector versions 2.0.0 and later require CP 6.0.0 or later.

## How to run

```bash
playground run -f hdfs3-source.sh
```

| Script | Description |
| --- | --- |
| `hdfs3-source.sh` | Writes data to HDFS with the HDFS 3 sink connector, then reads it back with the HDFS 3 source connector |

## What the script does

1. Starts the environment with HDFS (Hadoop 3.1.3) and Hive containers and opens permissions on `/` in HDFS.
2. Creates an HDFS 3 **sink** connector on topic `hdfs-topic` (`FieldPartitioner` on `f1`) and produces 10 Avro records.
3. Lists `/topics/hdfs-topic` in HDFS and displays one Avro file with `playground tools read-avro-file`.
4. Creates the `hdfs3-source` connector (`AvroFormat`) with a `RegexRouter` transform that prefixes topic names with `copy-of-`.
5. Verifies that topic `copy-of-hdfs-topic` receives the records with `playground topic consume`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) writes Avro files of `{"f1":"benchmark message <i>"}` records (the schema of the example) to HDFS for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), in the layout of the HDFS 3 sink: `/topics/<topic>/<partition>/<topic>+0+<start>+<end>.avro`, the topic being the one written by the sink of the example (`BENCHMARK_HDFS_TOPIC` to choose another one). The files are generated with `avro-tools` and copied with `hdfs dfs -put`, which writes `<file>._COPYING_` and renames it, so the connector never reads a file being written. The example has two connectors, so name the source:

```bash
# drain of 200000 records in files of 10000 records
playground connector benchmark --connector hdfs3-source --nb-records 200000

# throughput during 2 minutes while files of 20000 records are written
playground connector benchmark --connector hdfs3-source --mode steady --duration 2m --nb-records 20000
```

The connector reads the file listed after the last one it read: the files go to a partition folder that sorts after the ones of the sink (`f1=zz-benchmark` with the `FieldPartitioner` of the example, `partition=0` with the default partitioner), with offsets that grow from one run to the next. `--shape small-txn` writes one record per file (drain only). Like the cloud storage sources, the connector reconfigures its task at each poll interval: the benchmark then counts the records in the topic, and says so.
