# Replicator (using Confluent Cloud)

## Cloud to Cloud example

### Prerequisites

When the script run, it will ask to login using ccloud, this will be the destination cluster.

You need to fill information for source cluster in `env.source` file:

```
$ cat env.source

BOOTSTRAP_SERVERS_SRC="xxx.confluent.cloud:9092"
CLOUD_KEY_SRC="xxx"
CLOUD_SECRET_SRC="xxxx"
SASL_JAAS_CONFIG_SRC="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$CLOUD_KEY_SRC\" password=\"$CLOUD_SECRET_SRC\";"
SCHEMA_REGISTRY_URL_SRC="https://xxxx.confluent.cloud"
SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC="xxx:xxx"
```

The `topic-replicator`in the source cluster should be created manually

### How to run

```
$ ./connect-cloud-to-cloud.sh
```
## OnPrem to Cloud example

### How to run

```
$ ./connect-onprem-to-cloud.sh
```
## Avro Converter examples

The two example above are using default `value.converter`=`io.confluent.connect.replicator.util.ByteArrayConverter` which does not preserve the schemas.

There are two scripts ending with `avro.sh`that are using `value.converter`=`io.confluent.connect.avro.AvroConverter` that preserve schemas.

This is documented [here](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/index.html#replicating-messages-with-schemas)

Note: In order to remove avro converter metadata added in schema, we can set:

```json
"value.converter.connect.meta.data": false
```

Before:

```json
{
  "connect.name": "myrecord",
  "connect.version": 1,
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
```

After:

```json
{
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
```

### Cloud to Cloud example

## OnPrem to Cloud example

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
