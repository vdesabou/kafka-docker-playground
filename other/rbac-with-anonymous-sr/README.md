# RBAC

## Description

This is a basic RBAC environment based on [environment/rbac-sasl-plain](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/rbac-sasl-plain) with allowing anonymous access to Schema Registry in an RBAC-enables setup. This is basically achieved by overriding 2 properties with the values:
```
confluent.schema.registry.anonymous.principal=true
authentication.skip.paths=/*
```
As a consequence, authorization won't be enforced for all paths and anonymous access will be mapped to a RBAC-principal `ANONYMOUS`. Example role-bindings for that principal are created by a helper-script. 

## How to run

Simply run:

```
$ playground run -f start<tab>
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021]), use `superUser`/`superUser`to login.

You may also log in as [other users](https://github.com/confluentinc/cp-demo/tree/5.4.1-post/scripts//security/ldap_users) to learn how each user’s view changes depending on their permissions.

You can use ksqlDB with CLI using:

```bash
$ docker exec -i ksqldb-cli ksql -u ksqlDBUser -p ksqlDBUser http://ksqldb-server:8088
```