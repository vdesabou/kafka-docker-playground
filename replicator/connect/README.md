# Using Confluent Replicator as connector

## Description

This is the very good example from [MDC and single views 🌍](https://github.com/framiere/mdc-with-replicator-and-regexrouter)

We have 2 regions: `US` and `EUROPE` each have a topic with sales that happened regionaly.
We want on each region to have a way to see **all** sales in **all** regions.

## How to run

With no security in place (PLAINTEXT):

```
$ ./connect-plaintext.sh
```

With no SSL encryption, SASL/PLAIN authentication:

```
$ ./connect-sasl-plain.sh
```

With no SSL encryption, Kerberos GSSAPI authentication:

```
$ ./connect-kerberos.sh
```