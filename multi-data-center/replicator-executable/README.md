# Using Confluent Replicator as executable



## Objective

[Run Replicator as an Executable](https://docs.confluent.io/current/multi-dc-replicator/replicator-run.html#run-crep-as-an-executable)

## Description

We have 2 regions: `US` and `EUROPE` each have a topic with sales that happened regionaly.
We want on each region to have a way to see **all** sales in **all** regions.

## How to run

With no security in place (PLAINTEXT):

```
$ just use <playground run> command and search for executable-plaintext.sh in this folder
```

With no SSL encryption, SASL/PLAIN authentication:

```
$ just use <playground run> command and search for executable-sasl-plain.sh in this folder
```

With no SSL encryption, Kerberos GSSAPI authentication:

```
$ just use <playground run> command and search for executable-kerberos.sh in this folder
```
