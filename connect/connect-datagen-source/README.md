# Datagen Source connector

## Objective

Quickly test the [Datagen Source](https://docs.confluent.io/kafka-connectors/datagen/current/overview.html) connector.

## How to run

```bash
playground run -f datagen-source.sh
```

| Script | Description |
| --- | --- |
| `datagen-source.sh` | Generate JSON `orders` records from a custom Avro schema file |

## What the script does

1. Generates `schemas/orders.avro` and `schemas/shipments.avro` from their templates, replacing `:NOW:` with the current timestamp.
2. Creates the `datagen-orders` connector (10 tasks, 10000 iterations, `schema.filename=/tmp/schemas/orders.avro`, `schema.keyfield=orderid`, `JsonConverter` without schemas) writing to topic `orders`.
3. Waits for the connector to inject data, then verifies topic `orders` with `playground topic consume`.
4. Deletes the connector.

The script also contains commented-out connectors for topics `shipments`, `products` and `customers`, using the other schema files in `schemas/`.

Example of record:

```json
{"ordertime":1643187141000,"orderid":0,"productid":"Product_8","orderunits":0,"order_category":"train","customerid":"Customer_1797"}
```
