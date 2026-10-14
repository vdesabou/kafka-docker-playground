# Redis Sink connector

## Objective

Quickly test the [Redis Sink](https://docs.confluent.io/kafka-connectors/redis/current/overview.html) connector (`com.github.jcustenborder.kafka.connect.redis.RedisSinkConnector`).

## Prerequisites

With CP 8.x, a connector version greater than 0.0.7 is required (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f redis-sink.sh
```

The Redis UI can be accessed at [http://localhost:5540/](http://localhost:5540/).

## What the script does

1. Starts the environment with a Redis container.
2. Produces 3 messages with key `key1` to topic `users` with `playground topic produce`.
3. Creates the Redis sink connector `redis-sink` (`redis.hosts=redis:6379`, string key and value converters).
4. Runs `redis-cli COMMAND GETKEYS` for the data keys and for the offset key `__kafka.offset.users.0` stored by the connector.

Note: `COMMAND GETKEYS` only extracts the key names from the given command, it does not read the stored data. To check the content, use for example:

```bash
playground container exec --container redis --command "redis-cli GET key1"
playground container exec --container redis --command "redis-cli GET __kafka.offset.users.0"
```
