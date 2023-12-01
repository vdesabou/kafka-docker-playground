# How to reset an offset for a specific consumer group using the REST Proxy

## Objective

As described in [Consumer groups](https://docs.confluent.io/current/clients/consumer.html#consumer-groups), the progress of a consumer group is stored in an internal topic called `__consumer_offsets`. Once a consumer group is resumed, the next offset to be read from a topic/partition is retrieved from the `__consumer_offsets` and the consumers would continue to read from where the group left off.

There may be a requirement from a REST consumer to re-consume some of the old messages or skip messages until a specific date/time that are produced to a Kafka topic.



## How to run

Simply run:

```
$ playground run -f start<tab>
```

## Resources
- https://docs.confluent.io/current/clients/consumer.html#consumer-groups
- https://docs.confluent.io/platform/current/kafka-rest/api.html
