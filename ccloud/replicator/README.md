# Replicator (using Confluent Cloud)

## OnPrem to Cloud examples with ByteArrayConverter

### How to run

With Connect:

```
$ ./connect-onprem-to-cloud.sh
```

With Replicator executable:

```
$ ./executable-onprem-to-cloud.sh
```
## OnPrem to Cloud examples with AvroConverter

The two example above are using default `value.converter`=`io.confluent.connect.replicator.util.ByteArrayConverter` which does not preserve the schemas.

There are two scripts ending with `avro.sh` that are using `value.converter`=`io.confluent.connect.avro.AvroConverter` that preserve schemas.

This is documented [here](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/index.html#replicating-messages-with-schemas)

### How to run

With Connect:

```
$ ./connect-onprem-to-cloud-avro.sh
```

With Replicator executable:

```
$ ./executable-onprem-to-cloud-avro.sh
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
