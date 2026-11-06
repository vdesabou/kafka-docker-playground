# Explicit Topic-Subject Associations

## Objective

Quickly test [Explicit Topic-Subject Associations](https://docs.confluent.io/platform/current/schema-registry/fundamentals/explicit-topic-subject-associations.html): a Kafka topic linked directly to a Schema Registry subject, instead of a subject name derived from the topic (`TopicNameStrategy`).

Note: this needs Confluent Platform 8.4 or later (the script exits with `111`, skipped, on earlier versions).

| | Native schema (lifecycle `STRONG`) | Shared schema (lifecycle `WEAK`) |
| --- | --- | --- |
| How it is created | with the topic, `kafka-topics --create --confluent-value-association <file>` with `{"schemaType":"AVRO","schema":"..."}` | register the subject, then `kafka-configs --alter --confluent-value-association <file>` with `{"subject":"Customer"}` |
| Subject | `<topic>-value` in the context `:.<cluster id>:` | any existing subject |
| Delete the subject | blocked while the topic exists | blocked while a topic is associated with it |
| Delete the topic | deletes the association, the subject and every version | removes the association, the subject stays |

Associations are written only with the topic configs `confluent.key.association` / `confluent.value.association` (Kafka Admin API: create topic, incremental alter configs). The Schema Registry Associations API (`GET /associations/...`) is read only.

With the CLI tools, the association is a JSON file given with `--confluent-value-association` (or `--confluent-key-association`), for both `kafka-topics` and `kafka-configs`. `--config` is refused:

```
Error while executing topic command : Use --confluent-value-association <file> instead of --config for confluent.value.association
```

Settings in [docker-compose.plaintext.yml](docker-compose.plaintext.yml), on the broker **and** on the KRaft controller:

| Setting | Without it |
| --- | --- |
| `confluent.topic.subject.association.enable=true` | on the controller: `Schema association configs (confluent.*.association.*) are not supported when topic-subject association is disabled. Please enable it by setting confluent.topic.subject.association.enable=true or remove these configs.` |
| `confluent.schema.registry.url=http://schema-registry:8081` | the broker or the controller does not start: `java.lang.IllegalArgumentException: Schema Registry URL not configured. Set 'confluent.schema.registry.url' in broker config for confluent-platform deployments.` |

The serializers of CP 8.4 use `AssociatedNameStrategy` by default: the producer finds the subject through the association of the topic, and falls back to `TopicNameStrategy` when the topic has none.

> [!NOTE]
> `playground topic consume` finds the schema of a topic with `TopicNameStrategy` only: on an associated topic, it prints `topic is not using any schema for value` and displays the raw Avro bytes. Give the subject with `--value-subject` (`playground topic consume --topic customer-signups --value-subject Customer`).

## How to run

Simply run:

```bash
playground run -f start.sh
```

## Details of what the script is doing

Get the Kafka cluster id (it names the context of the native subjects):

```bash
playground broker describe | grep 'Cluster id:'
```

### Native schema

Create topic `orders` together with its `Order` schema ([order.avsc](order.avsc)):

[order-association.json](order-association.json) (the folder is mounted in the broker as `/data`):

```json
{
  "schemaType": "AVRO",
  "schema": "{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"com.example.avro\",\"fields\":[{\"name\":\"orderId\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"double\"}]}"
}
```

```bash
playground topic create --topic orders -- --confluent-value-association /data/order-association.json
```

Look up the associations of the topic:

```bash
curl -s http://localhost:8081/associations/resources/<cluster id>/orders | jq .
```

```json
[
  {
    "subject": ":.<cluster id>:orders-value",
    "resourceName": "orders",
    "resourceType": "topic",
    "associationType": "value",
    "lifecycle": "STRONG"
  }
]
```

The subject is in the context `:.<cluster id>:`, not in the default context:

```bash
playground schema get --subject orders-value --context ".<cluster id>"
```

Produce to `orders`: the producer finds `:.<cluster id>:orders-value` through the association, and no `orders-value` subject is created in the default context:

```bash
playground topic produce --topic orders --nb-messages 5 --value order.avsc
```

### Shared schema

Register `Customer` ([customer.avsc](customer.avsc)) and associate topic `customer-signups` with it:

```bash
playground schema register --subject Customer --schema @customer.avsc
playground topic create --topic customer-signups
# customer-association.json: {"subject": "Customer"}
playground topic alter --topic customer-signups --confluent-value-association /data/customer-association.json
curl -s http://localhost:8081/associations/subjects/Customer | jq .
```

The association has the lifecycle `WEAK`. Producing to `customer-signups` uses subject `Customer`, and no `customer-signups-value` subject is created:

```bash
playground topic produce --topic customer-signups --nb-messages 5 --value customer.avsc
```

Deleting subject `Customer` is refused while the topic is associated with it:

```bash
playground schema delete --subject Customer
```

```
🔥 ❌ Command failed with error code 40904
🔥 An association already exists for subject 'Customer'
```

Unlink the topic (the subject `Customer` stays):

```bash
playground topic alter --topic customer-signups --delete-config confluent.value.association
```

### Delete the topic with the native schema

Delete topic `orders` without the subject cleanup of `playground topic delete`: Schema Registry deletes the native subject `:.<cluster id>:orders-value` itself:

```bash
playground topic delete --topic orders --skip-delete-schema
```
