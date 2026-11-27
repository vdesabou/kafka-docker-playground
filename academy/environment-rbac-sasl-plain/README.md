# Academy: exercises on the rbac-sasl-plain environment

Reproduction models of the [🧑‍🎓 Playground Academy](https://kafka-docker-playground.io/#/academy) that need RBAC (Confluent
Server authorizer, MDS, LDAP users: `playground start-environment --environment rbac-sasl-plain`):

| Model | Mistake | Exercise |
| --- | --- | --- |
| `rbac-repro-000031-sink-not-authorized-own-service-account.sh` | a connector with its own `principal.service.name` (`appSA`), which has no role binding | [the connector runs as its own service account, and is not authorized](https://kafka-docker-playground.io/#/academy?id=rbac-the-connector-runs-as-its-own-service-account-and-is-not-authorized) |

The lab `other/deep-dive-labs/academy-areas.sh` replays it and its fix every night.
