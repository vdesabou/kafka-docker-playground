# Replicator (using Confluent Cloud)

## OnPrem to Cloud examples with ByteArrayConverter

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

### How to run

With Connect:

```
$ just use <playground run> command and search for connect-onprem-to-cloud.sh in this folder
```

With Replicator executable:

```
$ just use <playground run> command and search for executable-onprem-to-cloud.sh in this folder
```
## OnPrem to Cloud examples with AvroConverter

The two example above are using default `value.converter`=`io.confluent.connect.replicator.util.ByteArrayConverter` which does not preserve the schemas.

There are two scripts ending with `avro.sh` that are using `value.converter`=`io.confluent.connect.avro.AvroConverter` that preserve schemas.

This is documented [here](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/index.html#replicating-messages-with-schemas)

### How to run

With Connect:

```
$ just use <playground run> command and search for connect-onprem-to-cloud-avro.sh in this folder
```

With Replicator executable:

```
$ just use <playground run> command and search for executable-onprem-to-cloud-avro.sh in this folder
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
