# Test with very small retention (30 seconds) and timestamp in mircosecond


## Objective

Test bad timestamp in microseconds (https://issues.apache.org/jira/browse/KAFKA-6482)


## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

Results:

With microsecond timestamp `1581583089003000L`

```
total 8
-rw-r--r-- 1 appuser appuser        0 Jan  7 14:34 leader-epoch-checkpoint
-rw-r--r-- 1 appuser appuser 10485760 Jan  7 14:34 00000000000000000000.index
-rw-r--r-- 1 appuser appuser       43 Jan  7 14:34 partition.metadata
-rw-r--r-- 1 appuser appuser 10485756 Jan  7 14:34 00000000000000000000.timeindex
-rw-r--r-- 1 appuser appuser      462 Jan  7 14:34 00000000000000000000.lo
```

With millisecond timestamp `1581583089003L`

```
total 20
-rw-r--r-- 1 appuser appuser       43 Jan  7 14:37 partition.metadata
-rw-r--r-- 1 appuser appuser      462 Jan  7 14:37 00000000000000000000.log.deleted
-rw-r--r-- 1 appuser appuser       12 Jan  7 14:37 00000000000000000000.timeindex.deleted
-rw-r--r-- 1 appuser appuser        0 Jan  7 14:37 00000000000000000000.index.deleted
-rw-r--r-- 1 appuser appuser       56 Jan  7 14:37 00000000000000000006.snapshot
-rw-r--r-- 1 appuser appuser        0 Jan  7 14:37 00000000000000000006.log
-rw-r--r-- 1 appuser appuser        8 Jan  7 14:37 leader-epoch-checkpoint
-rw-r--r-- 1 appuser appuser 10485756 Jan  7 14:38 00000000000000000006.timeindex
```