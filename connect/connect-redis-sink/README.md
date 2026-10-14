# Redis Sink connector

## Objective

Quickly test the [Redis Sink](https://docs.confluent.io/kafka-connectors/redis/current/overview.html) connector (`com.github.jcustenborder.kafka.connect.redis.RedisSinkConnector`).

## Prerequisites

With CP 8.x, connector version 0.0.7 or later is required (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f redis-sink.sh
```

The Redis UI can be accessed at [http://localhost:5540/](http://localhost:5540/).

## What the script does

1. Starts the environment with a Redis container.
2. Produces 3 messages (keys `key1` to `key3`, values `value1` to `value3`) to topic `users` with `playground topic produce`.
3. Creates the Redis sink connector `redis-sink` (`redis.hosts=redis:6379`, string key and value converters).
4. Checks that Redis database 1 (the connector default `redis.database`) contains the data keys and the offset key `__kafka.offset.users.0`, and that `key1` is `value1`.

Note: the connector writes to database 1, so pass `-n 1` to `redis-cli`:

```bash
playground container exec --container redis --command "redis-cli -n 1 GET key1"
playground container exec --container redis --command "redis-cli -n 1 GET __kafka.offset.users.0"
```
