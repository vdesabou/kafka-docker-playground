# How to use Data Contracts with Schema Registry

## Objective

This is an example of usage of Data Contracts:

- a CEL rule passed by the producer (`value.rule.set`), on topic `test-data-contracts`
- a data contract on `orders-value`, built with the playground CLI: the schema
  (`playground schema register --schema @data/order.avsc`), then metadata (`--metadata-property owner=OrdersTeam …`),
  then a rule set (`--rule-set @data/order_ruleset.json`: `message.totalPriceCents > 0`)
- `playground schema test-rules` checks records against the rules without producing them (a non-positive price
  fails `checkTotalPrice`), then the console producer shows the same verdict
- the current limits of REST Proxy and ksqlDB with data contracts

The override `docker-compose.plaintext.yml` sets `SCHEMA_REGISTRY_RESOURCE_EXTENSION_CLASS:
io.confluent.kafka.schemaregistry.rulehandler.RuleSetResourceExtension`: without it, the registry silently drops the
rules (`playground schema register` warns).

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

## Resources
- https://docs.confluent.io/platform/current/schema-registry/fundamentals/data-contracts.html#quick-start
- https://www.confluent.io/en-gb/blog/data-contracts-confluent-schema-registry/
