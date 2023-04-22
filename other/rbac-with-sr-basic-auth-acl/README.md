# RBAC

## Description

This is a basic RBAC environment based on [environment/rbac-sasl-plain](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/rbac-sasl-plain) with removing primary Schema Registry from the RBAC setup. It is then secured with BASIC authentication and (topic-) ACL authorization. Standard clients as well as Connect and ksqlDB will support thi setup but C3 only supports global RBAC settings, i.e. either for all components or for none. In this example, we will spin up a second follower schema registry that is RBAC-enabled so C3 can have read-only access for schemas.

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