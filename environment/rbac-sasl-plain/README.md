# RBAC

## Description

This is mostly based on [confluentinc/cp-demo](https://github.com/confluentinc/cp-demo), but the idea is to have the simplest setup possible

This is a deployment with no encryption but with SASL/PLAIN authentication:

* 1 zookeeper
* 1 broker
* 1 connect
* 1 schema-registry
* 1 control-center

## How to run

Simply run:

```
$ ./start.sh
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021]), use `superUser`/`superUser`to login.

You may also log in as [other users](https://github.com/confluentinc/cp-demo/tree/5.4.1-post/scripts//security/ldap_users) to learn how each user’s view changes depending on their permissions.