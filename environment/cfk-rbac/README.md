# CFK with RBAC

## Description

Same deployment as [cfk](../cfk/) (Confluent for Kubernetes on k3d), with RBAC configured the CFK way: `authorization.type: rbac` on the CP resources, MDS with an LDAP provider, a `KafkaRestClass`, bearer secrets for the components and `ConfluentRolebinding` resources. No encryption, SASL/PLAIN authentication against LDAP.

The users are the ones of [rbac-sasl-plain](../rbac-sasl-plain/), so connectors, `playground topic` and `playground rbac` commands behave the same on both environments.

* 1 KRaft controller
* 1 broker, with the Metadata Service (MDS) on `http://kafka.confluent.svc.cluster.local:8090` (`http://localhost:8091` on the host)
* 1 OpenLDAP (`openldap-0`), the only source of users and groups
* 1 connect, 1 schema-registry

Control Center, ksqlDB and REST Proxy are not supported (`--enable-control-center`, `--enable-ksqldb` and `--enable-rest-proxy` are ignored).

Listeners of the broker:

| Listener | Port | Used by |
| --- | --- | --- |
| `INTERNAL` | `kafka:9071` | SASL/PLAIN, any LDAP user with its LDAP password (`playground` CLI as `admin`, connector `confluent.topic.*` clients) |
| `TOKEN` | `kafka:9073` | SASL/OAUTHBEARER with MDS tokens, added by CFK: connect workers, connectors, schema-registry |
| `REPLICATION` | `kafka:9072` | inter-broker, `admin` |

## How to run

```bash
playground start-environment --environment cfk-rbac
```

or run a connector example on it:

```bash
playground run -f connect/connect-datagen-source/datagen-source.sh --environment cfk-rbac
```

## Users

Users are the LDAP users of [rbac-sasl-plain/scripts/security/ldap_users](../rbac-sasl-plain/scripts/security/ldap_users), loaded in the `openldap-ldifs` ConfigMap.

| User | Password | Used for |
| --- | --- | --- |
| `admin` | `admin-secret` | super user: inter-broker, KRaft controller, `KafkaRestClass`, `playground` CLI (`/mnt/secrets/playground-client/client.properties` in `connect-0`) |
| `superUser` | `superUser` | super user, `SystemAdmin` on every cluster, `playground rbac` commands, Schema Registry REST API |
| `connectAdmin` | `connectAdmin` | connect workers |
| `schemaregistryUser` | `schemaregistryUser` | schema-registry |
| `connectorSubmitter` | `connectorSubmitter` | creates connectors (`Connector` resources, Connect REST API, `playground connector`) |
| `connectorSA` | `connectorSA` | connectors run as this principal (`principal.service.name`, added by `playground connector create-or-update`) |
| `clientAvroCli` | `clientAvroCli` | Schema Registry access of `playground topic produce/consume` |
| `alice`, `barnie`, `charlie` | `<user>-secret` | `SystemAdmin`, `ClusterAdmin`, `UserAdmin` |

Secrets holding these credentials are created by [cfk-rbac.sh](cfk-rbac.sh).

## Role bindings

CFK creates the role bindings of the component principals itself (`internal-connect-*`, `internal-schemaregistry-*`). The other default role bindings are `ConfluentRolebinding` resources in [role-bindings.yaml](role-bindings.yaml):

```bash
kubectl -n confluent get confluentrolebinding
playground rbac role-binding list --principal User:connectorSA
```

Cluster ids used in role bindings: connect is `confluent.connect`, schema registry is `id_schemaregistry_confluent`.

## Change permissions

Either the CFK way, with a `ConfluentRolebinding` resource:

```bash
kubectl apply -f - << EOF
apiVersion: platform.confluent.io/v1beta1
kind: ConfluentRolebinding
metadata:
  name: alice-orders
  namespace: confluent
spec:
  principal:
    type: user
    name: alice
  role: DeveloperRead
  resourcePatterns:
    - resourceType: Topic
      name: orders
      patternType: LITERAL
EOF
```

or with `playground rbac`, which calls the MDS REST API through the `localhost:8091` port-forward (these role bindings are not visible as Kubernetes resources):

```bash
playground rbac role-binding create --principal User:alice --role DeveloperRead --resource Topic:orders
playground rbac user add --user bob --password bob-secret --group KafkaDevelopers
```
