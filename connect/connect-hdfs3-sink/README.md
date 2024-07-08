# HDFS 3 Sink connector



## Objective

Quickly test [HDFS 3 Sink](https://docs.confluent.io/current/connect/kafka-connect-hdfs/hdfs3/index.html#kconnect-long-hdfs-3-sink-connector) connector.

Note: HIVE integration is only available when using CP < 6.x or a non UBI8 image, because otherwise images are using JDK 11 which is not supported by HADOOP. The connector would fail with:

```
[2021-05-26 15:47:45,399] ERROR Got exception: java.lang.ClassCastException class [Ljava.lang.Object; cannot be cast to class [Ljava.net.URI; ([Ljava.lang.Object; and [Ljava.net.URI; are in module java.base of loader 'bootstrap') (org.apache.hadoop.hive.metastore.utils.MetaStoreUtils)
java.lang.ClassCastException: class [Ljava.lang.Object; cannot be cast to class [Ljava.net.URI; ([Ljava.lang.Object; and [Ljava.net.URI; are in module java.base of loader 'bootstrap')
```

## How to run

Simply run:

```
$ just use <playground run> command and search for hdfs3-sink.sh in this folder
```

or with Kerberos:

```
$ just use <playground run> command and search for hdfs2-sink-ha-kerberos.sh in this folder
```
