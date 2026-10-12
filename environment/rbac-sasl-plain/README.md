# RBAC with SASL/PLAIN

## Description

Confluent Platform with RBAC, no encryption, SASL/PLAIN authentication against LDAP. It is based on [confluentinc/cp-demo](https://github.com/confluentinc/cp-demo), kept as simple as possible:

* 1 broker (KRaft controller, or ZooKeeper before CP 8) with the Metadata Service (MDS) on `http://localhost:8091`
* 1 OpenLDAP (`openldap`), the only source of users and groups
* 1 connect, 1 schema-registry, and optionally control-center and ksqlDB

Listeners of the broker:

| Listener | Port | Used by |
| --- | --- | --- |
| `INTERNAL` | `broker:9092` | SASL/PLAIN, any LDAP user with its LDAP password (inter-broker traffic and the `playground` CLI use `admin`) |
| `TOKEN` | `broker:10091` | SASL/OAUTHBEARER with MDS tokens: connect, schema-registry, ksqlDB, control-center |

## How to run

```bash
playground start-environment --environment rbac-sasl-plain
```

or `playground run` and pick `environment/rbac-sasl-plain/start.sh`.

Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021), log in with `superUser`/`superUser`, or with another user below to see how the view changes with permissions.

ksqlDB CLI:

```bash
playground container exec -c ksqldb-cli --command "ksql -u ksqlDBUser -p ksqlDBUser http://ksqldb-server:8088"
```

## Users

Users are the LDAP users of the `openldap` container, loaded from [scripts/security/ldap_users](scripts/security/ldap_users) at startup. The broker authenticates SASL/PLAIN clients against LDAP, so every LDAP user can connect on `broker:9092` with its LDAP password, and log in to MDS, Control Center, Schema Registry and the Connect REST API with basic auth.

| User | Password | Used for |
| --- | --- | --- |
| `admin` | `admin-secret` | super user: inter-broker, metrics reporter, `playground` CLI (`client_without_interceptors.config`) |
| `mds` | `mds` | super user |
| `superUser` | `superUser` | super user, `SystemAdmin` on every cluster, `playground rbac` commands |
| `schemaregistryUser` | `schemaregistryUser` | schema-registry |
| `connectAdmin` | `connectAdmin` | connect workers |
| `connectorSubmitter` | `connectorSubmitter` | creates connectors (Connect REST API, `playground connector`) |
| `connectorSA` | `connectorSA` | connectors run as this principal (`principal.service.name`) |
| `ksqlDBAdmin`, `ksqlDBUser` | same as user | ksqlDB |
| `controlcenterAdmin` | `controlcenterAdmin` | control-center |
| `clientAvroCli` | `clientAvroCli` | Schema Registry access of `playground topic produce/consume` |
| `alice`, `barnie`, `charlie` | `<user>-secret` | `SystemAdmin`, `ClusterAdmin`, `UserAdmin`, to try Control Center views |
| `appSA`, `badapp`, `clientListen`, `restAdmin` | same as user | no role binding |

All users except `admin`, `badapp` and `clientAvroCli` are in the `KafkaDevelopers` group.

Users can be changed on the running environment, without restart:

```bash
playground rbac user list
playground rbac user add --user bob --password bob-secret --group KafkaDevelopers
playground rbac user delete --user bob
```

MDS picks up new group memberships (for `Group:<name>` role bindings) within its LDAP refresh interval (60 seconds by default).

## Role bindings

The default role bindings are listed in [role-bindings.txt](role-bindings.txt), one per line, and created by `start.sh` through the MDS REST API. See them on a running environment with:

```bash
playground rbac role-binding list
playground rbac role-binding list --principal User:connectorSA
```

## Change permissions

Role bindings and ACLs can be changed on the running environment with `playground rbac` (it calls the MDS REST API as `superUser`):

```bash
playground rbac role-binding create --principal User:alice --role DeveloperRead --resource Topic:orders
playground rbac role-binding create --principal User:alice --role ResourceOwner --resource Topic:orders --prefix
playground rbac role-binding create --principal User:connectorSA --role ResourceOwner --resource Subject:orders-value
playground rbac role-binding delete --principal User:alice --role DeveloperRead --resource Topic:orders
playground rbac role-binding create --file "${PWD}/role-bindings.txt"      # same format as the default file

playground rbac acl create --principal User:charlie --operation WRITE --operation DESCRIBE --resource Topic:orders
playground rbac acl create --principal User:charlie --operation READ --resource Topic:orders --kafka-acls   # regular Kafka ACL
playground rbac acl list
```

ACLs are MDS centralized ACLs by default, or regular Kafka ACLs (`kafka-acls`) with `--kafka-acls`. Both are enforced, `playground rbac acl list` shows both.

If a component needs a role binding **at startup** (before connect, schema-registry, ksqldb and control-center start), put the `playground rbac` commands in a file and pass it to `start-environment`; it is sourced right after the default role bindings are created:

```bash
playground start-environment --environment rbac-sasl-plain \
  --docker-compose-override-file "${PWD}/docker-compose.rbac-sasl-plain.yml" \
  --rbac-role-bindings-file "${PWD}/role-bindings.sh"
```

See [other/rbac-with-sr-basic-auth-acl](../../other/rbac-with-sr-basic-auth-acl/) for an example.
