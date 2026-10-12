# RBAC

## Description

This is a basic RBAC environment based on [environment/rbac-sasl-plain](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/rbac-sasl-plain) allowing anonymous access to Schema Registry in an RBAC-enabled setup. This is achieved by overriding 2 properties:

```properties
confluent.schema.registry.anonymous.principal=true
authentication.skip.paths=/subjects/*,/schemas/*,/config/*,/mode/*,/compatibility/*,/contexts/*
```

Requests without credentials are mapped to the RBAC principal `User:ANONYMOUS`, which still needs role bindings: the example gives it `ResourceOwner` on `Subject:*`, then registers and lists a schema without credentials.

⚠️ `authentication.skip.paths=/*`, as in the documentation, does not work with CP 8.3.2: `/*` is the same path spec as the constraint requiring authentication on every path, which wins, and anonymous requests get `401 Unauthorized`. List the Schema Registry resources instead.

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021]), use `superUser`/`superUser`to login.

You may also log in as [other users](../../environment/rbac-sasl-plain/README.md#users) to learn how each user’s view changes depending on their permissions.

You can use ksqlDB with CLI using:

```bash
playground container exec -c ksqldb-cli --command "ksql -u ksqlDBUser -p ksqlDBUser http://ksqldb-server:8088"
```